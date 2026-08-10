import XCTest
@testable import BarKeepCore

final class ExclusionListTests: XCTestCase {
    func testUniqueDedupesByBundleID() {
        let a = ExclusionEntry.make(name: "Dropbox", bundleIdentifier: "com.dropbox.Dropbox")
        let b = ExclusionEntry.make(name: "Dropbox Helper", bundleIdentifier: "com.dropbox.Dropbox")
        let c = ExclusionEntry.make(name: "Quitter", bundleIdentifier: "com.marcoarment.quitter")
        let out = ExclusionList.unique([a, b, c, a])
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.map(\.name), ["Dropbox", "Quitter"])
        XCTAssertEqual(Set(out.compactMap(\.bundleIdentifier)).count, 2)
    }

    func testUniqueDedupesByNameIdWhenNoBundle() {
        let a = ExclusionEntry.make(name: "Foo", bundleIdentifier: nil)
        let b = ExclusionEntry.make(name: "Foo", bundleIdentifier: nil)
        let c = ExclusionEntry.make(name: "Bar", bundleIdentifier: nil)
        let out = ExclusionList.unique([a, b, c])
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.map(\.name).sorted(), ["Bar", "Foo"])
    }

    func testUniqueSortsByName() {
        let list = [
            ExclusionEntry.make(name: "Zebra", bundleIdentifier: "z"),
            ExclusionEntry.make(name: "apple", bundleIdentifier: "a"),
            ExclusionEntry.make(name: "Mango", bundleIdentifier: "m"),
        ]
        let out = ExclusionList.unique(list)
        XCTAssertEqual(out.map(\.name), ["apple", "Mango", "Zebra"])
    }

    func testContainsMatchesBundleOrName() {
        let list = [
            ExclusionEntry.make(name: "Quitter", bundleIdentifier: "com.marcoarment.quitter"),
            ExclusionEntry.make(name: "Nameless", bundleIdentifier: nil),
        ]
        XCTAssertTrue(ExclusionList.contains(list, name: "Other", bundleIdentifier: "com.marcoarment.quitter"))
        XCTAssertTrue(ExclusionList.contains(list, name: "quitter", bundleIdentifier: nil))
        XCTAssertTrue(ExclusionList.contains(list, name: "Nameless", bundleIdentifier: nil))
        XCTAssertFalse(ExclusionList.contains(list, name: "Nope", bundleIdentifier: "com.example"))
    }

    func testClampAutoHideSeconds() {
        XCTAssertEqual(ExclusionList.clampAutoHideSeconds(0), 10)
        XCTAssertEqual(ExclusionList.clampAutoHideSeconds(-5), 1)
        XCTAssertEqual(ExclusionList.clampAutoHideSeconds(15), 15)
        XCTAssertEqual(ExclusionList.clampAutoHideSeconds(9999), 600)
        XCTAssertEqual(ExclusionList.clampAutoHideSeconds(1), 1)
    }
}
