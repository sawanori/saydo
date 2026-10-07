import AVFoundation
import Foundation
import os
import SaydoCore
import Speech
import XCTest

@testable import Saydo

// MARK: - テスト用の部品

/// `SessionViewModelTests` のインメモリの保存を、そのまま約束の保存にも使う
/// （1 日 1 件の約束、つないだ声があれば宣言の `VoiceEntry` も作る、という規則が同じ）。
extension InMemorySessionStore: PromiseStore {}

/// テストが進める時計。
private final class PromiseTestClock: Sendable {
    private let state: OSAllocatedUnfairLock<Date>

    init(_ date: Date) {
        state = OSAllocatedUnfairLock(initialState: date)
    }

    var now: Date { state.withLock { $0 } }

    func advance(_ seconds: TimeInterval) {
        state.withLock { $0 += seconds }
    }
}

/// 押している間だけ開いたままになる録音。始めると実物と同じくファイルを作る。
/// `AVAudioEngine` には触らない。
@MainActor
private final class HeldVoiceCapture: VoiceCapturing {
    private(set) var isCapturing = false
    private(set) var recordingURL: URL?
    var limit: VoiceCaptureLimit = .utterance

    private(set) var startCount = 0
    private(set) var stopCount = 0
    /// 始めたときの上限。
    private(set) var limitsAtStart: [VoiceCaptureLimit] = []
    var failsToStart = false
    private var eventContinuation: AsyncStream<VoiceCaptureEvent>.Continuation?

    func start(writingTo url: URL, analyzerFormat: AVAudioFormat?) throws -> VoiceCaptureSession {
        if failsToStart { throw VoiceCaptureFault.inputUnavailable }
        guard !isCapturing else { throw VoiceCaptureFault.alreadyCapturing }
        startCount += 1
        limitsAtStart.append(limit)
        isCapturing = true
        recordingURL = url
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: Data([0x01]))

        let (events, continuation) = AsyncStream<VoiceCaptureEvent>.makeStream()
        eventContinuation = continuation
        let (analyzerInput, analyzerContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        analyzerContinuation.finish()

        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        return VoiceCaptureSession(
            recordingURL: url,
            events: events,
            analyzerInput: analyzerInput,
            inputFormat: AudioFormatSummary(format),
            analyzerFormat: AudioFormatSummary(format)
        )
    }

    func emitLevel(rms: Float = 0.4, duration: TimeInterval) {
        eventContinuation?.yield(.level(rms: rms, duration: duration))
    }

    /// 実物と同じく、上限に達したら知らせてから自分で止まる。
    func reachLimit() {
        eventContinuation?.yield(.reachedLimit)
        stop()
    }

    func stop() {
        guard isCapturing else { return }
        stopCount += 1
        isCapturing = false
        eventContinuation?.finish()
        eventContinuation = nil
    }
}

// MARK: - テスト本体

@MainActor
final class PromiseViewModelTests: XCTestCase {

    private static let tokyo: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// 日本時間 2026-10-06 9:00。朝（10:00）・昼（14:00）・晩（19:00）の 3 回とも、これから始まる時刻。
    private static let morning = at(9)

