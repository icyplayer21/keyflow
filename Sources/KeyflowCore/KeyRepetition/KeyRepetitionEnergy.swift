import Foundation

/// How full the Key Repetition letter looks, from 0 (starting size) to 1.
///
/// This is display only. It never changes the count, the accuracy or anything
/// saved, and it is not a score. Correct presses earn size; when the gap since
/// the last correct press runs past the user's own rhythm, the size drains.
public struct KeyRepetitionEnergy: Equatable, Sendable {
    /// No shrinking until this many correct presses, so the user can settle in.
    public static let settlingPresses = 3
    /// The wait before shrinking is twice the usual gap, within these limits.
    public static let minimumGrace: TimeInterval = 0.6
    public static let maximumGrace: TimeInterval = 2
    /// Seconds from the end of the wait to fully drained.
    public static let fadeSeconds: TimeInterval = 3
    /// Share of the lost size each correct press wins back.
    public static let recovery = 0.4
    private static let gapMemory = 7

    private var earned = 0.0
    private var base = 0.0
    private var lastPress: MonotonicTime?
    private var gaps: [TimeInterval] = []
    private var presses = 0
    private var pausedAt: MonotonicTime?

    public init() {}

    /// Seconds allowed between presses, or nil while settling in.
    public var graceSeconds: TimeInterval? {
        guard presses >= Self.settlingPresses, !gaps.isEmpty else { return nil }
        let sorted = gaps.sorted()
        let middle = sorted.count / 2
        let median = sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
        return min(Self.maximumGrace, max(Self.minimumGrace, median * 2))
    }

    /// The size at a moment. Gentle at first, faster the longer the wait.
    public func level(at time: MonotonicTime) -> Double {
        guard let lastPress, let grace = graceSeconds else { return base }
        let over = (pausedAt ?? time) - lastPress - grace
        guard over > 0 else { return base }
        let u = min(1, over / Self.fadeSeconds)
        return base * (1 - u * u)
    }

    /// A correct press. `earned` is correct presses ÷ goal, after this press.
    /// Wrong keys are not reported here, so they restore nothing.
    public mutating func press(earned newEarned: Double, at time: MonotonicTime) {
        let lost = max(0, earned - level(at: time))
        if let lastPress {
            gaps.append(max(0, time - lastPress))
            if gaps.count > Self.gapMemory { gaps.removeFirst(gaps.count - Self.gapMemory) }
        }
        earned = min(1, max(0, newEarned))
        base = max(0, earned - lost * (1 - Self.recovery))
        lastPress = time
        presses += 1
    }

    /// Freezes the size until `resume`.
    public mutating func pause(at time: MonotonicTime) {
        if pausedAt == nil { pausedAt = time }
    }

    public mutating func resume(at time: MonotonicTime) {
        guard let pausedAt else { return }
        if let lastPress { self.lastPress = lastPress + max(0, time - pausedAt) }
        self.pausedAt = nil
    }
}
