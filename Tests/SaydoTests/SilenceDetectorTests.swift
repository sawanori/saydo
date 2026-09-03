import XCTest

@testable import Saydo

/// `SilenceDetector` は音声フレームワークに依存しない純ロジックなので、
/// 実機もシミュレータの音声入力も無しで検証できる（計画 §7.3 / task_007）。
final class SilenceDetectorTests: XCTestCase {
    /// 1 バッファぶんの長さ。4096 フレーム / 48 kHz ≒ 0.0853 秒 に近い刻みを使う。
    private let step: TimeInterval = 0.1

    // MARK: 設定

    func testSilenceDurationChoicesMatchPlan() {
        XCTAssertEqual(SilenceDuration.allCases.map(\.seconds), [1.2, 1.5, 2.0])
        XCTAssertEqual(SilenceDuration.standard.seconds, 1.5)
    }

    func testInitFromDurationUsesSeconds() {
        let detector = SilenceDetector(duration: .long)
        XCTAssertEqual(detector.requiredSilence, 2.0)
        XCTAssertEqual(detector.threshold, SilenceDetector.defaultThreshold)
    }

    // MARK: 発話前の無音

    func testSilenceBeforeAnySpeechNeverFinishes() {
        var detector = SilenceDetector(duration: .standard)
        for _ in 0..<100 {
            XCTAssertFalse(detector.feed(rms: 0, duration: step))
        }
        XCTAssertFalse(detector.hasHeardSpeech)
        XCTAssertEqual(detector.silentSeconds, 0)
        XCTAssertEqual(detector.progress, 0)
    }

    // MARK: 発話 → 無音

    func testFinishesAfterRequiredSilenceFollowingSpeech() {
        var detector = SilenceDetector(duration: .standard)
        XCTAssertFalse(detector.feed(rms: 0.2, duration: step))
        XCTAssertTrue(detector.hasHeardSpeech)

        // 1.5 秒 = 0.1 秒 × 15。14 回目までは終わらない。
        for index in 1...14 {
            XCTAssertFalse(detector.feed(rms: 0, duration: step), "step \(index)")
        }
        XCTAssertTrue(detector.feed(rms: 0, duration: step))
        XCTAssertTrue(detector.hasFinished)
    }

    func testFinishesExactlyAtBoundary() {
        var detector = SilenceDetector(requiredSilence: 1.0)
        _ = detector.feed(rms: 0.5, duration: 0.5)
        XCTAssertFalse(detector.feed(rms: 0, duration: 0.5))
        XCTAssertTrue(detector.feed(rms: 0, duration: 0.5))
    }

    func testSpeechResetsSilenceCounter() {
        var detector = SilenceDetector(requiredSilence: 1.0)
        _ = detector.feed(rms: 0.5, duration: 0.3)
        _ = detector.feed(rms: 0, duration: 0.5)
        XCTAssertEqual(detector.silentSeconds, 0.5, accuracy: 0.0001)

        // 途中で話し直したらカウンタは 0 に戻る。
        XCTAssertFalse(detector.feed(rms: 0.5, duration: 0.1))
        XCTAssertEqual(detector.silentSeconds, 0)
        XCTAssertFalse(detector.feed(rms: 0, duration: 0.5))
        XCTAssertTrue(detector.feed(rms: 0, duration: 0.5))
    }

    // MARK: しきい値

    func testValueAtThresholdCountsAsSpeech() {
        var detector = SilenceDetector(requiredSilence: 1.0, threshold: 0.02)
        XCTAssertFalse(detector.feed(rms: 0.02, duration: 0.1))
        XCTAssertTrue(detector.hasHeardSpeech)
    }

    func testValueJustBelowThresholdCountsAsSilence() {
        var detector = SilenceDetector(requiredSilence: 1.0, threshold: 0.02)
        _ = detector.feed(rms: 0.5, duration: 0.1)
        XCTAssertFalse(detector.feed(rms: 0.019, duration: 0.4))
        XCTAssertEqual(detector.silentSeconds, 0.4, accuracy: 0.0001)
    }

    // MARK: progress

    func testProgressIsClampedToOne() {
        var detector = SilenceDetector(requiredSilence: 1.0)
        _ = detector.feed(rms: 0.5, duration: 0.1)
        _ = detector.feed(rms: 0, duration: 0.5)
        XCTAssertEqual(detector.progress, 0.5, accuracy: 0.0001)
        _ = detector.feed(rms: 0, duration: 5.0)
        XCTAssertEqual(detector.progress, 1.0)
    }

    func testProgressIsZeroWhenRequiredSilenceIsZero() {
        let detector = SilenceDetector(requiredSilence: 0)
        XCTAssertEqual(detector.progress, 0)
    }

    // MARK: 無効な入力

    func testZeroDurationBufferIsIgnored() {
        var detector = SilenceDetector(requiredSilence: 1.0)
        XCTAssertFalse(detector.feed(rms: 0.5, duration: 0))
        XCTAssertFalse(detector.hasHeardSpeech)

        _ = detector.feed(rms: 0.5, duration: 0.1)
        XCTAssertFalse(detector.feed(rms: 0, duration: 0))
        XCTAssertEqual(detector.silentSeconds, 0)
    }

    // MARK: reset

    func testResetClearsStateButKeepsConfiguration() {
        var detector = SilenceDetector(requiredSilence: 1.0, threshold: 0.03)
        _ = detector.feed(rms: 0.5, duration: 0.1)
        _ = detector.feed(rms: 0, duration: 0.5)
        detector.reset()

        XCTAssertFalse(detector.hasHeardSpeech)
        XCTAssertEqual(detector.silentSeconds, 0)
        XCTAssertFalse(detector.hasFinished)
        XCTAssertEqual(detector.requiredSilence, 1.0)
        XCTAssertEqual(detector.threshold, 0.03)
    }

    // MARK: hasFinished

    func testHasFinishedMatchesFeedResult() {
        var detector = SilenceDetector(requiredSilence: 0.5)
        _ = detector.feed(rms: 0.5, duration: 0.1)
        XCTAssertFalse(detector.hasFinished)
        let finished = detector.feed(rms: 0, duration: 0.5)
        XCTAssertTrue(finished)
        XCTAssertTrue(detector.hasFinished)
    }
}
