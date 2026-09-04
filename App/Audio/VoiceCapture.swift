import Accelerate
import AVFoundation
import OSLog
import Foundation
import Speech
import Synchronization

// MARK: - 値型（スレッドをまたぐのはここだけ）

/// 1 回の録音の上限（計画 §7.3 / task_007）。
/// 会話中の発話は 20 秒、朝の宣言（M4）だけ 30 秒。
enum VoiceCaptureLimit: Sendable {
    case utterance
    case declaration

    var seconds: TimeInterval {
        switch self {
        case .utterance: 20
        case .declaration: 30
        }
    }
}

enum VoiceCaptureFault: Error, Sendable, Equatable {
    case alreadyCapturing
    case inputUnavailable
    case converterUnavailable
    case fileWriteFailed(String)
    case conversionFailed(String)
}

/// 入力タップから @MainActor へ渡す唯一のデータ。
/// タップのクロージャは nonisolated なので、状態は持たせずこの値だけを流す。
enum VoiceCaptureEvent: Sendable {
    case level(rms: Float, duration: TimeInterval)
    /// 上限秒数に達したので録音を打ち切った。
    case reachedLimit
    case failed(VoiceCaptureFault)
}

/// 画面やログに出すための形式の要約。`AVAudioFormat` をそのまま持ち回さないための値型。
struct AudioFormatSummary: Sendable, Equatable {
    let sampleRate: Double
    let channelCount: UInt32

    init(_ format: AVAudioFormat) {
        sampleRate = format.sampleRate
        channelCount = format.channelCount
    }
}

/// `start` の戻り値。呼び出し側はこの 2 本のストリームだけを見る。
struct VoiceCaptureSession: Sendable {
    let recordingURL: URL
    /// RMS・上限到達・失敗。
    let events: AsyncStream<VoiceCaptureEvent>
    /// `TranscriptionService.start(inputSequence:)` にそのまま渡す。
    let analyzerInput: AsyncStream<AnalyzerInput>
    let inputFormat: AudioFormatSummary
    let analyzerFormat: AudioFormatSummary?
}

// MARK: - プロトコル

@MainActor
protocol VoiceCapturing: AnyObject {
    var isCapturing: Bool { get }
    var recordingURL: URL? { get }
    var limit: VoiceCaptureLimit { get set }

    /// 1 タップから (a) AAC ファイル (b) SpeechAnalyzer (c) RMS へ分配する。
    /// `analyzerFormat` が nil なら (b) を作らず録音と波形だけにする。
    func start(writingTo url: URL, analyzerFormat: AVAudioFormat?) throws -> VoiceCaptureSession
    func stop()
}

// MARK: - タップの中で使う nonisolated ヘルパ

/// 1 バッファの RMS。オーディオスレッドで呼ばれるので状態を持たない。
private nonisolated func rootMeanSquare(of buffer: AVAudioPCMBuffer) -> Float {
    guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }
    let samples = UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength))
    return vDSP.rootMeanSquare(samples)
}

/// SpeechAnalyzer が要求する形式へ変換する。
/// `AnalyzerInputConverter` は iOS 26.2 SDK に存在しないため `AVAudioConverter` を直接使う
/// （fix-decisions P4.1）。iOS 27 以降で使えるようになったらここだけ差し替える。
private nonisolated func convertForAnalyzer(
    _ buffer: AVAudioPCMBuffer,
    using converter: AVAudioConverter,
    to format: AVAudioFormat
) throws -> AVAudioPCMBuffer? {
    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
    guard capacity > 0,
          let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)
    else { return nil }

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
/// （Sendable の unchecked 適合も、unsafe な nonisolated 指定も使わないと決めている。
/// scripts/lint-principles.sh はこの 2 つを機械的に弾くので、綴りも書かない）。
/// そこで (1) タップのバッファを新しいバッファへ複製して region を切り離し、
/// (2) 標準ライブラリが Sendable を保証する `Mutex` に入れて 1 回だけ取り出す。
///
/// 複製を `[[Float]]`（Sendable）経由で行うのが要点。ポインタ経由で直接 memcpy すると
/// region 解析が複製先を入力バッファと同じ region と見なし、
/// `sending 'copy.some' risks causing data races` で落ちる
/// （docs/spikes/speech-spike.md §1「詰まった 1 点と回避」）。
/// コストは 1 バッファ（4096 フレーム × 4 バイト ≒ 16 KB）につき memcpy 2 回。
private final class InputBufferSource: Sendable {
    private let slot: Mutex<AVAudioPCMBuffer?>

