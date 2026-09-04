import Foundation
import SaydoCore
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

    /// fix-decisions P1.4 の既定値。
    @MainActor
    func testDefaultsMatchThePlan() throws {
        try withSettings { settings, _ in
            XCTAssertEqual(settings.morningTime, TimeOfDay(hour: 8, minute: 0))
            XCTAssertEqual(settings.noonTime, TimeOfDay(hour: 13, minute: 0))
            XCTAssertEqual(settings.nightTime, TimeOfDay(hour: 21, minute: 0))
            XCTAssertEqual(settings.silenceThresholdSeconds, 1.5, accuracy: 0.0001)
            XCTAssertNil(settings.speechVoiceIdentifier)
            XCTAssertEqual(settings.notificationMode, .twoPerDay)
            XCTAssertTrue(settings.weekendNotificationsEnabled)
            XCTAssertNil(settings.aloneTime)
            XCTAssertFalse(settings.hasCompletedOnboarding)
        }
    }

    /// retention-strategy.md R2: 既定は朝 + 行動時刻。昼と夜は「3 回モード」で足す。
    @MainActor
    func testNotificationModeDecidesWhichFixedNotificationsFire() throws {
        try withSettings { settings, _ in
            XCTAssertEqual(settings.notificationMode.fixedSessionTypes, [.morning])
            XCTAssertEqual(settings.fixedNotificationTime(for: .morning), TimeOfDay(hour: 8, minute: 0))
            XCTAssertNil(settings.fixedNotificationTime(for: .noon))
            XCTAssertNil(settings.fixedNotificationTime(for: .night))

            settings.notificationMode = .threePerDay

            XCTAssertEqual(settings.notificationMode.fixedSessionTypes, [.morning, .noon, .night])
            XCTAssertEqual(settings.fixedNotificationTime(for: .noon), TimeOfDay(hour: 13, minute: 0))
            XCTAssertEqual(settings.fixedNotificationTime(for: .night), TimeOfDay(hour: 21, minute: 0))
            XCTAssertNil(settings.fixedNotificationTime(for: .adhoc))
        }
    }

    @MainActor
    func testValuesRoundTripThroughUserDefaults() throws {
        try withSettings { settings, defaults in
            settings.morningTime = TimeOfDay(hour: 6, minute: 45)
            settings.silenceThresholdSeconds = 2.0
            settings.speechVoiceIdentifier = "com.apple.voice.example"
            settings.weekendNotificationsEnabled = false
            settings.aloneTime = TimeOfDay(hour: 22, minute: 30)
            settings.hasCompletedOnboarding = true

            let reloaded = AppSettings(defaults: defaults)

            XCTAssertEqual(reloaded.morningTime, TimeOfDay(hour: 6, minute: 45))
            XCTAssertEqual(reloaded.silenceThresholdSeconds, 2.0, accuracy: 0.0001)
            XCTAssertEqual(reloaded.speechVoiceIdentifier, "com.apple.voice.example")
            XCTAssertFalse(reloaded.weekendNotificationsEnabled)
            XCTAssertEqual(reloaded.aloneTime, TimeOfDay(hour: 22, minute: 30))
            XCTAssertEqual(reloaded.effectiveAloneTime, TimeOfDay(hour: 22, minute: 30))
            XCTAssertTrue(reloaded.hasCompletedOnboarding)
        }
    }

    /// 一人で話せる時間が未設定のうちは夜の時刻を使う（retention-strategy.md R1）。
    @MainActor
    func testEffectiveAloneTimeFallsBackToTheNightTime() throws {
        try withSettings { settings, _ in
            settings.nightTime = TimeOfDay(hour: 23, minute: 15)

            XCTAssertNil(settings.aloneTime)
            XCTAssertEqual(settings.effectiveAloneTime, TimeOfDay(hour: 23, minute: 15))
        }
    }

    /// 設定画面に無い値が入っても既定に戻す（実装計画 §7.3 の 1.2 / 1.5 / 2.0）。
    @MainActor
    func testSilenceThresholdRejectsValuesOutsideTheChoices() throws {
        try withSettings { settings, _ in
            settings.silenceThresholdSeconds = 9.9

            XCTAssertEqual(settings.silenceThresholdSeconds, 1.5, accuracy: 0.0001)
            XCTAssertEqual(AppSettings.silenceThresholdChoices, [1.2, 1.5, 2.0])
        }
    }

    @MainActor
    func testResetRestoresDefaults() throws {
        try withSettings { settings, _ in
            settings.morningTime = TimeOfDay(hour: 5, minute: 0)
            settings.notificationMode = .threePerDay
            settings.hasCompletedOnboarding = true

            settings.reset()

            XCTAssertEqual(settings.morningTime, TimeOfDay(hour: 8, minute: 0))
            XCTAssertEqual(settings.notificationMode, .twoPerDay)
            XCTAssertFalse(settings.hasCompletedOnboarding)
        }
    }

    // MARK: - 「話せない時」を自動で使う時間帯（task_013）

    @MainActor
    func testQuietModeScheduleDefaultsAreOffFromNineToSix() throws {
        try withSettings { settings, _ in
            XCTAssertFalse(settings.quietModeScheduleEnabled)
            XCTAssertEqual(settings.quietModeStart, TimeOfDay(hour: 9, minute: 0))
            XCTAssertEqual(settings.quietModeEnd, TimeOfDay(hour: 18, minute: 0))
            // 既定は切ってあるので、帯の中の時刻でも false。
            XCTAssertFalse(settings.isQuietMode(at: TimeOfDay(hour: 12, minute: 0).date()))
        }
    }

    /// 開始と同じ時刻は含み、終了と同じ時刻は含まない。
    @MainActor
    func testQuietModeIncludesTheStartAndExcludesTheEnd() throws {
        try withSettings { settings, _ in
            settings.quietModeScheduleEnabled = true

            XCTAssertFalse(settings.isQuietMode(at: TimeOfDay(hour: 8, minute: 59).date()))
            XCTAssertTrue(settings.isQuietMode(at: TimeOfDay(hour: 9, minute: 0).date()))
            XCTAssertTrue(settings.isQuietMode(at: TimeOfDay(hour: 17, minute: 59).date()))
            XCTAssertFalse(settings.isQuietMode(at: TimeOfDay(hour: 18, minute: 0).date()))
        }
    }

    /// 終了が開始より前なら日をまたぐ帯として扱う。
    @MainActor
    func testQuietModeWrapsAroundMidnight() throws {
        try withSettings { settings, _ in
            settings.quietModeScheduleEnabled = true
            settings.quietModeStart = TimeOfDay(hour: 22, minute: 0)
            settings.quietModeEnd = TimeOfDay(hour: 6, minute: 0)

            XCTAssertTrue(settings.isQuietMode(at: TimeOfDay(hour: 22, minute: 0).date()))
            XCTAssertTrue(settings.isQuietMode(at: TimeOfDay(hour: 23, minute: 30).date()))
            XCTAssertTrue(settings.isQuietMode(at: TimeOfDay(hour: 5, minute: 59).date()))
            XCTAssertFalse(settings.isQuietMode(at: TimeOfDay(hour: 6, minute: 0).date()))
            XCTAssertFalse(settings.isQuietMode(at: TimeOfDay(hour: 21, minute: 59).date()))
        }
    }

    /// 開始と終了が同じなら幅 0 の帯。どの時刻も外。
    @MainActor
    func testQuietModeWithTheSameStartAndEndCoversNothing() throws {
        try withSettings { settings, _ in
            settings.quietModeScheduleEnabled = true
            settings.quietModeStart = TimeOfDay(hour: 10, minute: 0)
            settings.quietModeEnd = TimeOfDay(hour: 10, minute: 0)

            XCTAssertFalse(settings.isQuietMode(at: TimeOfDay(hour: 10, minute: 0).date()))
            XCTAssertFalse(settings.isQuietMode(at: TimeOfDay(hour: 3, minute: 0).date()))
        }
    }

    @MainActor
    func testQuietModeSettingsRoundTripAndReset() throws {
        try withSettings { settings, defaults in
            settings.quietModeScheduleEnabled = true
            settings.quietModeStart = TimeOfDay(hour: 7, minute: 30)
            settings.quietModeEnd = TimeOfDay(hour: 19, minute: 45)

            let reloaded = AppSettings(defaults: defaults)
            XCTAssertTrue(reloaded.quietModeScheduleEnabled)
            XCTAssertEqual(reloaded.quietModeStart, TimeOfDay(hour: 7, minute: 30))
            XCTAssertEqual(reloaded.quietModeEnd, TimeOfDay(hour: 19, minute: 45))

            reloaded.reset()

            XCTAssertFalse(reloaded.quietModeScheduleEnabled)
            XCTAssertEqual(reloaded.quietModeStart, TimeOfDay(hour: 9, minute: 0))
            XCTAssertEqual(reloaded.quietModeEnd, TimeOfDay(hour: 18, minute: 0))
        }
    }

    /// 通知計画（`SaydoCore`）へ渡す形への変換。
    @MainActor
    func testNotificationSettingsBridgeCarriesTheChosenValues() throws {
        try withSettings { settings, _ in
            XCTAssertEqual(settings.notificationSettings.mode, SaydoCore.NotificationMode.twice)
            XCTAssertEqual(settings.notificationSettings.morning, SaydoCore.TimeOfDay(hour: 8, minute: 0))
            XCTAssertTrue(settings.notificationSettings.weekendEnabled)

            settings.notificationMode = .threePerDay
            settings.nightTime = TimeOfDay(hour: 22, minute: 10)
            settings.weekendNotificationsEnabled = false

            XCTAssertEqual(settings.notificationSettings.mode, SaydoCore.NotificationMode.thrice)
            XCTAssertEqual(settings.notificationSettings.night, SaydoCore.TimeOfDay(hour: 22, minute: 10))
            XCTAssertFalse(settings.notificationSettings.weekendEnabled)
        }
    }

    /// `TimeOfDay` はアプリ側（`Saydo`）と `SaydoCore` の両方にある。このテストが見るのは
    /// アプリ側の値丸めと順序なので、文脈から型が決まらない行は `Saydo.` で明示する。
    func testTimeOfDayClampsAndOrders() {
        XCTAssertEqual(Saydo.TimeOfDay(hour: 99, minute: 99), Saydo.TimeOfDay(hour: 23, minute: 59))
        XCTAssertEqual(TimeOfDay(minutesFromMidnight: 8 * 60 + 5), TimeOfDay(hour: 8, minute: 5))
        XCTAssertLessThan(Saydo.TimeOfDay(hour: 8, minute: 0), Saydo.TimeOfDay(hour: 13, minute: 0))
        XCTAssertEqual(TimeOfDay(hour: 13, minute: 0).dateComponents.hour, 13)
    }
}
