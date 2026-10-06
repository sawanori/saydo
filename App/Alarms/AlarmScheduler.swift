import ActivityKit
import AlarmKit
import Foundation
import SaydoCore
import SwiftUI

// MARK: - AlarmKit の薄い包み

/// アラームの権限。`AlarmManager.AuthorizationState` を写したもの。
enum AlarmAuthorization: Sendable, Equatable {
    case notDetermined
    case denied
    case authorized
}

/// AlarmKit を呼ぶところだけを切り出した契約。`AlarmScheduler` の論理（どれを取り消し、どれを登録するか）を
/// テストできるようにするためのもので、実体は `AlarmKitBackend`、テストは記録するだけの実装を入れる。
protocol AlarmBackend: Sendable {
    func authorization() async -> AlarmAuthorization
    func requestAuthorization() async -> AlarmAuthorization
    /// 1 本を登録する。`soundName` は `Library/Sounds` のファイル名（拡張子つき）。nil なら既定の音。
    func schedule(id: UUID, fireDate: Date, soundName: String?) async throws
    /// 1 本を取り消す。登録されていない識別子ではエラーを投げてよい。
    func cancel(id: UUID) async throws
}

/// `AlarmAttributes` が要求するメタデータ。中身は持たない。
struct SaydoAlarmMetadata: AlarmMetadata {}

/// AlarmKit の実体。形は実機で動いた試作（`Spikes/AlarmSpike/AlarmSpikeApp.swift`）に合わせてある。
///
/// `AlarmManager` は `Sendable` ではないので、試作と同じく MainActor の上でだけ触る。
struct AlarmKitBackend: AlarmBackend {

    @MainActor
    func authorization() async -> AlarmAuthorization {
        Self.map(AlarmManager.shared.authorizationState)
    }

    @MainActor
    func requestAuthorization() async -> AlarmAuthorization {
        do {
            return Self.map(try await AlarmManager.shared.requestAuthorization())
        } catch {
            return Self.map(AlarmManager.shared.authorizationState)
        }
    }

    @MainActor
    func schedule(id: UUID, fireDate: Date, soundName: String?) async throws {
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: Self.makeAlert()),
            metadata: SaydoAlarmMetadata(),
            tintColor: SaydoTheme.Palette.accent
        )
        // 「とめる」はシステムの持ち物で、その 1 回だけを止める。stopIntent は渡さない（連鎖に触らない）。
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(fireDate),
            attributes: attributes,
            secondaryIntent: OpenFollowUpIntent(),
            sound: soundName.map { .named($0) } ?? .default
        )
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }

    @MainActor
    func cancel(id: UUID) async throws {
        try AlarmManager.shared.cancel(id: id)
    }

    private static func map(_ state: AlarmManager.AuthorizationState) -> AlarmAuthorization {
        switch state {
        case .authorized: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    /// iOS 26.1 で stopButton は使われなくなり、取らない init が足された。
    /// deploymentTarget が 26.0 なので両方を持つ（docs/spikes/alarm-spike.md §2.4）。
    private static func makeAlert() -> AlarmPresentation.Alert {
        let title = LocalizedStringResource(String.LocalizationValue(PromiseCopy.alarmTitle))
        let openButton = AlarmButton(
            text: LocalizedStringResource(String.LocalizationValue(PromiseCopy.alarmOpenButton)),
            textColor: .white,
            systemImageName: "arrow.up.forward.app"
        )
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(
                title: title,
                secondaryButton: openButton,
                secondaryButtonBehavior: .custom
            )
        } else {
            let stopButton = AlarmButton(
                text: LocalizedStringResource(String.LocalizationValue(PromiseCopy.alarmStopButton)),
                textColor: .white,
                systemImageName: "stop.circle"
            )
            return AlarmPresentation.Alert(
                title: title,
                stopButton: stopButton,
                secondaryButton: openButton,
                secondaryButtonBehavior: .custom
            )
        }
    }
}

// MARK: - AlarmScheduler

/// 約束の後追いの連鎖アラーム（実装計画 §17.3「追われる」/ §17.4）。
///
/// 発火時刻と識別子は `AlarmPlan` が決める。識別子は連鎖の**開始日**から再計算できるので、
/// ここは登録した識別子を覚えない。取り消しは「その日の全識別子を取り消す」で行う。
struct AlarmScheduler: AlarmScheduling {
    private let backend: any AlarmBackend
    /// 本人の声をアラーム音に書き出す先。nil なら常に既定の音。
    private let soundStore: AlarmSoundStore?
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(
        backend: any AlarmBackend = AlarmKitBackend(),
        soundStore: AlarmSoundStore?,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.backend = backend
        self.soundStore = soundStore
        self.calendar = calendar
        self.now = now
    }

    /// 本番の組み立て。声は `<container>/Library/Sounds` に書き出す。
    init(audioFileStore: AudioFileStore) {
        self.init(soundStore: .librarySounds(audioFileStore: audioFileStore))
    }

    func requestAuthorization() async -> Bool {
        await backend.requestAuthorization() == .authorized
    }

    func scheduleChain(start: Date, voiceRelativePath: String?) async -> AlarmScheduleOutcome {
        // 未確認ならここで求める。拒否済みならダイアログは出ず、そのまま戻る。
        var authorization = await backend.authorization()
        if authorization == .notDetermined {
            authorization = await backend.requestAuthorization()
        }
        guard authorization == .authorized else { return .notAuthorized }

        // 同じ日の連鎖が残っていれば、先に全部取り消す（音のファイルも消える）。
        await cancelChain(startedOn: start)

        // 過ぎた時刻の本は登録しない。
        let current = now()
        let slots = AlarmPlan.slots(start: start, calendar: calendar).filter { $0.fireDate > current }
        guard !slots.isEmpty else { return .failed }

        let soundName = voiceRelativePath.flatMap {
            soundStore?.export(relativePath: $0, for: start, calendar: calendar)
        }

        var scheduled = 0
        for slot in slots {
            do {
                try await backend.schedule(id: slot.id, fireDate: slot.fireDate, soundName: soundName)
                scheduled += 1
            } catch {
                // 1 本の失敗で残りを諦めない。登録できた分だけで追う。
                continue
            }
        }

        guard scheduled > 0 else {
            soundStore?.remove(for: start, calendar: calendar)
            return .failed
        }
        return .scheduled(count: scheduled)
    }

    func cancelChain(startedOn day: Date) async {
        for id in AlarmPlan.identifiers(on: day, calendar: calendar) {
            // 登録されていない識別子（鳴り終えた本、登録しなかった本）の失敗は無視する。
            try? await backend.cancel(id: id)
        }
        soundStore?.remove(for: day, calendar: calendar)
    }
}
