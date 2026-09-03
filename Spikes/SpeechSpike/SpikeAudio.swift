import Accelerate
import AVFoundation
import Foundation
import Observation
import Speech
import Synchronization
import UserNotifications

// MARK: - 値型（スレッドをまたぐのはここだけ）

/// 入力タップから @MainActor へ渡す唯一のデータ。
/// タップのクロージャは nonisolated なので、状態は持たせずこの値だけを流す。
enum TapEvent: Sendable {
    case level(rms: Float, duration: TimeInterval)
    case failure(String)
}

/// RMS ベースの無音判定。純粋な値型で、@MainActor 側だけが更新する。
struct SilenceDetector: Sendable {
    /// この値未満を無音とみなす（RMS。実機で調整する前提の初期値）
    var threshold: Float = 0.015
    /// この秒数だけ無音が続いたら発話終了
    var requiredSilence: TimeInterval

    private(set) var silentSeconds: TimeInterval = 0
    private(set) var hasHeardSpeech = false

    init(requiredSilence: TimeInterval) {
        self.requiredSilence = requiredSilence
    }

    /// 戻り値 true で「発話が終わった」
    mutating func feed(rms: Float, duration: TimeInterval) -> Bool {
        if rms >= threshold {
            hasHeardSpeech = true
            silentSeconds = 0
            return false
        }
        // 話し始める前の無音は数えない（読み上げ直後の間で切らないため）
        guard hasHeardSpeech else { return false }
        silentSeconds += duration
        return silentSeconds >= requiredSilence
    }

    var progress: Double {
        guard requiredSilence > 0 else { return 0 }
        return min(1, silentSeconds / requiredSilence)
    }

    mutating func reset() {
        silentSeconds = 0
        hasHeardSpeech = false
    }
}

// MARK: - タップの中で使う nonisolated ヘルパ

/// 1 バッファの RMS。オーディオスレッドで呼ばれるので状態を持たない。
nonisolated func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
    guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
    let frames = Int(buffer.frameLength)
    let samples = UnsafeBufferPointer(start: channelData[0], count: frames)
    return vDSP.rootMeanSquare(samples)
}

/// SpeechAnalyzer が要求する形式へ変換する。
/// `AnalyzerInputConverter` は iOS 26.2 SDK に存在しないため AVAudioConverter を直接使う。
/// AVAudioConverter は iOS 26.2 SDK で NS_SWIFT_SENDABLE なので、タップのクロージャに捕捉できる。
nonisolated func convertForAnalyzer(
    _ buffer: AVAudioPCMBuffer,
    using converter: AVAudioConverter,
    to format: AVAudioFormat
) throws -> AVAudioPCMBuffer? {
    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
    guard capacity > 0,
          let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
        return nil
    }

    // 入力ブロックは 1 回だけデータを返す（このバッファ 1 個ぶんの変換）。
    guard let source = InputBufferSource(copying: buffer) else { return nil }
    var conversionError: NSError?
    let status = converter.convert(to: output, error: &conversionError) { _, statusPointer in
        source.next(status: statusPointer)
    }

    if let conversionError { throw conversionError }
    switch status {
    case .haveData, .inputRanDry, .endOfStream:
        return output.frameLength > 0 ? output : nil
    case .error:
        return nil
    @unknown default:
        return nil
    }
}

/// `AVAudioConverterInputBlock` は NS_SWIFT_SENDABLE なので、
/// 非 Sendable な `AVAudioPCMBuffer` をそのままブロックへ捕捉できない
/// （`@unchecked Sendable` も `nonisolated(unsafe)` も使わないと決めている）。
/// そこで (1) タップのバッファを新しいバッファへ複製して region を切り離し、
/// (2) 標準ライブラリが Sendable を保証する `Mutex` に入れて 1 回だけ取り出す。
/// 複製は 1 バッファ（4096 フレーム）の memcpy なのでオーディオスレッドでも軽い。
private final class InputBufferSource: Sendable {
    private let slot: Mutex<AVAudioPCMBuffer?>

