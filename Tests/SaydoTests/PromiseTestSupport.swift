import AVFoundation
import Foundation
import SaydoCore
import Speech

@testable import Saydo

// 約束する画面（`PromiseViewModelTests`）が使うテスト用の部品。

// MARK: - インメモリの保存

/// `PromiseStore` のインメモリ実装。`Repository` と同じ規則
/// （1 日 1 件の約束、約束の声があれば宣言の `VoiceEntry` も作る）だけを写す。
actor InMemoryPromiseStore: PromiseStore {
    private(set) var commitments: [CommitmentSnapshot] = []
    private(set) var entries: [VoiceEntrySnapshot] = []

    private let calendar: Calendar
    /// これから何回、約束の保存（`createCommitment`）を失敗させるか。
    private var failingCreates = 0

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// 次の `count` 回の約束の保存を失敗させる。
    func failCreates(_ count: Int) {
        failingCreates = count
    }

    func createCommitment(_ draft: CommitmentDraft) throws -> CommitmentSnapshot {
        if failingCreates > 0 {
            failingCreates -= 1
            throw CocoaError(.fileWriteUnknown)
        }
        let key = DayKey.make(from: draft.createdAt, calendar: calendar)
        if commitments.contains(where: { $0.dayKey == key }) {
            throw RepositoryError.commitmentAlreadyExists(dayKey: key)
        }
        let snapshot = CommitmentSnapshot(
            id: draft.id,
            dayKey: key,
            microAction: draft.microAction,
            plannedAt: draft.plannedAt,
            plannedPlace: draft.plannedPlace,
            declarationAudioPath: draft.declarationAudioPath,
            declarationTranscript: draft.declarationTranscript,
            isVoiceless: draft.isVoiceless,
            outcome: .pending,
            reason: draft.reason,
            progressNote: nil,
            createdAt: draft.createdAt,
            avoidanceID: UUID(),
            avoidanceTitle: draft.avoidanceTitle,
            domain: draft.domain
        )
        commitments.append(snapshot)

        // `Repository.createCommitment` と同じく、宣言音声があれば宣言の `VoiceEntry` も作る。
        if let audioPath = draft.declarationAudioPath {
            entries.append(
                VoiceEntrySnapshot(
                    id: UUID(),
                    recordedAt: draft.createdAt,
                    sessionType: draft.sessionType,
                    kind: .declaration,
                    audioPath: audioPath,
                    transcript: draft.declarationTranscript,
                    durationSec: draft.declarationDurationSec,
                    commitmentID: snapshot.id
                )
            )
        }
        return snapshot
    }

    func appendVoiceEntry(_ draft: VoiceEntryDraft) throws -> VoiceEntrySnapshot {
        let snapshot = VoiceEntrySnapshot(
            id: draft.id,
            recordedAt: draft.recordedAt,
            sessionType: draft.sessionType,
            kind: draft.kind,
            audioPath: draft.audioPath,
            transcript: draft.transcript,
            durationSec: draft.durationSec,
            commitmentID: draft.commitmentID
        )
        entries.append(snapshot)
        return snapshot
    }
}

// MARK: - 門と文字起こし

/// テストが開けるまで待たせる門。録音の準備や確定の `await` を途中で止めるのに使う。
@MainActor
final class Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    var waitingCount: Int { waiters.count }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters = []
    }
}

/// あらかじめ決めた文字起こしを順に返す。
@MainActor
final class MockTranscriber: Transcribing {
    var script: [String]
    var volatileText = ""
    private(set) var finalText = ""
    var assetState: TranscriptionAssetState = .installed
    var isRunning = false

    init(script: [String]) {
        self.script = script
    }

    /// 置くと、録音の準備（`prepare()`）がこの門が開くまで戻らない。
    var prepareGate: Gate?
    /// 置くと、確定（`finish()`）がこの門が開くまで戻らない。
    var finishGate: Gate?

    func prepare() async throws -> AVAudioFormat {
        await prepareGate?.wait()
        return AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
    }

    /// 開始を呼ばれた回数（失敗した分も数える）。
    private(set) var startAttemptCount = 0
    /// 何回目の開始呼び出しを失敗させるか（1 始まり）。
    var failingStarts: Set<Int> = []
    /// 置くと、開始（`start`）がこの門が開くまで戻らない。
    var startGate: Gate?

    func start(inputSequence: AsyncStream<AnalyzerInput>) async throws {
        startAttemptCount += 1
        let attempt = startAttemptCount
        await startGate?.wait()
        if failingStarts.contains(attempt) { throw VoiceCaptureFault.converterUnavailable }
        isRunning = true
    }

    func finish() async -> String {
        isRunning = false
        await finishGate?.wait()
        finalText = script.isEmpty ? "" : script.removeFirst()
        return finalText
    }

    func cancel() {
        isRunning = false
        volatileText = ""
        finalText = ""
    }

    func reset() {
        volatileText = ""
        finalText = ""
    }
}
