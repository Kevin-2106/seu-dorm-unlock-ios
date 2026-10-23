import XCTest
@testable import DoorCrypto

final class UnlockFailureTests: XCTestCase {
    func testExpiredAndExhaustedOfferRefresh() {
        XCTAssertEqual(UnlockFailure.fromCode(24).action, .refreshCredentials)
        XCTAssertEqual(UnlockFailure.fromCode(25).action, .refreshCredentials)
    }

    func testKeyUpdateNeedsNoButton() {
        XCTAssertNil(UnlockFailure.fromCode(27).action)
    }

    func testUnknownCodeKeepsCodeAndOffersRefresh() {
        let f = UnlockFailure.fromCode(99)
        XCTAssertEqual(f.code, 99)
        XCTAssertTrue(f.title.contains("99"))
        XCTAssertEqual(f.action, .refreshCredentials)
    }

    func testPlainHasNoCode() {
        XCTAssertNil(UnlockFailure.plain("蓝牙未开启").code)
    }
}