    init?(copying buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0, let source = buffer.floatChannelData else { return nil }

        // Sendable な [Float] を一度経由する。ポインタ経由で直接 memcpy すると
        // region 解析が複製先を入力バッファと同じ region と見なし、
        // 「sending 'copy' risks causing data races」で落ちるため。
        var samples: [[Float]] = []
        samples.reserveCapacity(channels)
        for channel in 0..<channels {
            samples.append(Array(UnsafeBufferPointer(start: source[channel], count: frames)))
        }

        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(frames)),
              let destination = copy.floatChannelData else {
            return nil
        }
        copy.frameLength = AVAudioFrameCount(frames)
        for channel in 0..<channels {
            samples[channel].withUnsafeBufferPointer { pointer in
                if let base = pointer.baseAddress {
                    destination[channel].update(from: base, count: frames)
                }
            }
        }
        slot = Mutex(copy)
    }

    /// 変換器へ渡すのは 1 回だけ。2 回目以降は .noDataNow を返して終わる。
    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        let buffer = slot.withLock { value -> AVAudioPCMBuffer? in
            defer { value = nil }
            return value
        }
        if let buffer {
            status.pointee = .haveData
            return buffer
        }
        status.pointee = .noDataNow
        return nil
    }
}

// MARK: - TTS のイベント（デリゲートは Sendable でなければならない）

enum SynthesisEvent: Sendable {
    case started
    case finished
    case cancelled
}

/// `AVSpeechSynthesizerDelegate` は iOS 26.2 SDK で NS_SWIFT_SENDABLE。
/// 格納プロパティを Sendable な continuation だけにすることで Sendable 適合が成立する。
final class SynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private let events: AsyncStream<SynthesisEvent>.Continuation

    init(events: AsyncStream<SynthesisEvent>.Continuation) {
        self.events = events
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        events.yield(.started)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        events.yield(.finished)
        events.finish()
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        events.yield(.cancelled)
        events.finish()
    }
}

// MARK: - 画面に出す状態

enum SpikeStage: String, Sendable {
    case idle = "待機"
    case checkingAssets = "モデル確認"
    case downloading = "モデル取得中"
    case speaking = "読み上げ中（半二重・録音停止）"
    case listening = "聞き取り中"
    case finalizing = "確定待ち"
    case playback = "録音を再生中"
    case finished = "完了"
    case failed = "失敗"
}

enum SpikeSessionMode: String, CaseIterable, Sendable {
    case standard = ".default"
    case voiceChat = ".voiceChat"

    var avMode: AVAudioSession.Mode {
        switch self {
        case .standard: .default
        case .voiceChat: .voiceChat
        }
    }
}

struct NotificationSample: Sendable, Identifiable {
    let id = UUID()
    let seconds: Double
    let tappedAt: Date
}

struct LocaleReport: Sendable {
    var transcriberAvailable = false
    var supported: [String] = []
    var installed: [String] = []
    var reserved: [String] = []
    var jaSupported = false
    var jaInstalled = false
    var matchedLocale: String?
    var assetStatus = "未確認"
}

// MARK: - 本体

@MainActor
@Observable
final class SpikeController {
    static let shared = SpikeController()

    // 表示状態
    private(set) var stage: SpikeStage = .idle
    private(set) var log: [String] = []
    private(set) var volatileText = ""
    private(set) var finalText = ""
    private(set) var level: Float = 0
    private(set) var levelHistory: [Float] = []
    private(set) var silenceProgress: Double = 0
    private(set) var localeReport = LocaleReport()
    private(set) var downloadProgress: Double?
    private(set) var notificationSamples: [NotificationSample] = []
    private(set) var recordingURL: URL?
    private(set) var audioFormatNote = ""
    private(set) var micPermission = "未確認"

    // 切替できる設定
    var silenceSeconds: TimeInterval = 1.5
    var sessionMode: SpikeSessionMode = .standard

