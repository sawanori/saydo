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
    /// `title` はアラームの題。
    func schedule(id: UUID, fireDate: Date, soundName: String?, title: String) async throws
    /// 1 本を取り消す。登録されていない識別子ではエラーを投げてよい。
    func cancel(id: UUID) async throws
    /// このアプリが登録しているアラームの識別子。取れなければエラーを投げる。
    func scheduledIDs() async throws -> [UUID]
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
    func schedule(id: UUID, fireDate: Date, soundName: String?, title: String) async throws {
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: Self.makeAlert(title: title)),
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

    @MainActor
    func scheduledIDs() async throws -> [UUID] {
        try AlarmManager.shared.alarms.map(\.id)
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
    private static func makeAlert(title text: String) -> AlarmPresentation.Alert {
        let title = LocalizedStringResource(String.LocalizationValue(text))
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

/// 約束の後追いのアラーム（実装計画 §17.3「追われる」/ §17.4 / §17.9）。
///
/// 発火時刻と識別子は `AlarmPlan` が決める。識別子は 日付 + 回 + 連番 から再計算できるので、
/// ここは登録した識別子を覚えない。取り消しは「その日の 1 回分」か「その日の全部」で行う。
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

    func scheduleRounds(_ rounds: [AlarmRoundRequest], on day: Date) async -> AlarmScheduleOutcome {
        // ここでは権限を求めない（起動や前面復帰のたびに呼ばれる）。求めるのは約束する画面とオンボーディング。
        guard await backend.authorization() == .authorized else { return .notAuthorized }

        // その日に残っているアラームを、先に全部取り消す。
        await cancelIdentifiers(AlarmPlan.allIdentifiers(on: day, calendar: calendar))

        // 過ぎた時刻の本は登録しない。
        let current = now()
        let planned: [(request: AlarmRoundRequest, slots: [AlarmSlot])] = rounds.map { request in
            let slots = AlarmPlan.slots(
                on: day,
                round: request.round,
                start: request.start,
                interval: request.interval,
                calendar: calendar
            )
            return (request, slots.filter { $0.fireDate > current })
        }
        .filter { !$0.slots.isEmpty }

        // 本人の声（約束の録音）は、結果を聞く回だけに使う。その日の音のファイルは 1 つ。
        let voicePath = planned
            .first { $0.request.purpose == .chase && $0.request.voiceRelativePath != nil }?
            .request.voiceRelativePath
        let soundName = voicePath.flatMap {
            soundStore?.export(relativePath: $0, for: day, calendar: calendar)
        }
        if soundName == nil {
            soundStore?.remove(for: day, calendar: calendar)
        }
        guard !planned.isEmpty else { return .scheduled(count: 0) }

        var scheduled = 0
        for (request, slots) in planned {
            let usesVoice = request.purpose == .chase && request.voiceRelativePath != nil
            let title = request.purpose == .prompt
                ? PromiseCopy.alarmPromptTitle
                : request.title ?? PromiseCopy.alarmTitle
            for slot in slots {
                do {
                    try await backend.schedule(
                        id: slot.id,
                        fireDate: slot.fireDate,
                        soundName: usesVoice ? soundName : nil,
                        title: title
                    )
                    scheduled += 1
                } catch {
                    // 1 本の失敗で残りを諦めない。登録できた分だけで追う。
                    continue
                }
            }
        }

        guard scheduled > 0 else {
            soundStore?.remove(for: day, calendar: calendar)
            return .failed
        }
        return .scheduled(count: scheduled)
    }

    func cancelRound(_ round: AlarmRound, on day: Date) async {
        await cancelIdentifiers(AlarmPlan.identifiers(on: day, round: round, calendar: calendar))
    }

    func cancelDay(_ day: Date) async {
        await cancelIdentifiers(AlarmPlan.allIdentifiers(on: day, calendar: calendar))
        soundStore?.remove(for: day, calendar: calendar)
    }

    func cancelAll() async {
        // 権限が無ければ、登録済みのアラームも無い。
        guard await backend.authorization() == .authorized else { return }
        if let registered = try? await backend.scheduledIDs() {
            await cancelIdentifiers(registered)
            return
        }
        // 一覧が取れなかった。前日・当日・翌日の、いまの識別子と旧い識別子を取り消す。
        let current = now()
        for offset in -1...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: current) else { continue }
            await cancelIdentifiers(
                AlarmPlan.allIdentifiers(on: day, calendar: calendar)
                    + AlarmPlan.legacyIdentifiers(on: day, calendar: calendar)
            )
        }
    }

    private func cancelIdentifiers(_ identifiers: [UUID]) async {
        for id in identifiers {
            // 登録されていない識別子（鳴り終えた本、登録しなかった本）の失敗は無視する。
            try? await backend.cancel(id: id)
        }
    }
}