    init?(copying buffer: AVAudioPCMBuffer) {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0, let source = buffer.floatChannelData else { return nil }

        var samples: [[Float]] = []
        samples.reserveCapacity(channels)
        for channel in 0..<channels {
            samples.append(Array(UnsafeBufferPointer(start: source[channel], count: frames)))
        }

        guard
            let copy = AVAudioPCMBuffer(
                pcmFormat: buffer.format,
                frameCapacity: AVAudioFrameCount(frames)
            ),
            let destination = copy.floatChannelData
        else { return nil }

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

    /// 変換器へ渡すのは 1 回だけ。2 回目以降は `.noDataNow` を返して終わる。
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

// MARK: - 実装

/// 入力タップを 1 つだけ張り、同じバッファを 3 つの用途へ分配する（計画 §7.3「1 入力 2 消費」+ 波形）。
///
/// 並行性（fix-decisions P4.6）:
/// `installTap` のクロージャは nonisolated である。クロージャ内では
/// (a) `AVAudioFile` への書き込みと (b)(c) continuation への yield しか行わない。
/// このクラスの格納プロパティには一切触れない。状態変更はすべて @MainActor 側で行う。
/// actor でまとめて包む回避策は採らない。
@MainActor
final class VoiceCapture: VoiceCapturing {
    private(set) var isCapturing = false
    private(set) var recordingURL: URL?
    var limit: VoiceCaptureLimit = .utterance
    private let logger = Logger(subsystem: "com.nonturn.saydo", category: "capture")

    /// タップに渡すバッファ長。スパイクで使った値をそのまま採用する。
    static let tapBufferSize: AVAudioFrameCount = 4096
    /// 録音の符号化率（計画 §7.3: AAC 32 kbps）。
    static let encoderBitRate = 32_000

    private var engine: AVAudioEngine?
    private var file: AVAudioFile?
    private var eventContinuation: AsyncStream<VoiceCaptureEvent>.Continuation?
    private var analyzerContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var limitTask: Task<Void, Never>?

    init() {}

    func start(writingTo url: URL, analyzerFormat: AVAudioFormat?) throws -> VoiceCaptureSession {
        guard !isCapturing else { throw VoiceCaptureFault.alreadyCapturing }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw VoiceCaptureFault.inputUnavailable
        }
        let analyzerDescription = analyzerFormat.map { "\($0.sampleRate)Hz/\($0.channelCount)ch" } ?? "nil"
        logger.info("capture start input=\(inputFormat.sampleRate, privacy: .public)Hz/\(inputFormat.channelCount, privacy: .public)ch analyzer=\(analyzerDescription, privacy: .public) limit=\(self.limit.seconds, privacy: .public)s")

        // タップのクロージャは @Sendable なので、捕捉する値は let にしておく。
        let converter: AVAudioConverter?
        if let analyzerFormat {
            guard let made = AVAudioConverter(from: inputFormat, to: analyzerFormat) else {
                throw VoiceCaptureFault.converterUnavailable
            }
            converter = made
        } else {
            converter = nil
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: Self.aacSettings(matching: inputFormat)
        )

        let (events, eventContinuation) = AsyncStream<VoiceCaptureEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        let (analyzerStream, analyzerContinuation) = AsyncStream<AnalyzerInput>.makeStream()

        // ここが唯一の入力タップ。捕捉するのは Sendable な値だけで、状態変更はしない。
        input.installTap(onBus: 0, bufferSize: Self.tapBufferSize, format: inputFormat) {
            @Sendable buffer, _ in
            let frames = Double(buffer.frameLength)
            let duration = frames > 0 ? frames / buffer.format.sampleRate : 0

            // (c) 波形と無音判定のための RMS
            eventContinuation.yield(.level(rms: rootMeanSquare(of: buffer), duration: duration))

            // (a) 録音ファイルへ書く
            do {
                try file.write(from: buffer)
            } catch {
                eventContinuation.yield(.failed(.fileWriteFailed(error.localizedDescription)))
            }

            // (b) SpeechAnalyzer へ流す
            if let converter, let analyzerFormat {
                do {
                    if let converted = try convertForAnalyzer(buffer, using: converter, to: analyzerFormat) {
                        analyzerContinuation.yield(AnalyzerInput(buffer: converted))
                    }
                } catch {
                    eventContinuation.yield(.failed(.conversionFailed(error.localizedDescription)))
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            eventContinuation.finish()
            analyzerContinuation.finish()
            throw error
        }

        self.engine = engine
        self.file = file
        self.eventContinuation = eventContinuation
        self.analyzerContinuation = analyzerContinuation
        recordingURL = url
        isCapturing = true

        if analyzerFormat == nil {
            analyzerContinuation.finish()
        }

        // 上限秒数。タイマーは @MainActor で回し、到達したら打ち切る。
        let seconds = limit.seconds
        limitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.isCapturing else { return }
            self.eventContinuation?.yield(.reachedLimit)
            self.stop()
        }

        return VoiceCaptureSession(
            recordingURL: url,
            events: events,
            analyzerInput: analyzerStream,
            inputFormat: AudioFormatSummary(inputFormat),
            analyzerFormat: analyzerFormat.map(AudioFormatSummary.init)
        )
    }

    func stop() {
        guard isCapturing else { return }
        isCapturing = false
        limitTask?.cancel()
        limitTask = nil

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        // AVAudioFile は解放時に書き出しを閉じる。
        file = nil

        analyzerContinuation?.finish()
        eventContinuation?.finish()
        analyzerContinuation = nil
        eventContinuation = nil
    }

    // MARK: 補助

    /// AAC 32 kbps。チャンネル数と標本化周波数は入力に合わせる
    /// （`AVAudioFile` の processingFormat とタップのバッファ形式を一致させるため）。
    /// 端末のマイク入力は 1 ch なので、実機では計画 §7.3 の「モノラル」と一致する。
    static func aacSettings(matching format: AVAudioFormat) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVEncoderBitRateKey: encoderBitRate,
        ]
    }
}
