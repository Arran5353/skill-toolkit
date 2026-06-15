import XCTest
@testable import SkillDeckCore

final class InstallerCommandTests: XCTestCase {
    func test_install_arguments_for_ref() {
        let args = Installer.installArguments(installRef: "ralph-loop@official")
        XCTAssertEqual(args, ["plugin", "install", "ralph-loop@official"])
    }

    func test_fallback_claude_path() {
        let p = Installer.fallbackClaudePath
        XCTAssertTrue(p.hasSuffix("/.local/bin/claude"))
    }
}
