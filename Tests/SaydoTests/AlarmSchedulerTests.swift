import Foundation
import SaydoCore
import XCTest

@testable import Saydo

/// `AlarmBackend` の記録するだけの実装。呼ばれた順に残す。
actor RecordingAlarmBackend: AlarmBackend {
    enum Event: Equatable, Sendable {
        case cancel(UUID)
        case schedule(id: UUID, fireDate: Date, soundName: String?)
    }

    struct Refused: Error {}

    private(set) var events: [Event] = []
    private(set) var authorizationRequests = 0
    /// いま登録されている識別子。実物と同じく、無い識別子の取り消しはエラーにする。
    private(set) var registered: Set<UUID> = []

    private var state: AlarmAuthorization
    private let stateAfterRequest: AlarmAuthorization
    /// この連番（0 始まり、登録の試行順）の登録を失敗させる。
    private var failingAttempts: Set<Int>
    private var failsEverySchedule: Bool
    private var attempts = 0

    init(
        state: AlarmAuthorization = .authorized,
        stateAfterRequest: AlarmAuthorization = .authorized,
        failingAttempts: Set<Int> = [],
        failsEverySchedule: Bool = false
    ) {
        self.state = state
        self.stateAfterRequest = stateAfterRequest
        self.failingAttempts = failingAttempts
        self.failsEverySchedule = failsEverySchedule
    }

    func authorization() async -> AlarmAuthorization { state }

    func requestAuthorization() async -> AlarmAuthorization {
        authorizationRequests += 1
        if state == .notDetermined { state = stateAfterRequest }
        return state
    }

    func schedule(id: UUID, fireDate: Date, soundName: String?) async throws {
        let attempt = attempts
        attempts += 1
        if failsEverySchedule || failingAttempts.contains(attempt) { throw Refused() }
        registered.insert(id)
        events.append(.schedule(id: id, fireDate: fireDate, soundName: soundName))
    }

    func cancel(id: UUID) async throws {
        events.append(.cancel(id))
        guard registered.remove(id) != nil else { throw Refused() }
    }

    var cancelledIDs: [UUID] {
        events.compactMap { if case .cancel(let id) = $0 { id } else { nil } }
    }

    var scheduled: [(id: UUID, fireDate: Date, soundName: String?)] {
        events.compactMap {
            if case .schedule(let id, let fireDate, let soundName) = $0 { (id, fireDate, soundName) } else { nil }
        }
    }

    func clearEvents() {
        events = []
    }
}

final class AlarmSchedulerTests: XCTestCase {

    private let tokyo: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    private var temporaryRoots: [URL] = []

