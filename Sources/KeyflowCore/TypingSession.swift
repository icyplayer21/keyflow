import Foundation

/// An immutable snapshot of a typing session: what was asked, what was typed,
/// and the full keystroke log. This is the unit that metrics are computed from
/// (and, from Phase 2, the unit that gets persisted).
public struct TypingSession: Sendable, Equatable {
    /// The text the user was asked to type.
    public var target: [Character]
    /// The typed buffer as it stood at the moment of the snapshot.
    public var typed: [Character]
    /// Every insert and backspace, in order.
    public var events: [TypingEvent]
    /// Seconds from the first keystroke to the snapshot (or to the end, if finished).
    public var elapsed: TimeInterval
    /// The time limit the session ran under, if any.
    public var timeLimit: TimeInterval?
    /// Whether the session has ended.
    public var isFinished: Bool

    public init(
        target: [Character],
        typed: [Character],
        events: [TypingEvent],
        elapsed: TimeInterval,
        timeLimit: TimeInterval? = nil,
        isFinished: Bool = true
    ) {
        self.target = target
        self.typed = typed
        self.events = events
        self.elapsed = elapsed
        self.timeLimit = timeLimit
        self.isFinished = isFinished
    }
}
