import ActivityKit
import AlarmKit
import AppIntents
import AVFAudio
import Foundation
import SwiftUI

// task_023 スパイク S-E。AlarmKit で「アプリを開くまで消えない・本人の声で大音量」が
// どこまで作れるかを、コンパイルの通る API だけで確かめるための最小アプリ。
// SaydoCore には依存しない。App/ と Packages/ には一切触れない。

// MARK: - メタデータ

/// AlarmAttributes は Metadata: AlarmMetadata を要求する。スパイクでは中身を持たない。
struct SpikeAlarmMetadata: AlarmMetadata {}

// MARK: - 連鎖アラームの共有状態

/// 連鎖アラームの ID と実行ログ。App Group は使わず UserDefaults.standard に置く。
/// LiveActivityIntent はアプリ本体のプロセスで実行されるため、同一 suite で足りる。
enum AlarmChainStore {
    private static let pendingIDsKey = "spike.alarm.pendingIDs"
    private static let logKey = "spike.alarm.log"
    private static let logLimit = 40

    static func savePending(_ ids: [UUID]) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: pendingIDsKey)
    }

    static func pendingIDs() -> [UUID] {
        let raw = UserDefaults.standard.stringArray(forKey: pendingIDsKey) ?? []
        return raw.compactMap { UUID(uuidString: $0) }
    }

    static func clearPending() {
        UserDefaults.standard.removeObject(forKey: pendingIDsKey)
    }

    /// 登録済みの連鎖アラームを全て取り消す。取り消せた件数を返す。
    @discardableResult
    static func cancelChain(reason: String) -> Int {
        let ids = pendingIDs()
        var cancelled = 0
        for id in ids {
            do {
                try AlarmManager.shared.cancel(id: id)
                cancelled += 1
            } catch {
                appendLog("cancel 失敗 \(id.uuidString.prefix(8)): \(error)")
            }
        }
        clearPending()
        appendLog("\(reason): \(cancelled)/\(ids.count) 件を取り消した")
        return cancelled
    }

    static func appendLog(_ line: String) {
        let stamp = Self.formatter.string(from: Date())
        var lines = UserDefaults.standard.stringArray(forKey: logKey) ?? []
        lines.append("[\(stamp)] \(line)")
        if lines.count > logLimit {
            lines.removeFirst(lines.count - logLimit)
        }
        UserDefaults.standard.set(lines, forKey: logKey)
    }

    static func log() -> [String] {
        UserDefaults.standard.stringArray(forKey: logKey) ?? []
    }

    static func clearLog() {
        UserDefaults.standard.removeObject(forKey: logKey)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

// MARK: - Open インテント

/// アラート上の「開く」ボタンから起動される。secondaryButtonBehavior = .custom のときに使われる。
/// iOS 26 で openAppWhenRun は deprecated（"Please provide 'supportedModes' instead"）なので
/// supportedModes を使う。
///
/// **`.foreground(.immediate)` と書いてはいけない。**
/// AppIntents のメタデータ抽出（Metadata.appintents/extract.actionsdata）は static func 形式の
/// `.foreground(_:)` を定数畳み込みできず、黙って `supportedModes = 1`（= `.background` と同値）を
/// 書き出す。static var の `.foreground` なら 2 になる。ビルドは両方通るので、書き間違えても
/// コンパイラは何も言わない。実測は docs/spikes/alarm-spike.md の「supportedModes の罠」を参照。
struct OpenSaydoIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "SAYDO を開く"
    static let supportedModes: IntentModes = .foreground

    init() {}

    func perform() async throws -> some IntentResult {
        AlarmChainStore.cancelChain(reason: "Open インテント実行")
        return .result()
    }
}

// MARK: - サウンドの 3 パターン

enum SpikeSoundMode: String, CaseIterable, Identifiable, Sendable {
    /// (a) システム既定音。
    case systemDefault
    /// (b) アプリバンドル同梱の chime.caf（IMA4 / 6 秒）。
    case bundledChime
    /// (c) バンドル外。起動後に録音して Library/Sounds/declaration.caf に書いたもの。
    case recordedDeclaration

