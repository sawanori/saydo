import Foundation
import os
import SaydoCore

@testable import Saydo

/// `AlarmScheduling` の記録するだけの実装（task_058）。AlarmKit には触らない。
///
/// 実物と同じく、`scheduleRounds` はその日の登録を丸ごと置き換える。`registered` を見れば、
/// いまどの日のどの回が登録されているかが分かる。
actor RecordingRoundAlarms: AlarmScheduling {
    enum Event: Equatable, Sendable {
        case schedule(dayKey: String, rounds: [AlarmRoundRequest])
        case cancelRound(dayKey: String, round: AlarmRound)
        case cancelDay(dayKey: String)
        case cancelAll
    }

    private let calendar: Calendar
    private(set) var events: [Event] = []
    private(set) var authorizationRequests = 0
    /// いま登録されている回。日付（`DayKey`）ごと。
    private(set) var registered: [String: [AlarmRound: AlarmRoundRequest]] = [:]
    private var isAuthorized = true
    private var failsToSchedule = false

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func deny() { isAuthorized = false }
    func failScheduling() { failsToSchedule = true }
    func clearEvents() { events = [] }

    /// その日に登録されている回（昇順）。
    func rounds(on day: Date) -> [AlarmRound] {
        (registered[DayKey.make(from: day, calendar: calendar)] ?? [:]).keys.sorted()
    }

    func request(_ round: AlarmRound, on day: Date) -> AlarmRoundRequest? {
        registered[DayKey.make(from: day, calendar: calendar)]?[round]
    }

    /// `scheduleRounds` が呼ばれた回数。
    var scheduleCalls: Int {
        events.filter { if case .schedule = $0 { true } else { false } }.count
    }

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return isAuthorized
    }

    func scheduleRounds(_ rounds: [AlarmRoundRequest], on day: Date) async -> AlarmScheduleOutcome {
        let key = DayKey.make(from: day, calendar: calendar)
        events.append(.schedule(dayKey: key, rounds: rounds))
        guard isAuthorized else { return .notAuthorized }
        if failsToSchedule { return .failed }
        registered[key] = Dictionary(uniqueKeysWithValues: rounds.map { ($0.round, $0) })
        return .scheduled(count: rounds.count * AlarmPlan.defaultCount)
    }

    func cancelRound(_ round: AlarmRound, on day: Date) async {
        let key = DayKey.make(from: day, calendar: calendar)
        events.append(.cancelRound(dayKey: key, round: round))
        registered[key]?[round] = nil
    }

    func cancelDay(_ day: Date) async {
        let key = DayKey.make(from: day, calendar: calendar)
        events.append(.cancelDay(dayKey: key))
        registered[key] = nil
    }

    func cancelAll() async {
        events.append(.cancelAll)
        registered = [:]
    }
}

/// テストが進める時計。
final class ChaseTestClock: Sendable {
    private let state: OSAllocatedUnfairLock<Date>

    init(_ date: Date) {
        state = OSAllocatedUnfairLock(initialState: date)
    }

    var now: Date { state.withLock { $0 } }

    func set(_ date: Date) {
        state.withLock { $0 = date }
    }
}

extension AppSettings {
    /// 回の時刻を、答え方・段階の判定の試験が前提にしている 朝 8:00・昼 13:00・晩 21:00 にそろえる。
    ///
    /// アプリの既定は 10:00・14:00・19:00（実装計画 §17.10）。この試験群は「どの回まで答えたか」の
    /// 扱いを確かめるもので、時刻の既定値は `AppSettingsTests` と `PromiseViewModelTests` が見る。
    @MainActor
    func useRoundTimesOfTheAnswerTests() {
        morningTime = TimeOfDay(hour: 8, minute: 0)
        noonTime = TimeOfDay(hour: 13, minute: 0)
        nightTime = TimeOfDay(hour: 21, minute: 0)
    }
}