    static let silenceChoices: [TimeInterval] = [1.2, 1.5, 2.0]
    static let prompt = "今日、何から逃げたい？"
    static let maxListeningSeconds: TimeInterval = 30

    // 音声まわり（すべて @MainActor に閉じる）
    private let synthesizer = AVSpeechSynthesizer()
    private var synthesizerDelegate: SynthesizerDelegate?
    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var tapContinuation: AsyncStream<TapEvent>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var tapTask: Task<Void, Never>?
    private var listenWatchdog: Task<Void, Never>?
    private var turnTask: Task<Void, Never>?
    private var player: AVAudioPlayer?
    private var detector = SilenceDetector(requiredSilence: 1.5)
    private var isStopping = false

    // 通知計測
    private var notificationTappedAt: Date?

    private init() {}

    // MARK: 起動と 1 ターン

    func onAppear() {
        guard stage == .idle else { return }
        append("SpeechTranscriber.isAvailable = \(SpeechTranscriber.isAvailable)")
        startTurn()
    }

    /// TTS →（発話完了後に）聞き取り、の 1 往復。
    func startTurn() {
        turnTask?.cancel()
        turnTask = Task { await runTurn() }
    }

    private func runTurn() async {
        finalText = ""
        volatileText = ""
        silenceProgress = 0
        levelHistory.removeAll()
        detector = SilenceDetector(requiredSilence: silenceSeconds)

        do {
            // 通知タップからの計測（S-C）を歪めないため、セッション設定の直後に発話する。
            // ロケール確認とモデル導入は発話が終わってから行う。
            try configureSession()
            stage = .speaking
            await speakPrompt()   // 半二重: 読み上げ中は入力タップを張らない

            await refreshMicPermission()
            stage = .checkingAssets
            let transcriber = SpeechTranscriber(
                locale: Locale(identifier: "ja-JP"),
                preset: .timeIndexedProgressiveTranscription
            )
            self.transcriber = transcriber
            await reportLocales(for: transcriber)
            try await ensureModelInstalled(for: transcriber)
            await reserveLocaleIfNeeded()

            stage = .listening
            try await startListening(with: transcriber)
        } catch {
            fail(error)
        }
    }

