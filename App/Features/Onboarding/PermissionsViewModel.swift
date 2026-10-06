import AVFoundation
import Foundation
import Observation
import UIKit

/// マイクとアラームの許可（実装計画 §17.6 のオンボーディング 3 画面、task_056）。
///
/// 拒否されても止めない。マイクが無ければ文字だけで約束でき、アラームが無くても約束は残る。
/// 朝の通知の許可はここでは求めない（最初の約束が保存された後に `AppRouter` が求める）。
@MainActor
@Observable
final class PermissionsViewModel {

    /// マイクの許可状態。`AVAudioApplication.recordPermission` をそのまま持ち回さず、
    /// 画面が分岐に使う 3 状態へ写す。
    enum MicrophoneState: Sendable, Equatable {
        /// まだ一度も聞いていない。ダイアログを出せる。
        case undetermined
        case granted
        /// 断られた。ダイアログは二度と出ないので、設定アプリへ送る。
        case denied
    }

    private(set) var microphone: MicrophoneState
    /// アラームの許可を求めた結果。まだ求めていなければ nil。
    private(set) var alarmGranted: Bool?

    @ObservationIgnored private let alarms: any AlarmScheduling

    init(alarms: any AlarmScheduling) {
        self.alarms = alarms
        microphone = Self.currentMicrophoneState()
    }

    // MARK: - 読み取り

    /// 画面に戻ってきたときに読み直す（設定アプリで変えられている可能性がある）。
    func refresh() {
        microphone = Self.currentMicrophoneState()
    }

    // MARK: - 要求

    /// マイクのダイアログを出す。既に答えが出ているときは何もしない。
    func requestMicrophone() async {
        guard microphone == .undetermined else { return }
        _ = await AVAudioApplication.requestRecordPermission()
        microphone = Self.currentMicrophoneState()
    }

    /// アラームのダイアログを出す。既に答えが出ているときは、その答えが返るだけ。
    func requestAlarm() async {
        alarmGranted = await alarms.requestAuthorization()
    }

    /// 設定アプリのこのアプリのページを開く。
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - 内部

    private static func currentMicrophoneState() -> MicrophoneState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        case .undetermined: .undetermined
        @unknown default: .undetermined
        }
    }
}
