import Foundation

/// A point on a monotonic clock, in seconds. The origin is arbitrary; only
/// differences are meaningful. The app feeds `NSEvent.timestamp` /
/// `ProcessInfo.systemUptime` (both system uptime), tests feed plain numbers.
public typealias MonotonicTime = TimeInterval

/// One recorded keystroke that changed the typed buffer.
public struct TypingEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// A character was appended to the typed buffer.
        case insert
        /// A character was removed from the typed buffer.
        case backspace
    }

    public let kind: Kind
    /// Seconds since the session started (the first keystroke is at 0).
    public let time: TimeInterval
    /// Index into the target text that this event applies to.
    public let position: Int
    /// The character the target text has at `position`.
    public let expected: Character
    /// The character that was typed (insert) or removed (backspace).
    public let typed: Character

    /// True only for an insert whose character matches the target.
    public var isCorrect: Bool { kind == .insert && typed == expected }

    public init(kind: Kind, time: TimeInterval, position: Int, expected: Character, typed: Character) {
        self.kind = kind
        self.time = time
        self.position = position
        self.expected = expected
        self.typed = typed
    }
}