    // MARK: AVAudioSession

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        // iOS 26.2 SDK の正式名: .allowBluetoothHFP（旧 .allowBluetooth は deprecated）
        try session.setCategory(
            .playAndRecord,
            mode: sessionMode.avMode,
            options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
        )
        try session.setActive(true)
        append("AVAudioSession: .playAndRecord / \(sessionMode.rawValue) / [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]")
    }

    private func refreshMicPermission() async {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            micPermission = "許可済み"
        case .denied:
            micPermission = "拒否"
        case .undetermined:
            micPermission = "未決定（ダイアログ表示）"
            let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            micPermission = granted ? "許可済み" : "拒否"
        @unknown default:
            micPermission = "不明"
        }
        append("マイク権限: \(micPermission)（音声認識権限は要求していない）")
    }

    // MARK: モデル

    private func reportLocales(for transcriber: SpeechTranscriber) async {
        var report = LocaleReport()
        report.transcriberAvailable = SpeechTranscriber.isAvailable
        let supported = await SpeechTranscriber.supportedLocales
        let installed = await SpeechTranscriber.installedLocales
        let reserved = await AssetInventory.reservedLocales
        report.supported = supported.map { $0.identifier(.bcp47) }.sorted()
        report.installed = installed.map { $0.identifier(.bcp47) }.sorted()
        report.reserved = reserved.map { $0.identifier(.bcp47) }.sorted()
        report.jaSupported = report.supported.contains { $0.hasPrefix("ja") }
        report.jaInstalled = report.installed.contains { $0.hasPrefix("ja") }
        let matched = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "ja-JP"))
        report.matchedLocale = matched?.identifier(.bcp47)
        report.assetStatus = Self.label(for: await AssetInventory.status(forModules: [transcriber]))
        localeReport = report
        append("supportedLocales に ja: \(report.jaSupported) / installedLocales に ja: \(report.jaInstalled)")
    }

    private func ensureModelInstalled(for transcriber: SpeechTranscriber) async throws {
        guard localeReport.jaSupported else {
            throw SpikeError.localeUnsupported
        }
        guard !localeReport.jaInstalled else { return }

        stage = .downloading
        downloadProgress = 0
        append("AssetInventory.assetInstallationRequest(supporting:) を要求")
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            append("インストール要求は nil（追加ダウンロード不要）")
            downloadProgress = nil
            return
        }
        let progress = request.progress
        let watcher = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.downloadProgress = progress.fractionCompleted
                if progress.isFinished { return }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { watcher.cancel() }
        try await request.downloadAndInstall()
        downloadProgress = nil
        append("モデルのダウンロードと導入が完了")
        await reportLocales(for: transcriber)
    }

    /// ロケールの割り当て。割り当てが無いと analyzer が assetLocaleNotAllocated で失敗しうる。
    private func reserveLocaleIfNeeded() async {
        let reserved = await AssetInventory.reservedLocales
        if reserved.contains(where: { $0.identifier(.bcp47).hasPrefix("ja") }) {
            append("ja-JP は reserve 済み")
            return
        }
        do {
            let reservedNow = try await AssetInventory.reserve(locale: Locale(identifier: "ja-JP"))
            append("AssetInventory.reserve(locale: ja-JP) = \(reservedNow)（上限 \(AssetInventory.maximumReservedLocales)）")
        } catch {
            append("reserve に失敗: \(error.localizedDescription)")
        }
    }

    // MARK: TTS（半二重の前半）

    private func speakPrompt() async {
        let (events, continuation) = AsyncStream<SynthesisEvent>.makeStream()
        let delegate = SynthesizerDelegate(events: continuation)
        synthesizerDelegate = delegate
        synthesizer.delegate = delegate

        let utterance = AVSpeechUtterance(string: Self.prompt)
        if let voice = Self.preferredJapaneseVoice() {
            utterance.voice = voice
            append("TTS 音声: \(voice.name)（\(voice.language) / \(Self.qualityLabel(voice.quality))）")
        } else {
            append("TTS 音声: ja-JP の音声が見つからない")
        }
        synthesizer.speak(utterance)

        // didFinish が来ない環境で固まらないための保険
        let watchdog = Task {
            try? await Task.sleep(for: .seconds(20))
            continuation.finish()
        }
        defer { watchdog.cancel() }

        for await event in events {
            switch event {
            case .started:
                recordNotificationLatencyIfNeeded()
            case .finished, .cancelled:
                break
            }
        }
    }

    static func preferredJapaneseVoice() -> AVSpeechSynthesisVoice? {
        let japanese = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("ja") }
        // enhanced / premium があれば優先する
        return japanese.max { rank(of: $0.quality) < rank(of: $1.quality) }
            ?? AVSpeechSynthesisVoice(language: "ja-JP")
    }

    private static func rank(of quality: AVSpeechSynthesisVoiceQuality) -> Int {
        switch quality {
        case .premium: 3
        case .enhanced: 2
        case .default: 1
        @unknown default: 0
        }
    }

    static func qualityLabel(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: "premium"
        case .enhanced: "enhanced"
        case .default: "default"
        @unknown default: "unknown"
        }
    }

    // MARK: 聞き取り（1 入力 2 消費）

    private func startListening(with transcriber: SpeechTranscriber) async throws {
        isStopping = false

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SpikeError.noAnalyzerFormat
        }

        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        let (tapStream, tapContinuation) = AsyncStream<TapEvent>.makeStream()
        self.inputContinuation = inputContinuation
        self.tapContinuation = tapContinuation

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        try await analyzer.prepareToAnalyze(in: analyzerFormat)

        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: analyzerFormat) else {
            throw SpikeError.converterUnavailable
        }

        let url = Self.makeRecordingURL()
        recordingURL = url
        let file = try AVAudioFile(forWriting: url, settings: Self.aacSettings(matching: inputFormat))

        audioFormatNote = """
        入力: \(Int(inputFormat.sampleRate)) Hz / \(inputFormat.channelCount) ch / \(Self.commonFormatLabel(inputFormat.commonFormat))
        解析: \(Int(analyzerFormat.sampleRate)) Hz / \(analyzerFormat.channelCount) ch / \(Self.commonFormatLabel(analyzerFormat.commonFormat))
        録音: AAC 32 kbps / \(Int(inputFormat.sampleRate)) Hz / \(inputFormat.channelCount) ch
        """

        // ここが唯一の入力タップ。クロージャは nonisolated（@Sendable）で、
        // 捕捉するのは Sendable な値だけ。状態変更は一切しない。
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { @Sendable buffer, _ in
            let frames = Double(buffer.frameLength)
            let duration = frames > 0 ? frames / buffer.format.sampleRate : 0

            // (c) 波形用の RMS
            tapContinuation.yield(.level(rms: rmsLevel(of: buffer), duration: duration))

            // (a) 録音ファイルへ書く
            do {
                try file.write(from: buffer)
            } catch {
                tapContinuation.yield(.failure("録音書き込み: \(error.localizedDescription)"))
            }

            // (b) SpeechAnalyzer へ流す
            do {
                if let converted = try convertForAnalyzer(buffer, using: converter, to: analyzerFormat) {
                    inputContinuation.yield(AnalyzerInput(buffer: converted))
                }
            } catch {
                tapContinuation.yield(.failure("形式変換: \(error.localizedDescription)"))
            }
        }

        engine.prepare()
        try engine.start()
        try await analyzer.start(inputSequence: inputStream)
        append("タップ開始（1 入力 → 録音 / SpeechAnalyzer / 波形）")

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let text = String(result.text.characters)
                    if result.isFinal {
                        self.finalText += text
                        self.volatileText = ""
                    } else {
                        self.volatileText = text
                    }
                }
            } catch {
                self?.append("results 終了: \(error.localizedDescription)")
            }
        }

        listenWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.maxListeningSeconds))
            guard let self, !Task.isCancelled else { return }
            self.append("聞き取りの上限 \(Int(Self.maxListeningSeconds)) 秒に達したので停止する")
            await self.finishListening()
        }

        tapTask = Task { [weak self] in
            for await event in tapStream {
                guard let self else { return }
                switch event {
                case let .level(rms, duration):
                    self.level = rms
                    self.levelHistory.append(rms)
                    if self.levelHistory.count > 80 {
                        self.levelHistory.removeFirst(self.levelHistory.count - 80)
                    }
                    if self.detector.feed(rms: rms, duration: duration) {
                        self.silenceProgress = 1
                        await self.finishListening()
                        return
                    }
                    self.silenceProgress = self.detector.progress
                case let .failure(message):
                    self.append(message)
                }
            }
        }
    }

    func finishListening() async {
        guard !isStopping, stage == .listening else { return }
        isStopping = true
        stage = .finalizing
        level = 0

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        inputContinuation?.finish()
        tapContinuation?.finish()
        inputContinuation = nil
        tapContinuation = nil

        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            append("finalizeAndFinishThroughEndOfInput: \(error.localizedDescription)")
        }
        await resultsTask?.value
        resultsTask = nil
        tapTask?.cancel()
        tapTask = nil
        listenWatchdog?.cancel()
        listenWatchdog = nil
        analyzer = nil

        append("確定文字起こし: \(finalText.isEmpty ? "（空）" : finalText)")
        playRecording()
    }

    // MARK: 再生

    func playRecording() {
        guard let url = recordingURL else {
            stage = .finished
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            self.player = player
            player.play()
            stage = .playback
            let seconds = player.duration
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds + 0.2))
                self?.stage = .finished
            }
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
            append("録音: \(String(format: "%.1f", seconds)) 秒 / \(bytes.map { "\($0 / 1024) KB" } ?? "サイズ不明")")
        } catch {
            append("再生に失敗: \(error.localizedDescription)")
            stage = .finished
        }
    }

    // MARK: 通知（S-C）

    func scheduleMeasurementNotification() {
        Task {
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else {
                    append("通知が許可されていない")
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = "SpeechSpike"
                content.body = "タップして計測（通知タップ → TTS 開始）"
                content.sound = .default
                content.userInfo = ["kind": "measure"]
                let request = UNNotificationRequest(
                    identifier: "measure-\(UUID().uuidString)",
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
                )
                try await center.add(request)
                append("10 秒後の通知を登録した")
            } catch {
                append("通知の登録に失敗: \(error.localizedDescription)")
            }
        }
    }

    /// 通知タップの瞬間（nonisolated なデリゲートが取った時刻）を受け取って 1 ターンを開始する。
    func handleNotificationTap(at date: Date) {
        notificationTappedAt = date
        append("通知タップ: \(Self.timeFormatter.string(from: date))")
        stopEverything()
        startTurn()
    }

    private func recordNotificationLatencyIfNeeded() {
        guard let tappedAt = notificationTappedAt else { return }
        notificationTappedAt = nil
        let elapsed = Date().timeIntervalSince(tappedAt)
        notificationSamples.append(NotificationSample(seconds: elapsed, tappedAt: tappedAt))
        if notificationSamples.count > 5 {
            notificationSamples.removeFirst(notificationSamples.count - 5)
        }
        append(String(format: "通知タップ → TTS 開始: %.3f 秒", elapsed))
    }

    func clearSamples() {
        notificationSamples.removeAll()
    }

    // MARK: 後始末とログ

    func stopEverything() {
        turnTask?.cancel()
        resultsTask?.cancel()
        tapTask?.cancel()
        listenWatchdog?.cancel()
        turnTask = nil
        resultsTask = nil
        tapTask = nil
        listenWatchdog = nil
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()
        player = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        inputContinuation?.finish()
        tapContinuation?.finish()
        inputContinuation = nil
        tapContinuation = nil
        analyzer = nil
        isStopping = false
        level = 0
        levelHistory.removeAll()
        silenceProgress = 0
        stage = .idle
    }

    private func fail(_ error: any Error) {
        append("失敗: \(error.localizedDescription)")
        // タップやエンジンを張ったまま失敗した場合に後始末する
        stopEverything()
        stage = .failed
    }

    private func append(_ line: String) {
        log.append("[\(Self.timeFormatter.string(from: Date()))] \(line)")
        if log.count > 60 { log.removeFirst(log.count - 60) }
    }

    // MARK: 補助

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private static func makeRecordingURL() -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("spike-\(Int(Date().timeIntervalSince1970)).m4a")
    }

    /// AAC 32 kbps。チャンネル数と標本化周波数は入力に合わせる（AVAudioFile の processingFormat と一致させるため）。
    private static func aacSettings(matching format: AVAudioFormat) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVEncoderBitRateKey: 32_000,
        ]
    }

    private static func label(for status: AssetInventory.Status) -> String {
        switch status {
        case .unsupported: "unsupported"
        case .supported: "supported（未導入）"
        case .downloading: "downloading"
        case .installed: "installed"
        @unknown default: "unknown"
        }
    }

    private static func commonFormatLabel(_ format: AVAudioCommonFormat) -> String {
        switch format {
        case .pcmFormatFloat32: "Float32"
        case .pcmFormatFloat64: "Float64"
        case .pcmFormatInt16: "Int16"
        case .pcmFormatInt32: "Int32"
        case .otherFormat: "other"
        @unknown default: "unknown"
        }
    }
}

enum SpikeError: LocalizedError {
    case localeUnsupported
    case noAnalyzerFormat
    case converterUnavailable

    var errorDescription: String? {
        switch self {
        case .localeUnsupported: "SpeechTranscriber が ja-JP に対応していない"
        case .noAnalyzerFormat: "bestAvailableAudioFormat(compatibleWith:) が nil"
        case .converterUnavailable: "AVAudioConverter を作れない（入力形式と解析形式が非互換）"
        }
    }
}
