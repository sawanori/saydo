import AVFoundation
import Foundation
import Observation
import UIKit
import UserNotifications

/// マイクと通知の許可状態（実装計画 §8 の `OnboardingView`、task_013）。
///
/// 拒否されても止めない。マイクが無ければ文字だけで完走でき（fix-decisions P2.3）、
/// 通知が無くてもアプリを開けば会話は始まる。画面はこの型の状態を読んで
/// 「許可を求める」か「設定アプリへの導線を出す」かだけを決める。
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
    private(set) var notifications: UNAuthorizationStatus

    @ObservationIgnored private let scheduler: NotificationScheduler

    init(scheduler: NotificationScheduler = .shared) {
        self.scheduler = scheduler
        microphone = Self.currentMicrophoneState()
        notifications = .notDetermined
    }

    // MARK: - 読み取り

    /// 声で会話できるか。
    var isMicrophoneGranted: Bool { microphone == .granted }

    /// 通知を送れるか（`provisional` と `ephemeral` も含む）。
    var isNotificationGranted: Bool {
        switch notifications {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    /// ダイアログではなく設定アプリへ送る状態か。
    var needsSystemSettingsForMicrophone: Bool { microphone == .denied }

    var needsSystemSettingsForNotifications: Bool {
        switch notifications {
        case .notDetermined: false
        default: !isNotificationGranted
        }
    }

    /// 画面に戻ってきたときに読み直す（設定アプリで変えられている可能性がある）。
    func refresh() async {
        microphone = Self.currentMicrophoneState()
        notifications = await scheduler.authorizationStatus()
    }

    // MARK: - 要求

    /// マイクのダイアログを出す。既に答えが出ているときは何もしない。
    func requestMicrophone() async {
        guard microphone == .undetermined else { return }
        _ = await AVAudioApplication.requestRecordPermission()
        microphone = Self.currentMicrophoneState()
    }

    /// 通知のダイアログを出す。既に答えが出ているときは状態を読み直すだけ。
    func requestNotifications() async {
        guard notifications == .notDetermined else {
            notifications = await scheduler.authorizationStatus()
            return
        }
        _ = await scheduler.requestAuthorization()
        notifications = await scheduler.authorizationStatus()
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
