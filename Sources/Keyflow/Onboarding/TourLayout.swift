import CoreGraphics

/// Where the spotlight, explanation panel and arrow go for one tour step.
/// Pure geometry in the overlay's own coordinates (origin top-left), so it is
/// unit-tested and recomputed from real frames whenever anything moves.
struct TourLayout: Equatable {
    enum Side: Equatable { case right, below, left, above }

    /// The highlighted area: the target with a little breathing room.
    let spotlight: CGRect
    let popover: CGRect
    let side: Side
    /// A gentle cubic curve from the panel to just outside the spotlight.
    let arrowStart: CGPoint
    let arrowControl1: CGPoint
    let arrowControl2: CGPoint
    let arrowEnd: CGPoint

    static let margin: CGFloat = 16
    /// Between the spotlight and the panel: room for the arrow.
    static let gap: CGFloat = 64
    /// The arrow stops this far outside the spotlight, so it never covers the label.
    static let arrowClearance: CGFloat = 6

    /// Converts a frame in window coordinates (AppKit, origin bottom-left)
    /// to the overlay's coordinates, given the overlay's own window frame.
    static func local(_ frame: CGRect, in overlay: CGRect) -> CGRect {
        CGRect(x: frame.minX - overlay.minX, y: overlay.maxY - frame.maxY, width: frame.width, height: frame.height)
    }

    /// Nil when the target is not on screen or the panel fits on no side of
    /// it: the step then shows its panel centred, with no spotlight or arrow,
    /// rather than pointing somewhere wrong.
    static func make(target: CGRect, popover size: CGSize, bounds: CGRect) -> TourLayout? {
        guard size.width > 0, size.height > 0, target.width > 0, target.height > 0,
              bounds.insetBy(dx: margin, dy: margin).contains(CGPoint(x: target.midX, y: target.midY))
        else { return nil }
        // At least 30 pt tall, so every tab gets the same highlight whatever
        // the height of its symbol.
        var spot = target.insetBy(dx: -6, dy: -4)
        if spot.height < 30 { spot = spot.insetBy(dx: 0, dy: (spot.height - 30) / 2) }
        let usable = bounds.insetBy(dx: margin, dy: margin)

        func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat { min(max(value, low), max(low, high)) }

        // A control in the top strip reads best with its panel directly below.
        let inTopStrip = spot.minY < 96 && spot.minX > bounds.width * 0.15
        for side in inTopStrip ? [Side.below, .right, .left, .above] : [Side.right, .below, .left, .above] {
            let origin: CGPoint
            switch side {
            case .right:
                // The panel sits a little below the row, so the arrow curves gently up into it.
                origin = CGPoint(x: spot.maxX + gap, y: clamp(spot.midY - 22, usable.minY, usable.maxY - size.height))
            case .left:
                origin = CGPoint(x: spot.minX - gap - size.width, y: clamp(spot.midY - 22, usable.minY, usable.maxY - size.height))
            case .below:
                origin = CGPoint(x: clamp(spot.midX - size.width / 2 + 40, usable.minX, usable.maxX - size.width), y: spot.maxY + gap)
            case .above:
                origin = CGPoint(x: clamp(spot.midX - size.width / 2 + 40, usable.minX, usable.maxX - size.width), y: spot.minY - gap - size.height)
            }
            let popover = CGRect(origin: origin, size: size)
            guard usable.contains(popover), !popover.intersects(spot.insetBy(dx: -arrowClearance, dy: -arrowClearance)) else { continue }
            return arrow(side: side, spot: spot, popover: popover)
        }
        return nil
    }

    private static func arrow(side: Side, spot: CGRect, popover: CGRect) -> TourLayout {
        let start: CGPoint
        let end: CGPoint
        // Unit vector out of the target, towards the panel.
        let normal: CGVector
        switch side {
        case .right:
            end = CGPoint(x: spot.maxX + arrowClearance, y: spot.midY)
            start = CGPoint(x: popover.minX - 8, y: min(max(spot.midY + 14, popover.minY + 18), popover.maxY - 18))
            normal = CGVector(dx: 1, dy: 0)
        case .left:
            end = CGPoint(x: spot.minX - arrowClearance, y: spot.midY)
            start = CGPoint(x: popover.maxX + 8, y: min(max(spot.midY + 14, popover.minY + 18), popover.maxY - 18))
            normal = CGVector(dx: -1, dy: 0)
        case .below:
            end = CGPoint(x: spot.midX, y: spot.maxY + arrowClearance)
            start = CGPoint(x: min(max(spot.midX + 24, popover.minX + 24), popover.maxX - 24), y: popover.minY - 8)
            normal = CGVector(dx: 0, dy: 1)
        case .above:
            end = CGPoint(x: spot.midX, y: spot.minY - arrowClearance)
            start = CGPoint(x: min(max(spot.midX + 24, popover.minX + 24), popover.maxX - 24), y: popover.maxY + 8)
            normal = CGVector(dx: 0, dy: -1)
        }
        let reach = hypot(end.x - start.x, end.y - start.y) * 0.45
        return TourLayout(
            spotlight: spot, popover: popover, side: side,
            arrowStart: start,
            arrowControl1: CGPoint(x: start.x - normal.dx * reach, y: start.y - normal.dy * reach),
            arrowControl2: CGPoint(x: end.x + normal.dx * reach, y: end.y + normal.dy * reach),
            arrowEnd: end)
    }
}