    var id: String { rawValue }

    var label: String {
        switch self {
        case .systemDefault: "(a) 既定音 .default"
        case .bundledChime: "(b) バンドル同梱 chime.caf"
        case .recordedDeclaration: "(c) Library/Sounds の録音 declaration.caf"
        }
    }

    /// 拡張子なしのファイル名。
    var baseName: String? {
        switch self {
        case .systemDefault: nil
        case .bundledChime: "chime"
        case .recordedDeclaration: "declaration"
        }
    }

    /// ActivityKit の AlertSound は struct で、`.default`（static var）と
    /// `.named(_:)`（static func）の 2 つだけを公開している。enum の case ではない。
    func alertSound(includeExtension: Bool) -> AlertConfiguration.AlertSound {
        guard let baseName else { return .default }
        return .named(includeExtension ? "\(baseName).caf" : baseName)
    }
}

// MARK: - モデル

@MainActor
@Observable
final class AlarmSpikeModel {
    /// 連鎖アラームの本数と間隔。最初の 1 本目は「今から 2 分後」。
    static let chainCount = 5
    static let firstDelay: TimeInterval = 2 * 60
    static let chainInterval: TimeInterval = 60
    static let recordingSeconds: TimeInterval = 10

    var authorizationState: AlarmManager.AuthorizationState = .notDetermined
    var soundMode: SpikeSoundMode = .systemDefault
    /// `.named` に拡張子を含めるかどうか。実機でどちらが鳴るかを 1 ビルドで比較するための切替。
    var includeExtension = true
    var pendingAlarms: [Alarm] = []
    var outputVolume: Float = 0
    var recordingState = "未録音"
    var isRecording = false
    var lastError: String?
    var log: [String] = []

    private var recorder: AVAudioRecorder?

    var declarationURL: URL {
        Self.soundsDirectory.appending(path: "declaration.caf")
    }