    override func tearDownWithError() throws {
        for root in temporaryRoots where FileManager.default.fileExists(atPath: root.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: root)
        }
        temporaryRoots = []
        try super.tearDownWithError()
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try XCTUnwrap(tokyo.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)))
    }

    private func makeScheduler(
        backend: RecordingAlarmBackend,
        soundStore: AlarmSoundStore? = nil,
        now: Date
    ) -> AlarmScheduler {
        AlarmScheduler(backend: backend, soundStore: soundStore, calendar: tokyo, now: { now })
    }

    private func makeSoundStore() -> (store: AlarmSoundStore, audioFiles: AudioFileStore) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SaydoAlarmSchedulerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        temporaryRoots.append(root)
        let audioFiles = AudioFileStore(rootDirectory: root.appending(path: "Audio", directoryHint: .isDirectory))
        let store = AlarmSoundStore(
            soundsDirectory: root.appending(path: "Sounds", directoryHint: .isDirectory),
            audioFileStore: audioFiles
        )
        return (store, audioFiles)
    }

    // MARK: 登録

    func testScheduleChainCancelsTheWholeDayBeforeRegisteringEveryThreeMinutes() async throws {
        let start = try date(6, 16)
        let backend = RecordingAlarmBackend()
        let scheduler = makeScheduler(backend: backend, now: try date(6, 15, 30))

        let outcome = await scheduler.scheduleChain(start: start, voiceRelativePath: nil)

        XCTAssertEqual(outcome, .scheduled(count: 60))
        let events = await backend.events
        let dayIDs = AlarmPlan.identifiers(on: start, calendar: tokyo)
        XCTAssertEqual(dayIDs.count, 60)

        // 先頭の 60 件が、その日の全識別子の取り消し。登録はその後にだけ並ぶ。
        XCTAssertEqual(Array(events.prefix(60)), dayIDs.map { .cancel($0) })
        let registrations = Array(events.dropFirst(60))
        XCTAssertEqual(registrations.count, 60)
        for (index, event) in registrations.enumerated() {
            XCTAssertEqual(
                event,
                .schedule(id: dayIDs[index], fireDate: start.addingTimeInterval(180 * Double(index)), soundName: nil)
            )
        }
        let lastFireDate = await backend.scheduled.last?.fireDate
        XCTAssertEqual(lastFireDate, try date(6, 18, 57))
    }

    func testScheduleChainReplacesAChainAlreadyRegisteredOnTheSameDay() async throws {
        let backend = RecordingAlarmBackend()
        let scheduler = makeScheduler(backend: backend, now: try date(6, 9))
        _ = await scheduler.scheduleChain(start: try date(6, 12), voiceRelativePath: nil)
        await backend.clearEvents()

        let outcome = await scheduler.scheduleChain(start: try date(6, 18), voiceRelativePath: nil)

        XCTAssertEqual(outcome, .scheduled(count: 60))
        let events = await backend.events
        XCTAssertEqual(events.prefix(60).map { $0 }, AlarmPlan.identifiers(on: try date(6, 18), calendar: tokyo).map { .cancel($0) })
        let fireDates = await backend.scheduled.map(\.fireDate)
        XCTAssertEqual(fireDates.first, try date(6, 18))
        let registered = await backend.registered
        XCTAssertEqual(registered.count, 60)
    }

    func testScheduleChainSkipsTheSlotsThatHaveAlreadyPassed() async throws {
        let start = try date(6, 16)
        let backend = RecordingAlarmBackend()
        // 16:07。16:00 / 16:03 / 16:06 は過ぎている。
        let scheduler = makeScheduler(backend: backend, now: try date(6, 16, 7))

        let outcome = await scheduler.scheduleChain(start: start, voiceRelativePath: nil)

        XCTAssertEqual(outcome, .scheduled(count: 57))
        let scheduled = await backend.scheduled
        XCTAssertEqual(scheduled.first?.fireDate, try date(6, 16, 9))
        XCTAssertEqual(scheduled.first?.id, AlarmPlan.identifier(on: start, index: 3, calendar: tokyo))
        let now = try date(6, 16, 7)
        XCTAssertTrue(scheduled.allSatisfy { $0.fireDate > now })
    }

    func testScheduleChainFailsWhenEverySlotHasPassed() async throws {
        let backend = RecordingAlarmBackend()
        let scheduler = makeScheduler(backend: backend, now: try date(6, 20))

        let outcome = await scheduler.scheduleChain(start: try date(6, 16), voiceRelativePath: nil)

        XCTAssertEqual(outcome, .failed)
        let scheduled = await backend.scheduled
        XCTAssertTrue(scheduled.isEmpty)
    }

    func testScheduleChainFailsWhenNothingCouldBeRegistered() async throws {
        let backend = RecordingAlarmBackend(failsEverySchedule: true)
        let scheduler = makeScheduler(backend: backend, now: try date(6, 15))

        let outcome = await scheduler.scheduleChain(start: try date(6, 16), voiceRelativePath: nil)

        XCTAssertEqual(outcome, .failed)
    }

    func testScheduleChainCountsOnlyTheAlarmsThatWereRegistered() async throws {
        let backend = RecordingAlarmBackend(failingAttempts: [0, 10])
        let scheduler = makeScheduler(backend: backend, now: try date(6, 15))

        let outcome = await scheduler.scheduleChain(start: try date(6, 16), voiceRelativePath: nil)

        XCTAssertEqual(outcome, .scheduled(count: 58))
        let registered = await backend.registered
        XCTAssertEqual(registered.count, 58)
    }

    func testAChainThatCrossesMidnightUsesTheStartDaysIdentifiers() async throws {
        let start = try date(6, 23, 30)
        let backend = RecordingAlarmBackend()
        let scheduler = makeScheduler(backend: backend, now: try date(6, 23))

        _ = await scheduler.scheduleChain(start: start, voiceRelativePath: nil)
        let scheduled = await backend.scheduled
        XCTAssertEqual(scheduled.map(\.id), AlarmPlan.identifiers(on: start, calendar: tokyo))
        XCTAssertEqual(scheduled.last?.fireDate, try date(7, 2, 27))

        // 取り消しも開始日で行う。翌日の日付では 1 本も消えない。
        await scheduler.cancelChain(startedOn: try date(7, 1))
        var registered = await backend.registered
        XCTAssertEqual(registered.count, 60)
        await scheduler.cancelChain(startedOn: start)
        registered = await backend.registered
        XCTAssertTrue(registered.isEmpty)
    }

    // MARK: 権限

    func testScheduleChainReturnsNotAuthorizedWhenDenied() async throws {
        let backend = RecordingAlarmBackend(state: .denied)
        let scheduler = makeScheduler(backend: backend, now: try date(6, 15))

        let outcome = await scheduler.scheduleChain(start: try date(6, 16), voiceRelativePath: nil)

        XCTAssertEqual(outcome, .notAuthorized)
        let events = await backend.events
        XCTAssertTrue(events.isEmpty)
    }

    func testScheduleChainAsksOnceWhenAuthorizationIsUndetermined() async throws {
        let granted = RecordingAlarmBackend(state: .notDetermined, stateAfterRequest: .authorized)
        let grantedOutcome = await makeScheduler(backend: granted, now: try date(6, 15))
            .scheduleChain(start: try date(6, 16), voiceRelativePath: nil)
        XCTAssertEqual(grantedOutcome, .scheduled(count: 60))
        let grantedRequests = await granted.authorizationRequests
        XCTAssertEqual(grantedRequests, 1)

        let refused = RecordingAlarmBackend(state: .notDetermined, stateAfterRequest: .denied)
        let refusedOutcome = await makeScheduler(backend: refused, now: try date(6, 15))
            .scheduleChain(start: try date(6, 16), voiceRelativePath: nil)
        XCTAssertEqual(refusedOutcome, .notAuthorized)
        let refusedScheduled = await refused.scheduled
        XCTAssertTrue(refusedScheduled.isEmpty)
    }

    func testRequestAuthorizationReportsWhetherItWasGranted() async throws {
        let granted = makeScheduler(
            backend: RecordingAlarmBackend(state: .notDetermined, stateAfterRequest: .authorized),
            now: try date(6, 15)
        )
        let refused = makeScheduler(
            backend: RecordingAlarmBackend(state: .notDetermined, stateAfterRequest: .denied),
            now: try date(6, 15)
        )

        let grantedResult = await granted.requestAuthorization()
        let refusedResult = await refused.requestAuthorization()
        XCTAssertTrue(grantedResult)
        XCTAssertFalse(refusedResult)
    }

    // MARK: 取り消し

    func testCancelChainCancelsEveryIdentifierOfThatDay() async throws {
        let start = try date(6, 16)
        let backend = RecordingAlarmBackend()
        let scheduler = makeScheduler(backend: backend, now: try date(6, 15))
        _ = await scheduler.scheduleChain(start: start, voiceRelativePath: nil)
        await backend.clearEvents()

        // 開始時刻ではなく、その日のどの時刻を渡しても同じ識別子になる。
        await scheduler.cancelChain(startedOn: try date(6, 21, 45))

        let cancelled = await backend.cancelledIDs
        XCTAssertEqual(cancelled, AlarmPlan.identifiers(on: start, calendar: tokyo))
        XCTAssertEqual(cancelled.count, AlarmPlan.defaultCount)
        let registered = await backend.registered
        XCTAssertTrue(registered.isEmpty)
    }

    func testCancelChainIgnoresIdentifiersThatWereNeverRegistered() async throws {
        let backend = RecordingAlarmBackend()
        let scheduler = makeScheduler(backend: backend, now: try date(6, 15))

        // 1 本も登録していない日。全部の取り消しがエラーになるが、最後まで進む。
        await scheduler.cancelChain(startedOn: try date(6, 16))

        let cancelled = await backend.cancelledIDs
        XCTAssertEqual(cancelled, AlarmPlan.identifiers(on: try date(6, 16), calendar: tokyo))
    }

    func testCancelChainLeavesAnotherDaysChainAlone() async throws {
        let backend = RecordingAlarmBackend()
        let scheduler = makeScheduler(backend: backend, now: try date(6, 15))
        _ = await scheduler.scheduleChain(start: try date(6, 16), voiceRelativePath: nil)
        _ = await scheduler.scheduleChain(start: try date(7, 16), voiceRelativePath: nil)

        await scheduler.cancelChain(startedOn: try date(6, 16))

        let registered = await backend.registered
        XCTAssertEqual(registered, Set(AlarmPlan.identifiers(on: try date(7, 16), calendar: tokyo)))
    }

    // MARK: 音

    func testScheduleChainUsesTheExportedVoiceAsTheSound() async throws {
        let (soundStore, audioFiles) = makeSoundStore()
        let start = try date(6, 16)
        let allocation = try audioFiles.allocate(recordedAt: start, calendar: tokyo)
        try AlarmTestAudio.writeVoice(to: allocation.url, seconds: 2)
        let backend = RecordingAlarmBackend()
        let scheduler = makeScheduler(backend: backend, soundStore: soundStore, now: try date(6, 15))

        let outcome = await scheduler.scheduleChain(start: start, voiceRelativePath: allocation.relativePath)

        XCTAssertEqual(outcome, .scheduled(count: 60))
        let expectedName = soundStore.fileName(for: start, calendar: tokyo)
        let soundNames = await backend.scheduled.map(\.soundName)
        XCTAssertEqual(Set(soundNames), [expectedName])
        let soundURL = soundStore.url(for: start, calendar: tokyo)
        XCTAssertTrue(FileManager.default.fileExists(atPath: soundURL.path(percentEncoded: false)))

        // 取り消すと音のファイルも消える。
        await scheduler.cancelChain(startedOn: start)
        XCTAssertFalse(FileManager.default.fileExists(atPath: soundURL.path(percentEncoded: false)))
    }

    func testScheduleChainFallsBackToTheDefaultSound() async throws {
        let (soundStore, _) = makeSoundStore()
        let start = try date(6, 16)

        // 文字で約束した日（声が無い）。
        let voiceless = RecordingAlarmBackend()
        _ = await makeScheduler(backend: voiceless, soundStore: soundStore, now: try date(6, 15))
            .scheduleChain(start: start, voiceRelativePath: nil)
        let voicelessNames = await voiceless.scheduled.map(\.soundName)
        XCTAssertEqual(voicelessNames.count, 60)
        XCTAssertTrue(voicelessNames.allSatisfy { $0 == nil })

        // 声のファイルが見つからず、書き出せなかった日。
        let missing = RecordingAlarmBackend()
        let outcome = await makeScheduler(backend: missing, soundStore: soundStore, now: try date(6, 15))
            .scheduleChain(start: start, voiceRelativePath: "2026/10/missing.m4a")
        XCTAssertEqual(outcome, .scheduled(count: 60))
        let missingNames = await missing.scheduled.map(\.soundName)
        XCTAssertTrue(missingNames.allSatisfy { $0 == nil })
    }
}
