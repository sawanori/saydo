import XCTest

@testable import Saydo

final class LaunchSafetyTests: XCTestCase {
    func testSweepIsSkippedOnInMemoryStore() {
        XCTAssertFalse(SaydoApp.shouldSweepOrphanAudio(isPersistent: false))
    }

    func testSweepRunsOnPersistentStore() {
        XCTAssertTrue(SaydoApp.shouldSweepOrphanAudio(isPersistent: true))
    }
}
