import AVFoundation
import Foundation
import UIKit

// MARK: - 値型

/// 再生直前に決める出力先。
/// 計画 §7.3: `.defaultToSpeaker` は付けず、`currentRoute.outputs` を見て毎回決める。
enum AudioOutputRoute: String, Sendable {
    /// イヤホン・Bluetooth・USB・カーオーディオが繋がっている。経路を触らずそのまま鳴らす。
    case accessory
    /// 何も繋がっていない。`overrideOutputAudioPort(.speaker)` でスピーカーへ回す。
    case speaker
    /// 「耳に当てて聞く」を選んだとき。`overrideOutputAudioPort(.none)` + 近接センサー。
    case receiver
}

/// 認識の混入対策としてモードを差し替えられるようにしておく（計画 §7.3 の S-B 比較項目）。
enum AudioSessionMode: String, CaseIterable, Sendable {
    case standard
    case voiceChat

    var avMode: AVAudioSession.Mode {
        switch self {
        case .standard: .default
        case .voiceChat: .voiceChat
        }
    }
}

/// 経路変更の中身。`AVAudioSession.RouteChangeReason` は Sendable なので値のまま運べる。
struct AudioRouteChange: Sendable {
    let reason: AVAudioSession.RouteChangeReason
    let isAccessoryConnected: Bool
}

/// セッション側で起きたことを @MainActor へ運ぶ唯一の型。
/// 通知は任意のスレッドで届くので、クロージャの中では continuation に yield するだけにする。
enum AudioSessionEvent: Sendable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case routeChanged(AudioRouteChange)
    case outputVolumeChanged(Float)
}

enum AudioSessionFault: Error, Sendable {
    case activationFailed
    case routeOverrideFailed
}

// MARK: - プロトコル（後続の ViewModel がモックを差し込むための境界）

@MainActor
protocol AudioSessionControlling: AnyObject {
    /// 割り込み・経路変更・音量変化。購読は 1 つを想定する。
    var events: AsyncStream<AudioSessionEvent> { get }
    var isActive: Bool { get }
    /// イヤホン等が接続されているか（再生前の確認 UI の条件）。
    var isAccessoryConnected: Bool { get }
    /// 端末の出力音量（0...1）。物理スイッチの状態を読む公開 API は無いので、これをゲートに使う。
    var outputVolume: Float { get }
    /// 「イヤホンで聞く / 文字で読む」を出すべきか。
    var requiresAudiblePlaybackConfirmation: Bool { get }

    func activate(mode: AudioSessionMode) throws
    func deactivate()
    /// 再生・発話の直前に呼び、決まった経路を返す。
    @discardableResult
    func applyOutputRoute(preferReceiver: Bool) -> AudioOutputRoute
}

// MARK: - 実装

/// `AVAudioSession` の設定と、割り込み・経路変更の受け口を 1 箇所にまとめる。
///
/// 消音スイッチについて（計画 §7.3 / fix-decisions P3.1）:
/// `.ambient` / `.soloAmbient` は Ring/Silent スイッチで **消音される側** のカテゴリであって、
/// 押し通す側ではない。本アプリが使う `.playAndRecord` はスイッチの影響を受けないため、
/// 「消音の尊重」は OS ではなくアプリ側の確認 UI で行う。
/// スイッチの状態を読む公開 API は AVFAudio に無い（`setOutputMuted` /
/// `outputMuteStateChangeNotification` はアプリ自身が設定したミュートであって物理スイッチではない）。
/// そこで `requiresAudiblePlaybackConfirmation`（イヤホン未接続 かつ `outputVolume` > 0.3）を
/// 確認 UI のゲート条件に使う。
@MainActor
final class AudioSessionController: AudioSessionControlling {
    /// 確認 UI を出す音量のしきい値（計画 §7.3）。
    static let confirmationVolumeThreshold: Float = 0.3

    /// アクセサリとみなす出力ポート。
    static let accessoryPorts: Set<AVAudioSession.Port> = [
        .headphones,
        .bluetoothA2DP,
        .bluetoothHFP,
        .bluetoothLE,
        .usbAudio,
        .carAudio,
        .airPlay,
    ]

    let events: AsyncStream<AudioSessionEvent>

    private(set) var isActive = false
    private(set) var mode: AudioSessionMode = .standard
    private(set) var lastAppliedRoute: AudioOutputRoute?