    /// 日本時間 2026-10-06 の `hour` 時。
    private static func at(_ hour: Int, _ minute: Int = 0, day: Int = 6) -> Date {
        tokyo.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private var root: URL!
    private var audioFiles: AudioFileStore!
    private var store: InMemorySessionStore!
    private var capture: HeldVoiceCapture!
    private var alarms: RecordingRoundAlarms!
    private var settings: AppSettings!
    private var clock: PromiseTestClock!

    override func setUp() async throws {
        try await super.setUp()
        root = FileManager.default.temporaryDirectory
            .appending(path: "PromiseViewModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        audioFiles = AudioFileStore(rootDirectory: root)
        store = InMemorySessionStore(calendar: Self.tokyo)
        capture = HeldVoiceCapture()
        alarms = RecordingRoundAlarms(calendar: Self.tokyo)
        settings = AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: "PromiseViewModelTests-\(UUID().uuidString)")))
        clock = PromiseTestClock(Self.morning)
    }

    /// 同じ試験の中で、1 から作り直す（時計を `date` に合わせる）。録音の置き場所は同じものを使う。
    private func setUpFreshStores(at date: Date) {
        store = InMemorySessionStore(calendar: Self.tokyo)
        capture = HeldVoiceCapture()
        alarms = RecordingRoundAlarms(calendar: Self.tokyo)
        settings = AppSettings(defaults: UserDefaults(suiteName: "PromiseViewModelTests-\(UUID().uuidString)")!)
        clock = PromiseTestClock(date)
    }

    override func tearDown() async throws {
        if let root, FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: root)
        }
        root = nil
        try await super.tearDown()
    }

    private func makeViewModel(
        transcript script: [String] = [],
        microphoneGranted: Bool = true,
        store customStore: (any PromiseStore)? = nil
    ) -> (PromiseViewModel, MockTranscriber) {
        let transcriber = MockTranscriber(script: script)
        let clock = clock!
        // 約束は `promiseSaved` で渡されるので、引き直す先は要らない（翌日の約束は無い）。
        let chase = ChaseCoordinator(
            alarms: alarms,
            settings: settings,
            calendar: Self.tokyo,
            now: { clock.now },
            commitmentOn: { _ in nil }
        )
        let viewModel = PromiseViewModel(
            store: customStore ?? store,
            capture: capture,
            transcriber: transcriber,
            chase: chase,
            audioFiles: audioFiles,
            calendar: Self.tokyo,
            now: { clock.now }
        )
        viewModel.open(microphoneGranted: microphoneGranted)
        return (viewModel, transcriber)
    }

    /// 押して、`seconds` 秒たってから離し、確定まで待つ。
    private func hold(_ viewModel: PromiseViewModel, for seconds: TimeInterval) async {
        viewModel.pressBegan()
        await viewModel.waitForPendingWork()
        clock.advance(seconds)
        viewModel.pressEnded()
        await viewModel.waitForPendingWork()
    }

    private func eventually(
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<400 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("条件が成り立たなかった", file: file, line: line)
    }

    private func storedFiles() throws -> [String] {
        try audioFiles.allRelativePaths()
    }

    // MARK: 押している間だけ録音する

    func testRecordingRunsOnlyWhilePressed() async throws {
        let (viewModel, _) = makeViewModel(transcript: ["企画書を出す"])
        XCTAssertFalse(capture.isCapturing, "押すまで録音しない")

        viewModel.pressBegan()
        await viewModel.waitForPendingWork()
        XCTAssertTrue(capture.isCapturing)
        XCTAssertTrue(viewModel.isRecording)
        XCTAssertEqual(capture.limitsAtStart.map(\.seconds), [30], "上限は 30 秒")

        clock.advance(2)
        viewModel.pressEnded()
        // 離した瞬間に止まっている（確定を待たない）。
        XCTAssertFalse(capture.isCapturing)
        XCTAssertFalse(viewModel.isRecording)

        await viewModel.waitForPendingWork()
        XCTAssertFalse(capture.isCapturing, "離した後に録音が続かない")
        XCTAssertEqual(capture.startCount, 1)
        XCTAssertEqual(capture.stopCount, 1)
        XCTAssertEqual(viewModel.answers[.promise]?.text, "企画書を出す")
        XCTAssertEqual(viewModel.answers[.promise]?.durationSec, 2)
        XCTAssertEqual(viewModel.stage, .action)
        XCTAssertEqual(try storedFiles().count, 1)
    }

    func testLevelsWhilePressedDriveTheElapsedSeconds() async throws {
        let (viewModel, _) = makeViewModel(transcript: ["企画書を出す"])
        viewModel.pressBegan()
        await viewModel.waitForPendingWork()
        capture.emitLevel(duration: 1.5)
        capture.emitLevel(duration: 1.5)
        await eventually { viewModel.elapsedSeconds == 3 }
        XCTAssertEqual(viewModel.waveform.levels.count, 2)
    }

    func testPressShorterThanHalfASecondDoesNotAdvance() async throws {
        let (viewModel, transcriber) = makeViewModel(transcript: ["企画書を出す"])
        await hold(viewModel, for: 0.3)

        XCTAssertEqual(viewModel.stage, .promise)
        XCTAssertTrue(viewModel.answers.isEmpty)
        XCTAssertEqual(viewModel.notice, .holdLonger)
        XCTAssertFalse(capture.isCapturing)
        XCTAssertEqual(try storedFiles(), [], "短い録音のファイルは残さない")
        XCTAssertEqual(transcriber.script, ["企画書を出す"], "短い押下は文字起こしを確定しない")

        // もう一度押せば、同じ質問に答えられる。
        await hold(viewModel, for: 0.5)
        XCTAssertEqual(viewModel.answers[.promise]?.text, "企画書を出す")
        XCTAssertEqual(viewModel.stage, .action)
        XCTAssertNil(viewModel.notice)
    }

    func testEmptyTranscriptDoesNotAdvance() async throws {
        let (viewModel, _) = makeViewModel(transcript: ["  ", "企画書を出す"])
        await hold(viewModel, for: 2)

        XCTAssertEqual(viewModel.stage, .promise)
        XCTAssertTrue(viewModel.answers.isEmpty)
        XCTAssertEqual(viewModel.notice, .notHeard)
        XCTAssertEqual(try storedFiles(), [], "聞き取れなかった録音のファイルは残さない")

        await hold(viewModel, for: 2)
        XCTAssertEqual(viewModel.answers[.promise]?.text, "企画書を出す")
        XCTAssertEqual(viewModel.stage, .action)
    }

    func testReleasingBeforeTheRecordingStartsDoesNotAdvance() async throws {
        let (viewModel, transcriber) = makeViewModel(transcript: ["企画書を出す"])
        let gate = Gate()
        transcriber.prepareGate = gate

        viewModel.pressBegan()
        await eventually { gate.waitingCount == 1 }
        viewModel.pressEnded()
        gate.open()
        await viewModel.waitForPendingWork()

        XCTAssertEqual(capture.startCount, 0, "離した後に録音を始めない")
        XCTAssertEqual(viewModel.stage, .promise)
        XCTAssertEqual(viewModel.notice, .holdLonger)
        XCTAssertFalse(viewModel.isFinalizing)
    }

    func testThirtySecondLimitEndsTheTake() async throws {
        let (viewModel, _) = makeViewModel(transcript: ["企画書を出す"])
        viewModel.pressBegan()
        await viewModel.waitForPendingWork()
        clock.advance(30)
        capture.reachLimit()

        await eventually { viewModel.stage == .action }
        XCTAssertFalse(viewModel.isHolding)
        XCTAssertEqual(viewModel.answers[.promise]?.text, "企画書を出す")

        // 指を離すのが後になっても、次の質問には何も起きない。
        viewModel.pressEnded()
        await viewModel.waitForPendingWork()
        XCTAssertEqual(viewModel.stage, .action)
        XCTAssertNil(viewModel.answers[.action])
        XCTAssertEqual(capture.startCount, 1)
    }

    func testCaptureThatCannotStartFallsBackToText() async throws {
        let (viewModel, _) = makeViewModel(transcript: ["企画書を出す"])
        capture.failsToStart = true
        viewModel.pressBegan()
        await viewModel.waitForPendingWork()

        XCTAssertEqual(viewModel.notice, .captureUnavailable)
        XCTAssertTrue(viewModel.showsTextField)
        XCTAssertFalse(viewModel.isHolding)
        XCTAssertEqual(try storedFiles(), [])

        viewModel.pressEnded()
        await viewModel.waitForPendingWork()
        XCTAssertEqual(viewModel.stage, .promise)
        XCTAssertEqual(viewModel.notice, .captureUnavailable)
    }

    // MARK: 古い録音の結果を別の質問に入れない

    func testStaleTakeDoesNotLandInAnotherQuestion() async throws {
        let (viewModel, transcriber) = makeViewModel(transcript: ["古い録音の言葉"])
        let gate = Gate()
        transcriber.finishGate = gate

        viewModel.pressBegan()
        await viewModel.waitForPendingWork()
        clock.advance(2)
        viewModel.pressEnded()
        await eventually { gate.waitingCount == 1 }

        // 確定を待っている間に、同じ質問を文字で答えて次の質問へ進む。
        viewModel.useTextInput()
        viewModel.submitText("文字の約束")
        XCTAssertEqual(viewModel.stage, .action)

        gate.open()
        await viewModel.waitForPendingWork()

        XCTAssertEqual(viewModel.answers[.promise]?.text, "文字の約束")
        XCTAssertNil(viewModel.answers[.action], "古い録音の結果が次の質問に入らない")
        XCTAssertEqual(viewModel.stage, .action)
        XCTAssertEqual(try storedFiles(), [], "捨てた録音のファイルは残さない")
        XCTAssertFalse(viewModel.isFinalizing)
    }

    // MARK: 保存とアラーム

    func testTwoAnswersAndCommitSaveOnePromiseAndScheduleOnce() async throws {
        let (viewModel, _) = makeViewModel(transcript: ["企画書を出す", "資料を開く"])
        await hold(viewModel, for: 2)
        await hold(viewModel, for: 3)

        // 2 つ話したら、聞き取った 2 行と「約束する」。時刻は選ばない。
        XCTAssertEqual(viewModel.stage, .confirm)
        XCTAssertTrue(viewModel.canCommit)
        let promisePath = try XCTUnwrap(viewModel.answers[.promise]?.audioPath)
        XCTAssertEqual(viewModel.answers[.action]?.text, "資料を開く")
        XCTAssertNil(viewModel.answers[.action]?.audioPath, "最初にやることは文字だけ。録音は残さない")
        XCTAssertEqual(try storedFiles(), [promisePath], "答えた時点で、アクションの録音ファイルは消えている")

        clock.advance(10)
        await viewModel.commit()

        // 9 時台の約束。最初に追うのは朝の回（10:00）。
        let start = Self.at(10)
        let commitments = await store.commitments
        XCTAssertEqual(commitments.count, 1)
        let saved = try XCTUnwrap(commitments.first)
        XCTAssertEqual(saved.avoidanceTitle, "企画書を出す")
        XCTAssertEqual(saved.microAction.text, "資料を開く")
        XCTAssertEqual(saved.plannedAt, start)
        XCTAssertEqual(saved.declarationTranscript, "企画書を出す")
        XCTAssertFalse(saved.isVoiceless)

        // あとで返す声は、約束の録音だけ。アクションの録音はつながない（保存後に残るのも約束の録音だけ）。
        XCTAssertEqual(saved.declarationAudioPath, promisePath)
        XCTAssertEqual(try storedFiles(), [promisePath])
        XCTAssertTrue(audioFiles.fileExists(atRelativePath: promisePath))

        // 記録の行は 1 つだけ。約束の録音を指す。
        let entries = await store.entries
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.commitmentID, saved.id)
        XCTAssertEqual(entries.first?.audioPath, promisePath)
        XCTAssertEqual(entries.first?.transcript, "企画書を出す")

        // 朝・昼・晩の 3 回が、約束の声で登録される。題は「最初にやること」の文字。
        let rounds = await alarms.rounds(on: clock.now)
        XCTAssertEqual(rounds, [.morning, .noon, .evening])
        let morning = await alarms.request(.morning, on: clock.now)
        XCTAssertEqual(
            morning,
            AlarmRoundRequest(
                round: .morning, start: start, voiceRelativePath: promisePath, purpose: .chase, title: "資料を開く"
            )
        )
        let noon = await alarms.request(.noon, on: clock.now)
        XCTAssertEqual(noon?.start, Self.at(14))
        XCTAssertEqual(noon?.voiceRelativePath, promisePath)
        XCTAssertEqual(noon?.title, "資料を開く")
        let evening = await alarms.request(.evening, on: clock.now)
        XCTAssertEqual(evening?.start, Self.at(19))
        XCTAssertEqual(evening?.voiceRelativePath, promisePath)
        XCTAssertEqual(evening?.title, "資料を開く")
        let authorizationRequests = await alarms.authorizationRequests
        XCTAssertEqual(authorizationRequests, 1)

        // 翌日の朝の回（約束を促す、既定の音、固定の題）も、このとき登録される。
        let tomorrow = Self.at(12, day: 7)
        let tomorrowRounds = await alarms.rounds(on: tomorrow)
        XCTAssertEqual(tomorrowRounds, [.morning])
        let prompt = await alarms.request(.morning, on: tomorrow)
        XCTAssertEqual(
            prompt,
            AlarmRoundRequest(round: .morning, start: Self.at(10, day: 7), voiceRelativePath: nil, purpose: .prompt)
        )

        XCTAssertEqual(viewModel.stage, .done)
        XCTAssertEqual(
            viewModel.completionLine,
            PromiseCopy.completion(roundsAt: [start, Self.at(14), Self.at(19)], calendar: Self.tokyo)
        )
        XCTAssertEqual(viewModel.completionLine, "10時と14時と19時に、あなたの声で追いかけます。")
        XCTAssertEqual(viewModel.commitment?.id, saved.id)

        // 完了の後にもう一度押しても、2 件目は作らない。
        let callsBefore = await alarms.scheduleCalls
        await viewModel.commit()
        let after = await store.commitments
        XCTAssertEqual(after.count, 1)
        let callsAfter = await alarms.scheduleCalls
        XCTAssertEqual(callsAfter, callsBefore)
    }

    /// 既定の時刻は 10:00・14:00・19:00。約束した時刻から、追う回の数が決まる（9 時 3 回、12 時 2 回、15 時 1 回、20 時 0 回）。
    func testNumberOfRoundsFollowsTheHourOfThePromise() async throws {
        let cases: [(hour: Int, rounds: [AlarmRound], starts: [Date])] = [
            (9, [.morning, .noon, .evening], [Self.at(10), Self.at(14), Self.at(19)]),
            (12, [.noon, .evening], [Self.at(14), Self.at(19)]),
            (15, [.evening], [Self.at(19)]),
            (20, [], []),
        ]
        for (hour, expectedRounds, expectedStarts) in cases {
            setUpFreshStores(at: Self.at(hour))
            let (viewModel, _) = makeViewModel(microphoneGranted: false)
            viewModel.submitText("企画書を出す")
            viewModel.submitText("資料を開く")
            await viewModel.commit()

            let rounds = await alarms.rounds(on: clock.now)
            XCTAssertEqual(rounds, expectedRounds, "\(hour) 時の約束")
            let commitments = await store.commitments
            XCTAssertEqual(commitments.first?.plannedAt, expectedStarts.first, "\(hour) 時: plannedAt は最初に追う回の時刻")
            for (round, start) in zip(expectedRounds, expectedStarts) {
                let request = await alarms.request(round, on: clock.now)
                XCTAssertEqual(request?.start, start, "\(hour) 時の \(round)")
            }
        }
    }

    /// 12 時に約束すると、昼と晩の回が登録され、朝の回は登録されない（§17.9 の 4）。
    func testPromiseAtNoonIsChasedAtTwoAndSeven() async throws {
        clock = PromiseTestClock(Self.at(12))
        let (viewModel, _) = makeViewModel(microphoneGranted: false)
        viewModel.submitText("企画書を出す")
        viewModel.submitText("資料を開く")
        await viewModel.commit()

        let rounds = await alarms.rounds(on: clock.now)
        XCTAssertEqual(rounds, [.noon, .evening])
        let commitments = await store.commitments
        XCTAssertEqual(commitments.first?.plannedAt, Self.at(14), "plannedAt は最初に追う回の時刻")
        XCTAssertEqual(viewModel.completionLine, "14時と19時に、アラームで追いかけます。")
    }

    /// 20 時に約束すると、3 回とも過ぎているので、その日は回を登録しない（§17.10 の 2）。
    /// 完了の 1 行は、追いかけるとは言わず、約束を残したことだけを伝える。
    func testPromiseAfterAllRoundsIsNotChasedThatDay() async throws {
        clock = PromiseTestClock(Self.at(20))
        let (viewModel, _) = makeViewModel(microphoneGranted: false)
        viewModel.submitText("企画書を出す")
        viewModel.submitText("資料を開く")
        await viewModel.commit()

        let commitments = await store.commitments
        XCTAssertEqual(commitments.count, 1, "約束は残る")
        XCTAssertNil(commitments.first?.plannedAt)
        let rounds = await alarms.rounds(on: clock.now)
        XCTAssertEqual(rounds, [])
        // 翌日の朝の回（約束を促す）は、これまでどおり登録される。
        let tomorrowRounds = await alarms.rounds(on: Self.at(12, day: 7))
        XCTAssertEqual(tomorrowRounds, [.morning])

        XCTAssertEqual(viewModel.stage, .done)
        let line = try XCTUnwrap(viewModel.completionLine)
        XCTAssertFalse(line.contains("追いかけます"))
        XCTAssertEqual(line, PromiseCopy.completionRecordedOnly)
    }

    /// 7 時に約束すると、3 回とも登録され、朝の回も約束の声で結果を聞く（§17.9 の 5）。
    func testPromiseBeforeTheMorningRoundIsChasedThreeTimesWithTheVoice() async throws {
        clock = PromiseTestClock(Self.at(7))
        let (viewModel, _) = makeViewModel(transcript: ["企画書を出す", "資料を開く"])
        await hold(viewModel, for: 2)
        await hold(viewModel, for: 2)
        await viewModel.commit()

        let commitments = await store.commitments
        let promisePath = try XCTUnwrap(commitments.first?.declarationAudioPath)
        let rounds = await alarms.rounds(on: clock.now)
        XCTAssertEqual(rounds, [.morning, .noon, .evening])
        for round in [AlarmRound.morning, .noon, .evening] {
            let request = await alarms.request(round, on: clock.now)
            XCTAssertEqual(request?.voiceRelativePath, promisePath, "\(round)")
            XCTAssertEqual(request?.purpose, .chase, "\(round)")
        }
        let morning = await alarms.request(.morning, on: clock.now)
        XCTAssertEqual(morning?.start, Self.at(10))
        XCTAssertEqual(commitments.first?.plannedAt, Self.at(10))
        XCTAssertEqual(viewModel.completionLine, "10時と14時と19時に、あなたの声で追いかけます。")
    }

    /// アラームの題は、その日の「最初にやること」の文字。長いときは 40 文字ほどで切る。
    func testAlarmTitleCarriesTheFirstActionAndLongOnesAreCut() async throws {
        let long = String(repeating: "資料を開いて見直す", count: 6)
        let (viewModel, _) = makeViewModel(microphoneGranted: false)
        viewModel.submitText("企画書を出す")
        viewModel.submitText(long)
        await viewModel.commit()

        let request = await alarms.request(.noon, on: clock.now)
        let title = try XCTUnwrap(request?.title)
        XCTAssertEqual(title, PromiseCopy.alarmTitle(firstAction: long))
        XCTAssertLessThan(title.count, long.count)
        XCTAssertLessThanOrEqual(title.count, 41, "切るのは 40 文字ほど")
        XCTAssertTrue(title.hasPrefix(String(long.prefix(30))), "「最初にやること」の頭の文字を含む")
        XCTAssertNotEqual(title, PromiseCopy.alarmTitle)

        // 短いときは、そのまま。
        setUpFreshStores(at: Self.morning)
        let (shortModel, _) = makeViewModel(microphoneGranted: false)
        shortModel.submitText("企画書を出す")
        shortModel.submitText("資料を開く")
        await shortModel.commit()
        let shortRequest = await alarms.request(.noon, on: clock.now)
        XCTAssertEqual(shortRequest?.title, "資料を開く")
    }

    // MARK: 約束の無い朝の「今日はやめる」

    func testStopTodayStopsTheMorningRoundWithoutSavingAPromise() async throws {
        // 朝の回（10:00〜）が鳴っている 10:30。
        clock = PromiseTestClock(Self.at(10, 30))
        let (viewModel, _) = makeViewModel(microphoneGranted: false)
        XCTAssertTrue(viewModel.showsStopToday)

        await viewModel.stopToday()

        XCTAssertTrue(viewModel.didStopToday)
        XCTAssertFalse(viewModel.showsStopToday)
        XCTAssertEqual(settings.morningPromptStoppedDayKey, DayKey.make(from: clock.now, calendar: Self.tokyo))
        let commitments = await store.commitments
        XCTAssertEqual(commitments, [])
        // その日の登録は空で置き換えられる（朝の回が止まる）。翌日の朝の回は残る。
        let events = await alarms.events
        XCTAssertTrue(events.contains(.schedule(dayKey: DayKey.make(from: clock.now, calendar: Self.tokyo), rounds: [])))
        let today = await alarms.rounds(on: clock.now)
        XCTAssertEqual(today, [])
        let tomorrow = await alarms.rounds(on: Self.at(12, day: 7))
        XCTAssertEqual(tomorrow, [.morning])
    }

    func testStopTodayIsNotOfferedOnceTheMorningRoundIsOver() async throws {
        // 朝の回（10:00〜）は 2 時間で鳴り終える。12:00 を過ぎたら出さない。
        clock = PromiseTestClock(Self.at(13))
        let (viewModel, _) = makeViewModel(microphoneGranted: false)
        XCTAssertFalse(viewModel.showsStopToday)

        await viewModel.stopToday()
        XCTAssertFalse(viewModel.didStopToday)
        let calls = await alarms.scheduleCalls
        XCTAssertEqual(calls, 0)
    }

    func testTextOnlyPromiseIsSavedAndScheduledWithoutAVoice() async throws {
        let (viewModel, _) = makeViewModel(microphoneGranted: false)
        XCTAssertTrue(viewModel.showsTextField, "マイクが使えない端末では最初から文字の入力")
        XCTAssertFalse(viewModel.showsTalkButton)
        XCTAssertFalse(viewModel.canUseVoice)

        viewModel.pressBegan()
        await viewModel.waitForPendingWork()
        XCTAssertEqual(capture.startCount, 0)

        viewModel.submitText("   ")
        XCTAssertEqual(viewModel.stage, .promise, "空の答えは受けない")
        viewModel.submitText("企画書を出す")
        viewModel.submitText("資料を開く")
        XCTAssertEqual(viewModel.stage, .confirm)
        await viewModel.commit()

        let start = Self.at(10)
        let commitments = await store.commitments
        XCTAssertEqual(commitments.count, 1)
        let saved = try XCTUnwrap(commitments.first)
        XCTAssertEqual(saved.avoidanceTitle, "企画書を出す")
        XCTAssertEqual(saved.microAction.text, "資料を開く")
        XCTAssertNil(saved.declarationAudioPath)
        XCTAssertTrue(saved.isVoiceless)

        let noon = await alarms.request(.noon, on: clock.now)
        XCTAssertEqual(
            noon,
            AlarmRoundRequest(round: .noon, start: Self.at(14), voiceRelativePath: nil, purpose: .chase, title: "資料を開く")
        )
        XCTAssertEqual(capture.startCount, 0)
        XCTAssertEqual(try storedFiles(), [])
        // 記録の行は 1 つだけ（文字だけ）。
        let entries = await store.entries
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries.first?.audioPath)
        XCTAssertEqual(entries.first?.transcript, "企画書を出す")

        let line = try XCTUnwrap(viewModel.completionLine)
        XCTAssertEqual(
            line,
            PromiseCopy.completionWithoutVoice(roundsAt: [start, Self.at(14), Self.at(19)], calendar: Self.tokyo)
        )
        XCTAssertFalse(line.contains("あなたの声"), "声の無い約束で「あなたの声で」と言わない")
    }

    /// 約束は声、最初にやることも声で話した日。アクションの録音は文字にしたら消え、声は約束の録音だけ。
    func testOnlyThePromiseRecordingIsKeptWhenBothAreSpoken() async throws {
        let (viewModel, _) = makeViewModel(transcript: ["企画書を出す", "資料を開く"])
        await hold(viewModel, for: 2)
        let promisePath = try XCTUnwrap(viewModel.answers[.promise]?.audioPath)
        await hold(viewModel, for: 2)
        XCTAssertEqual(try storedFiles(), [promisePath])
        await viewModel.commit()

        let commitments = await store.commitments
        XCTAssertEqual(commitments.first?.declarationAudioPath, promisePath)
        XCTAssertEqual(commitments.first?.isVoiceless, false)
        XCTAssertEqual(try storedFiles(), [promisePath])
        let entries = await store.entries
        XCTAssertEqual(entries.compactMap(\.audioPath), [promisePath])
        let noon = await alarms.request(.noon, on: clock.now)
        XCTAssertEqual(noon?.voiceRelativePath, promisePath)
    }

    /// 約束を文字で入力し、アクションだけ声で話した日は、声の無い約束（アラームは既定の音）。録音は残らない。
    func testTextPromiseWithSpokenActionIsAVoicelessPromise() async throws {
        let (viewModel, _) = makeViewModel(transcript: ["資料を開く"])
        viewModel.useTextInput()
        viewModel.submitText("企画書を出す")
        viewModel.useVoiceInput()
        await hold(viewModel, for: 2)
        XCTAssertEqual(viewModel.stage, .confirm)
        await viewModel.commit()

        let commitments = await store.commitments
        let saved = try XCTUnwrap(commitments.first)
        XCTAssertNil(saved.declarationAudioPath)
        XCTAssertTrue(saved.isVoiceless)
        XCTAssertEqual(saved.microAction.text, "資料を開く")
        XCTAssertEqual(try storedFiles(), [], "アクションの録音は残らない")
        let entries = await store.entries
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries.first?.audioPath)
        let noon = await alarms.request(.noon, on: clock.now)
        XCTAssertNil(noon?.voiceRelativePath, "アラームは既定の音")
        XCTAssertEqual(noon?.title, "資料を開く")
        let line = try XCTUnwrap(viewModel.completionLine)
        XCTAssertFalse(line.contains("あなたの声"))
    }

    func testWithoutAlarmPermissionThePromiseIsSavedAndTheLineDoesNotPromiseToFollow() async throws {
        await alarms.deny()
        let (viewModel, _) = makeViewModel(transcript: ["企画書を出す", "資料を開く"])
        await hold(viewModel, for: 2)
        await hold(viewModel, for: 2)
        await viewModel.commit()

        let commitments = await store.commitments
        XCTAssertEqual(commitments.count, 1)
        XCTAssertEqual(commitments.first?.avoidanceTitle, "企画書を出す")
        let authorizationRequests = await alarms.authorizationRequests
        XCTAssertEqual(authorizationRequests, 1, "権限は「約束する」を押した時点で求める")

        XCTAssertEqual(viewModel.stage, .done)
        XCTAssertEqual(viewModel.alarmOutcome, .notAuthorized)
        let line = try XCTUnwrap(viewModel.completionLine)
        XCTAssertFalse(line.contains("追いかけます"))
        XCTAssertEqual(line, PromiseCopy.completionNotAuthorized)
    }

    func testAlarmFailureKeepsThePromiseAndDoesNotPromiseToFollow() async throws {
        await alarms.failScheduling()
        let (viewModel, _) = makeViewModel(microphoneGranted: false)
        viewModel.submitText("企画書を出す")
        viewModel.submitText("資料を開く")
        await viewModel.commit()

        let commitments = await store.commitments
        XCTAssertEqual(commitments.count, 1)
        let line = try XCTUnwrap(viewModel.completionLine)
        XCTAssertFalse(line.contains("追いかけます"))
        XCTAssertEqual(line, PromiseCopy.completionAlarmUnavailable)
    }

    func testSaveFailureKeepsTheAnswersAndCanBeRetried() async throws {
        let (viewModel, _) = makeViewModel(transcript: ["企画書を出す", "資料を開く"])
        await hold(viewModel, for: 2)
        await hold(viewModel, for: 2)
        await store.failCreates(1)
        await viewModel.commit()

        XCTAssertEqual(viewModel.stage, .confirm)
        XCTAssertEqual(viewModel.notice, .saveUnavailable)
        XCTAssertNil(viewModel.completionLine)
        let calls = await alarms.scheduleCalls
        XCTAssertEqual(calls, 0, "保存できなかった約束でアラームを頼まない")
        XCTAssertEqual(try storedFiles().count, 1, "約束の録音は残す（アクションの録音は答えた時点で消えている）")

        await viewModel.commit()
        let commitments = await store.commitments
        XCTAssertEqual(commitments.count, 1)
        let rounds = await alarms.rounds(on: clock.now)
        XCTAssertEqual(rounds, [.morning, .noon, .evening])
        XCTAssertEqual(viewModel.stage, .done)
    }

    /// 実物の `Repository`（SwiftData）に保存しても、約束・言葉・録音がそろって残る。
    func testPromiseIsSavedThroughTheRepository() async throws {
        let repository = Repository(modelContainer: try SaydoModelContainer.make(inMemory: true))
        await repository.configure(audioFileStore: audioFiles)
        let (viewModel, _) = makeViewModel(
            transcript: ["企画書を出す", "資料を開く"],
            store: RepositoryPromiseStore(repository, calendar: Self.tokyo)
        )
        await hold(viewModel, for: 2)
        await hold(viewModel, for: 2)
        await viewModel.commit()
        XCTAssertEqual(viewModel.stage, .done)

        let today = try await repository.todayCommitment(on: clock.now, calendar: Self.tokyo)
        let saved = try XCTUnwrap(today)
        XCTAssertEqual(saved.avoidanceTitle, "企画書を出す")
        XCTAssertEqual(saved.microAction.text, "資料を開く")
        XCTAssertEqual(saved.plannedAt, Self.at(10))
        XCTAssertEqual(saved.outcome, .pending)
        let promisePath = try XCTUnwrap(saved.declarationAudioPath)

        // 記録の行は約束の 1 つだけ。録音は約束の声だけが残る。
        let entries = try await repository.entries(for: clock.now, calendar: Self.tokyo)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(try storedFiles(), [promisePath])
        XCTAssertTrue(entries.contains { $0.audioPath == promisePath && $0.kind == .declaration })

        // 起動時の掃除で、約束の声が消えない。
        let swept = try await repository.sweepOrphanAudioFiles()
        XCTAssertEqual(swept, [])
        XCTAssertEqual(try storedFiles(), [promisePath])
    }

    // MARK: 言い直す

    func testRedoReplacesTheAnswerAndDeletesTheOldRecording() async throws {
        let (viewModel, _) = makeViewModel(transcript: ["企画書を出す", "企画書を今日出す", "資料を開く"])
        await hold(viewModel, for: 2)
        let oldPath = try XCTUnwrap(viewModel.answers[.promise]?.audioPath)
        XCTAssertTrue(audioFiles.fileExists(atRelativePath: oldPath))

        viewModel.redo(.promise)
        XCTAssertEqual(viewModel.stage, .promise)
        XCTAssertNil(viewModel.answers[.promise])
        XCTAssertFalse(audioFiles.fileExists(atRelativePath: oldPath), "前の録音ファイルは消す")

        await hold(viewModel, for: 2)
        let newPath = try XCTUnwrap(viewModel.answers[.promise]?.audioPath)
        XCTAssertEqual(viewModel.answers[.promise]?.text, "企画書を今日出す")
        XCTAssertNotEqual(newPath, oldPath)
        XCTAssertEqual(try storedFiles(), [newPath])
        XCTAssertEqual(viewModel.stage, .action)

        // 時刻の段階から約束を言い直しても、アクションの答えは残る。
        await hold(viewModel, for: 2)
        XCTAssertEqual(viewModel.stage, .confirm)
        viewModel.redo(.promise)
        XCTAssertEqual(viewModel.stage, .promise)
        XCTAssertEqual(viewModel.answers[.action]?.text, "資料を開く")
        viewModel.useTextInput()
        viewModel.submitText("企画書を必ず出す")
        XCTAssertEqual(viewModel.stage, .confirm)
        XCTAssertEqual(viewModel.answers[.promise]?.text, "企画書を必ず出す")
    }

    // MARK: 閉じる

    func testClosingMidwayStopsRecordingAndSavesNothing() async throws {
        let (viewModel, _) = makeViewModel(transcript: ["企画書を出す", "資料を開く"])
        await hold(viewModel, for: 2)
        XCTAssertEqual(try storedFiles().count, 1)

        viewModel.pressBegan()
        await viewModel.waitForPendingWork()
        XCTAssertTrue(capture.isCapturing)
        XCTAssertEqual(try storedFiles().count, 2)

        viewModel.close()
        XCTAssertFalse(capture.isCapturing, "閉じたら録音を止める")
        XCTAssertEqual(try storedFiles(), [], "保存していない録音ファイルは残さない")

        // 閉じた後の操作は何も起こさない。
        viewModel.pressEnded()
        viewModel.pressBegan()
        await viewModel.waitForPendingWork()
        await viewModel.commit()
        XCTAssertFalse(capture.isCapturing)
        XCTAssertEqual(capture.startCount, 2)

        let commitments = await store.commitments
        XCTAssertEqual(commitments, [])
        let entries = await store.entries
        XCTAssertEqual(entries, [])
        let calls = await alarms.scheduleCalls
        XCTAssertEqual(calls, 0)
    }

    func testClosingAfterThePromiseIsSavedKeepsTheRecordings() async throws {
        let (viewModel, _) = makeViewModel(transcript: ["企画書を出す", "資料を開く"])
        await hold(viewModel, for: 2)
        await hold(viewModel, for: 2)
        await viewModel.commit()
        let before = try storedFiles()
        XCTAssertEqual(before.count, 1, "約束の録音だけ")

        viewModel.close()
        XCTAssertEqual(try storedFiles(), before, "約束の声は消さない")
    }
}