    static var soundsDirectory: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return library.appending(path: "Sounds", directoryHint: .isDirectory)
    }

    var declarationFileDescription: String {
        let url = declarationURL
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
              let size = attributes[.size] as? NSNumber else {
            return "未作成（\(url.path(percentEncoded: false))）"
        }
        return "\(size.intValue) バイト（\(url.path(percentEncoded: false))）"
    }

    var bundledChimeDescription: String {
        guard let url = Bundle.main.url(forResource: "chime", withExtension: "caf") else {
            return "バンドルに chime.caf が無い"
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? NSNumber)??.intValue
        return "chime.caf \(size.map(String.init) ?? "?") バイト"
    }

    // MARK: 権限

    func refreshAuthorization() {
        authorizationState = AlarmManager.shared.authorizationState
    }

    func requestAuthorization() async {
        do {
            authorizationState = try await AlarmManager.shared.requestAuthorization()
            AlarmChainStore.appendLog("requestAuthorization → \(Self.describe(authorizationState))")
        } catch {
            lastError = "requestAuthorization 失敗: \(error)"
        }
        refresh()
    }

    static func describe(_ state: AlarmManager.AuthorizationState) -> String {
        switch state {
        case .notDetermined: "未確認"
        case .denied: "拒否"
        case .authorized: "許可"
        @unknown default: "不明"
        }
    }

    // MARK: 連鎖アラーム

    func scheduleChain() async {
        lastError = nil
        let base = Date().addingTimeInterval(Self.firstDelay)
        var scheduled: [UUID] = []

        for index in 0..<Self.chainCount {
            let id = UUID()
            let fireDate = base.addingTimeInterval(Double(index) * Self.chainInterval)
            let configuration = AlarmManager.AlarmConfiguration.alarm(
                schedule: .fixed(fireDate),
                attributes: makeAttributes(),
                secondaryIntent: OpenSaydoIntent(),
                sound: soundMode.alertSound(includeExtension: includeExtension)
            )
            do {
                _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
                scheduled.append(id)
            } catch {
                lastError = "\(index + 1) 本目の schedule に失敗: \(error)"
                break
            }
        }

        AlarmChainStore.savePending(scheduled)
        AlarmChainStore.appendLog(
            "連鎖登録 \(scheduled.count)/\(Self.chainCount) 件・音=\(soundMode.label)・拡張子=\(includeExtension)"
        )
        refresh()
    }

    func cancelAll() {
        AlarmChainStore.cancelChain(reason: "手動で全取り消し")
        // 連鎖リストに載っていない残骸も掃除する。
        if let alarms = try? AlarmManager.shared.alarms {
            for alarm in alarms {
                try? AlarmManager.shared.cancel(id: alarm.id)
            }
        }
        refresh()
    }

    private func makeAttributes() -> AlarmAttributes<SpikeAlarmMetadata> {
        AlarmAttributes(
            presentation: AlarmPresentation(alert: Self.makeAlert()),
            metadata: SpikeAlarmMetadata(),
            tintColor: .orange
        )
    }

    /// iOS 26.1 で stopButton は deprecated（"This property is not used anymore"）になり、
    /// stopButton を取らない init が追加された。deploymentTarget が 26.0 なので両方を持つ。
    private static func makeAlert() -> AlarmPresentation.Alert {
        let openButton = AlarmButton(
            text: "開く",
            textColor: .white,
            systemImageName: "arrow.up.forward.app"
        )
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(
                title: "朝のあなたからです",
                secondaryButton: openButton,
                secondaryButtonBehavior: .custom
            )
        } else {
            let stopButton = AlarmButton(
                text: "とめる",
                textColor: .white,
                systemImageName: "stop.circle"
            )
            return AlarmPresentation.Alert(
                title: "朝のあなたからです",
                stopButton: stopButton,
                secondaryButton: openButton,
                secondaryButtonBehavior: .custom
            )
        }
    }

    // MARK: 録音（バンドル外のサウンド）

    func recordDeclaration() async {
        lastError = nil
        recordingState = "マイク権限を確認中"
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            recordingState = "マイク権限が無い"
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            try FileManager.default.createDirectory(
                at: Self.soundsDirectory,
                withIntermediateDirectories: true
            )

            // AlertSound.named は IMA4 / µLaw / aLaw / リニア PCM を想定した通知音と同じ制約下にある。
            // ここでは afconvert の -d ima4 と同じ形式を AVAudioRecorder に指定する。
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatAppleIMA4),
                AVSampleRateKey: 44_100.0,
                AVNumberOfChannelsKey: 1
            ]
            let recorder = try AVAudioRecorder(url: declarationURL, settings: settings)
            self.recorder = recorder
            guard recorder.record() else {
                recordingState = "録音を開始できなかった"
                return
            }
            isRecording = true
            recordingState = "録音中（\(Int(Self.recordingSeconds)) 秒）"
            try await Task.sleep(for: .seconds(Self.recordingSeconds))
            recorder.stop()
            isRecording = false
            self.recorder = nil
            recordingState = "録音済み: \(declarationFileDescription)"
            AlarmChainStore.appendLog("録音完了 → \(declarationURL.lastPathComponent)")
        } catch {
            isRecording = false
            recordingState = "録音に失敗"
            lastError = "録音失敗: \(error)"
        }
        refresh()
    }

    // MARK: 表示の更新

    func refresh() {
        authorizationState = AlarmManager.shared.authorizationState
        do {
            pendingAlarms = try AlarmManager.shared.alarms
        } catch {
            pendingAlarms = []
            lastError = "alarms の取得に失敗: \(error)"
        }
        // MPVolumeView は使わない。読むだけ。バックグラウンドから音量を変える API は AlarmKit に無い。
        outputVolume = AVAudioSession.sharedInstance().outputVolume
        log = AlarmChainStore.log()
    }

    func activateSessionForVolumeReading() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            lastError = "AVAudioSession の有効化に失敗: \(error)"
        }
        refresh()
    }

    func clearLog() {
        AlarmChainStore.clearLog()
        log = []
    }
}

// MARK: - エントリポイント

@main
struct AlarmSpikeApp: App {
    var body: some Scene {
        WindowGroup {
            AlarmSpikeView()
        }
    }
}
