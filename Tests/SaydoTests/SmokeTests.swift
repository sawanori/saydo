import XCTest

final class SmokeTests: XCTestCase {
    func testBundleIdentifierIsSaydo() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.nonturn.saydo")
    }
}
