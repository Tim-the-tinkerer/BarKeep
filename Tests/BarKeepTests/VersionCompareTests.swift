import XCTest
@testable import BarKeepCore

final class VersionCompareTests: XCTestCase {
    func testEqualVersions() {
        XCTAssertEqual(VersionCompare.compare("1.2.0", "1.2.0"), .orderedSame)
        XCTAssertEqual(VersionCompare.compare("v1.2.0", "1.2.0"), .orderedSame)
        XCTAssertEqual(VersionCompare.compare("1.2", "1.2.0"), .orderedSame)
    }

    func testOrdering() {
        XCTAssertEqual(VersionCompare.compare("1.2.1", "1.2.2"), .orderedAscending)
        XCTAssertEqual(VersionCompare.compare("1.2.2", "1.2.1"), .orderedDescending)
        XCTAssertEqual(VersionCompare.compare("1.9.0", "1.10.0"), .orderedAscending)
        XCTAssertEqual(VersionCompare.compare("2.0.0", "1.9.9"), .orderedDescending)
    }

    func testVPrefixAndWhitespace() {
        XCTAssertEqual(VersionCompare.normalizeTag(" v1.2.3 "), "1.2.3")
        XCTAssertEqual(VersionCompare.compare("v1.2.3", "1.2.4"), .orderedAscending)
    }

    func testPrereleaseSuffixes() {
        // Final release is newer than prerelease of the same numbers.
        XCTAssertEqual(VersionCompare.compare("1.2.3-beta", "1.2.3"), .orderedAscending)
        XCTAssertEqual(VersionCompare.compare("1.2.3", "1.2.3-beta"), .orderedDescending)
        XCTAssertEqual(VersionCompare.compare("1.2.3-alpha", "1.2.3-beta"), .orderedAscending)
        XCTAssertEqual(VersionCompare.compare("1.2.3-beta.1", "1.2.3-beta.2"), .orderedAscending)
        XCTAssertEqual(VersionCompare.compare("1.2.3-beta.2", "1.2.3-beta.10"), .orderedAscending)
    }

    func testMalformedAndEmpty() {
        XCTAssertEqual(VersionCompare.compare("", "1.0.0"), .orderedAscending)
        XCTAssertEqual(VersionCompare.compare("???", "1.0.0"), .orderedAscending)
        // Non-numeric core collapses to 0 for empty numeric parse edge cases.
        XCTAssertEqual(VersionCompare.compare("1.2.3", "not-a-version"), .orderedDescending)
    }

    func testBuildMetadataIgnored() {
        // SemVer: +build does not affect precedence of the release core.
        XCTAssertEqual(VersionCompare.compare("1.2.3+build.1", "1.2.3"), .orderedSame)
        XCTAssertEqual(VersionCompare.compare("1.2.3+aaa", "1.2.3+bbb"), .orderedSame)
    }

    func testTrailingJunkOnCore() {
        // "1.2.3beta" → numeric 1.2.3 with prerelease beta
        XCTAssertEqual(VersionCompare.compare("1.2.3beta", "1.2.3"), .orderedAscending)
        XCTAssertEqual(VersionCompare.compare("1.2.3", "1.2.3rc1"), .orderedDescending)
    }
}
