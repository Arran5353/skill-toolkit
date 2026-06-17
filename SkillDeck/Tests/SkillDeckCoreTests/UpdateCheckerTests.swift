import XCTest
@testable import SkillDeckCore

final class UpdateCheckerTests: XCTestCase {
    func test_newer_patch() { XCTAssertTrue(UpdateChecker.isNewer(latest: "1.0.1", than: "1.0.0")) }
    func test_newer_minor_double_digit() { XCTAssertTrue(UpdateChecker.isNewer(latest: "1.10.0", than: "1.9.0")) }
    func test_equal_is_not_newer() { XCTAssertFalse(UpdateChecker.isNewer(latest: "1.2.3", than: "1.2.3")) }
    func test_older_is_not_newer() { XCTAssertFalse(UpdateChecker.isNewer(latest: "1.0.0", than: "1.1.0")) }
    func test_v_prefix_tolerated() { XCTAssertTrue(UpdateChecker.isNewer(latest: "v2.0.0", than: "1.9.9")) }
    func test_different_length() { XCTAssertTrue(UpdateChecker.isNewer(latest: "1.1", than: "1.0.5")); XCTAssertFalse(UpdateChecker.isNewer(latest: "1.0", than: "1.0.0")) }
}
