import Foundation

/// Pure layout math for the │–BK keepers zone (preferred-position space).
/// Higher preferred position = further left in the menu bar.
public enum KeepersLayout {
    public static let defaultControl: Double = 250
    public static let slotStride: Double = 28
    public static let edgePad: Double = 14
    public static let minGapFloor: Double = 30

    public struct GapPlan: Equatable {
        public var control: Double
        public var divider: Double
        /// Suggested preferred positions for keepers, left → right (high → low).
        public var slots: [Double]

        public init(control: Double, divider: Double, slots: [Double]) {
            self.control = control
            self.divider = divider
            self.slots = slots
        }

        public var gap: Double { divider - control }
    }

    /// Preferred-position span for the keepers zone given exclusion/keeper count.
    public static func keepersGap(exclusionCount: Int) -> GapPlan {
        let count = max(0, exclusionCount)
        let control = defaultControl
        let needed = edgePad * 2 + Double(max(count, 1)) * slotStride
        let divider = control + max(needed, minGapFloor)
        var slots: [Double] = []
        if count > 0 {
            for i in 0..<count {
                let slot = divider - edgePad - (Double(i) + 0.5) * slotStride
                slots.append(slot)
            }
        }
        return GapPlan(control: control, divider: divider, slots: slots)
    }

    /// Minimum divider − control distance for `exclusionCount` keepers.
    public static func minimumGap(exclusionCount: Int) -> Double {
        14 + Double(max(exclusionCount, 0)) * slotStride
    }

    /// Resolve stored BarKeep preferred positions against the exclusion count.
    /// Preserves a valid control when possible; widens divider when the gap is too small.
    public static func resolveStoredGap(
        storedControl: Double?,
        storedDivider: Double?,
        exclusionCount: Int
    ) -> (control: Double, divider: Double) {
        let plan = keepersGap(exclusionCount: exclusionCount)
        let control: Double
        if let c = storedControl, c > 0, c <= 10_000 {
            control = c
        } else {
            control = plan.control
        }
        let minDivider = control + minimumGap(exclusionCount: exclusionCount)
        let divider: Double
        if let d = storedDivider, d > control + 10, d >= minDivider, d <= 10_000 {
            divider = d
        } else {
            divider = max(minDivider, control + plan.divider - plan.control)
        }
        return (control, divider)
    }

    /// Evenly spaced preferred positions for `count` keepers between control (right)
    /// and divider (left). Empty when count is 0 or the span is non-positive.
    public static func slotPositions(
        controlPosition: Double,
        dividerPosition: Double,
        count: Int
    ) -> [Double] {
        guard count > 0, dividerPosition > controlPosition else { return [] }
        let span = dividerPosition - controlPosition
        return (0..<count).map { index in
            let t = (Double(index) + 1.0) / (Double(count) + 1.0)
            return dividerPosition - t * span
        }
    }
}
