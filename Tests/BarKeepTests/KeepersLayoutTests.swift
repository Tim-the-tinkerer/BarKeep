import XCTest
@testable import BarKeepCore

final class KeepersLayoutTests: XCTestCase {
    func testKeepersGapGrowsWithCount() {
        let zero = KeepersLayout.keepersGap(exclusionCount: 0)
        let three = KeepersLayout.keepersGap(exclusionCount: 3)
        XCTAssertGreaterThan(three.gap, zero.gap)
        XCTAssertEqual(zero.slots.count, 0)
        XCTAssertEqual(three.slots.count, 3)
        // Slots sit strictly between control and divider.
        for slot in three.slots {
            XCTAssertGreaterThan(slot, three.control)
            XCTAssertLessThan(slot, three.divider)
        }
    }

    func testMinimumGap() {
        XCTAssertEqual(KeepersLayout.minimumGap(exclusionCount: 0), 14)
        XCTAssertEqual(KeepersLayout.minimumGap(exclusionCount: 2), 14 + 56)
    }

    func testResolveStoredGapPreservesValidControl() {
        let resolved = KeepersLayout.resolveStoredGap(
            storedControl: 687,
            storedDivider: 702,
            exclusionCount: 0
        )
        XCTAssertEqual(resolved.control, 687)
        XCTAssertGreaterThan(resolved.divider, resolved.control)
    }

    func testResolveStoredGapWidensWhenTooTightForKeepers() {
        let resolved = KeepersLayout.resolveStoredGap(
            storedControl: 250,
            storedDivider: 255, // far too small for 3 keepers
            exclusionCount: 3
        )
        XCTAssertEqual(resolved.control, 250)
        XCTAssertGreaterThanOrEqual(resolved.divider - resolved.control, KeepersLayout.minimumGap(exclusionCount: 3))
    }

    func testResolveStoredGapDefaultsWhenMissing() {
        let resolved = KeepersLayout.resolveStoredGap(
            storedControl: nil,
            storedDivider: nil,
            exclusionCount: 1
        )
        let plan = KeepersLayout.keepersGap(exclusionCount: 1)
        XCTAssertEqual(resolved.control, plan.control)
        XCTAssertEqual(resolved.divider, plan.divider)
    }

    func testSlotPositionsEvenSpacing() {
        let slots = KeepersLayout.slotPositions(controlPosition: 100, dividerPosition: 400, count: 2)
        XCTAssertEqual(slots.count, 2)
        // t = 1/3 and 2/3 from divider toward control
        XCTAssertEqual(slots[0], 400 - (1.0 / 3.0) * 300, accuracy: 0.001)
        XCTAssertEqual(slots[1], 400 - (2.0 / 3.0) * 300, accuracy: 0.001)
    }

    func testSlotPositionsEmptyWhenInvalid() {
        XCTAssertTrue(KeepersLayout.slotPositions(controlPosition: 100, dividerPosition: 100, count: 2).isEmpty)
        XCTAssertTrue(KeepersLayout.slotPositions(controlPosition: 200, dividerPosition: 100, count: 2).isEmpty)
        XCTAssertTrue(KeepersLayout.slotPositions(controlPosition: 100, dividerPosition: 400, count: 0).isEmpty)
    }
}
