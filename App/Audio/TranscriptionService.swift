import AVFoundation
import Foundation
import Observation
import Speech

// MARK: - 値型

enum TranscriptionFault: Error, Sendable, Equatable {
    /// `SpeechTranscriber` が ja-JP に対応していない。
    case localeUnsupported
    /// `bestAvailableAudioFormat(compatibleWith:)` が nil を返した。
    case noAnalyzerFormat
    /// `prepare()` を呼ぶ前に `start(inputSequence:)` を呼んだ。
    case notPrepared
    case alreadyRunning
}

/// ja-JP モデルの導入状況（オンボーディングの進捗表示に使う）。
enum TranscriptionAssetState: Sendable, Equatable {
    case unknown
    case unsupported
    case installed
    case downloading(Double)
}

// MARK: - プロトコル

@MainActor
protocol Transcribing: AnyObject {
    /// 途中結果（未確定）。
    var volatileText: String { get }
    /// 確定した文字起こし。
    var finalText: String { get }
    var assetState: TranscriptionAssetState { get }
    var isRunning: Bool { get }

    /// ja-JP アセットを確認し、必要ならダウンロードしてから解析形式を返す。
    /// 戻り値を `VoiceCapture.start(writingTo:analyzerFormat:)` に渡す。
    func prepare() async throws -> AVAudioFormat
    func start(inputSequence: AsyncStream<AnalyzerInput>) async throws
    /// 入力の終端まで確定させ、確定文字列を返す。
    func finish() async -> String
    func cancel()
    func reset()
}

// MARK: - 実装

/// `SpeechTranscriber` / `SpeechAnalyzer` のライフサイクルを 1 箇所に閉じる。
///
/// 権限について: `SFSpeechRecognizer` を使わないので音声認識の権限ダイアログは出ない。
/// 必要なのはマイク権限だけ（task_007 の done_definition）。
@MainActor
@Observable
final class TranscriptionService: Transcribing {
    static let locale = Locale(identifier: "ja-JP")

    private(set) var volatileText = ""
    private(set) var finalText = ""
    private(set) var assetState: TranscriptionAssetState = .unknown
    private(set) var isRunning = false

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?

    init() {}

    // MARK: 準備（アセット確認とダウンロード）

    func prepare() async throws -> AVAudioFormat {
        let transcriber = SpeechTranscriber(
            locale: Self.locale,
            preset: .timeIndexedProgressiveTranscription
        )
        self.transcriber = transcriber

        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47).hasPrefix("ja") }) else {
            assetState = .unsupported
            throw TranscriptionFault.localeUnsupported
        }

        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: { $0.identifier(.bcp47).hasPrefix("ja") }) {
            assetState = .installed
        } else {
            try await downloadAssets(for: transcriber)
        }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionFault.noAnalyzerFormat
        }
        return format
    }

    private func downloadAssets(for transcriber: SpeechTranscriber) async throws {
        assetState = .downloading(0)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            // nil は「追加のダウンロードは不要」を意味する。
            assetState = .installed
            return
        }
        let progress = request.progress
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.assetState = .downloading(progress.fractionCompleted)
                if progress.isFinished { return }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer {
            progressTask?.cancel()
            progressTask = nil
        }
        try await request.downloadAndInstall()
        assetState = .installed
    }

    // MARK: 解析

    func start(inputSequence: AsyncStream<AnalyzerInput>) async throws {
        guard let transcriber else { throw TranscriptionFault.notPrepared }
        guard !isRunning else { throw TranscriptionFault.alreadyRunning }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionFault.noAnalyzerFormat
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        try await analyzer.prepareToAnalyze(in: format)
        try await analyzer.start(inputSequence: inputSequence)
        isRunning = true

        // results の購読は @MainActor の Task。ここでだけ表示用の状態を書き換える。
        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        self.finalText += text
                        self.volatileText = ""
                    } else {
                        self.volatileText = text
                    }
                }
            } catch {
                // ストリームの終了はここに来る。確定済みのテキストはそのまま残す。
                self.volatileText = ""
            }
        }
    }

    func finish() async -> String {
        guard isRunning else { return finalText }
        isRunning = false
        // 入力側（VoiceCapture）の continuation が finish 済みであることが前提。
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        resultsTask = nil
        analyzer = nil
        volatileText = ""
        return finalText
    }

    func cancel() {
        isRunning = false
        resultsTask?.cancel()
        resultsTask = nil
        progressTask?.cancel()
        progressTask = nil
        analyzer = nil
        volatileText = ""
    }

    func reset() {
        volatileText = ""
        finalText = ""
    }
}