    private let continuation: AsyncStream<AudioSessionEvent>.Continuation
    private let session = AVAudioSession.sharedInstance()
    private var observerTokens: [any NSObjectProtocol] = []
    private var volumeObservation: NSKeyValueObservation?

    init() {
        let (stream, continuation) = AsyncStream<AudioSessionEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(32)
        )
        events = stream
        self.continuation = continuation
    }

    // MARK: 有効化

    func activate(mode: AudioSessionMode) throws {
        // `.defaultToSpeaker` は付けない。付けると有線・Bluetooth いずれのイヤホンも
        // 無視され、retention-strategy R8「イヤホンで聞く」が成立しなくなる（計画 §7.3）。
        // Bluetooth は iOS 26 SDK の名前を使う（旧 `.allowBluetooth` は deprecated）。
        try session.setCategory(
            .playAndRecord,
            mode: mode.avMode,
            options: [.allowBluetoothHFP, .allowBluetoothA2DP]
        )
        try session.setActive(true)
        self.mode = mode
        isActive = true
        startObservingIfNeeded()
    }

    func deactivate() {
        stopObserving()
        UIDevice.current.isProximityMonitoringEnabled = false
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
        isActive = false
        lastAppliedRoute = nil
    }

    // MARK: 経路

    var isAccessoryConnected: Bool {
        session.currentRoute.outputs.contains { Self.accessoryPorts.contains($0.portType) }
    }

    var outputVolume: Float {
        session.outputVolume
    }

    var requiresAudiblePlaybackConfirmation: Bool {
        !isAccessoryConnected && outputVolume > Self.confirmationVolumeThreshold
    }

    /// 発話・再生の直前に必ず呼ぶ。判定は毎回やり直す（経路は途中で変わる）。
    @discardableResult
    func applyOutputRoute(preferReceiver: Bool) -> AudioOutputRoute {
        let route: AudioOutputRoute
        if preferReceiver {
            // 受話口。近接センサーを併用して、耳に当てたら画面を消す。
            try? session.overrideOutputAudioPort(.none)
            UIDevice.current.isProximityMonitoringEnabled = true
            route = .receiver
        } else if isAccessoryConnected {
            // 直前にスピーカーへ回していた可能性があるので override を戻してから鳴らす。
            try? session.overrideOutputAudioPort(.none)
            UIDevice.current.isProximityMonitoringEnabled = false
            route = .accessory
        } else {
            try? session.overrideOutputAudioPort(.speaker)
            UIDevice.current.isProximityMonitoringEnabled = false
            route = .speaker
        }
        lastAppliedRoute = route
        return route
    }

    // MARK: 通知の受け口

    private func startObservingIfNeeded() {
        guard observerTokens.isEmpty else { return }
        let center = NotificationCenter.default
        let continuation = continuation
        let accessoryPorts = Self.accessoryPorts

        // 通知は任意のスレッドで届く。クロージャの中では Sendable な値を組み立てて
        // continuation に yield するだけにし、状態変更は購読側（@MainActor）で行う。
        observerTokens.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: session,
                queue: nil
            ) { notification in
                guard
                    let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                    let type = AVAudioSession.InterruptionType(rawValue: raw)
                else { return }
                switch type {
                case .began:
                    continuation.yield(.interruptionBegan)
                case .ended:
                    let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw ?? 0)
                    continuation.yield(.interruptionEnded(shouldResume: options.contains(.shouldResume)))
                @unknown default:
                    continuation.yield(.interruptionBegan)
                }
            }
        )

        observerTokens.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: session,
                queue: nil
            ) { notification in
                guard
                    let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                    let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
                else { return }
                // 通知が運ぶ経路ではなく、その時点の現在経路を読む（override の結果を含めるため）。
                let connected = AVAudioSession.sharedInstance().currentRoute.outputs
                    .contains { accessoryPorts.contains($0.portType) }
                continuation.yield(
                    .routeChanged(AudioRouteChange(reason: reason, isAccessoryConnected: connected))
                )
            }
        )

        volumeObservation = session.observe(\.outputVolume, options: [.new]) { _, change in
            guard let value = change.newValue else { return }
            continuation.yield(.outputVolumeChanged(value))
        }
    }

    private func stopObserving() {
        let center = NotificationCenter.default
        for token in observerTokens {
            center.removeObserver(token)
        }
        observerTokens.removeAll()
        volumeObservation?.invalidate()
        volumeObservation = nil
    }
}
