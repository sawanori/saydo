import Foundation
import XCTest

@testable import Saydo

/// `AppSettings` は `@MainActor`（`UserDefaults` が非 Sendable のため）。
/// `XCTestCase` の `setUp` / `tearDown` の override は nonisolated なので、
/// 状態はプロパティに置かず、各テストの中で作って捨てる。
final class AppSettingsTests: XCTestCase {
    @MainActor
    private func withSettings(_ body: (AppSettings, UserDefaults) throws -> Void) throws {
        let suiteName = "saydo.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(AppSettings(defaults: defaults), defaults)
    }

    /// 追う回の既定の時刻（実装計画 §17.10）。
    @MainActor
    func testDefaultsMatchThePlan() throws {
        try withSettings { settings, _ in
            // 1 日に追うのはこの 3 回まで。
            XCTAssertEqual(settings.morningTime, TimeOfDay(hour: 10, minute: 0))
            XCTAssertEqual(settings.noonTime, TimeOfDay(hour: 14, minute: 0))
            XCTAssertEqual(settings.nightTime, TimeOfDay(hour: 19, minute: 0))
            XCTAssertFalse(settings.hasCompletedOnboarding)
        }
    }

    @MainActor
    func testValuesRoundTripThroughUserDefaults() throws {
        try withSettings { settings, defaults in
            settings.morningTime = TimeOfDay(hour: 6, minute: 45)
            settings.noonTime = TimeOfDay(hour: 12, minute: 30)
            settings.nightTime = TimeOfDay(hour: 23, minute: 15)
            settings.hasCompletedOnboarding = true

            let reloaded = AppSettings(defaults: defaults)

            XCTAssertEqual(reloaded.morningTime, TimeOfDay(hour: 6, minute: 45))
            XCTAssertEqual(reloaded.noonTime, TimeOfDay(hour: 12, minute: 30))
            XCTAssertEqual(reloaded.nightTime, TimeOfDay(hour: 23, minute: 15))
            XCTAssertTrue(reloaded.hasCompletedOnboarding)
        }
    }

    @MainActor
    func testResetRestoresDefaults() throws {
        try withSettings { settings, _ in
            settings.morningTime = TimeOfDay(hour: 5, minute: 0)
            settings.hasCompletedOnboarding = true

            settings.reset()

            XCTAssertEqual(settings.morningTime, TimeOfDay(hour: 10, minute: 0))
            XCTAssertFalse(settings.hasCompletedOnboarding)
        }
    }

    func testTimeOfDayClampsAndOrders() {
        XCTAssertEqual(TimeOfDay(hour: 99, minute: 99), TimeOfDay(hour: 23, minute: 59))
        XCTAssertEqual(TimeOfDay(minutesFromMidnight: 8 * 60 + 5), TimeOfDay(hour: 8, minute: 5))
        XCTAssertLessThan(TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 13, minute: 0))
        XCTAssertEqual(TimeOfDay(hour: 13, minute: 0).dateComponents.hour, 13)
    }
}
