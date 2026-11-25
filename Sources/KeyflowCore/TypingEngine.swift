import Foundation

/// The typing state machine. A pure value type: every input carries its own
/// monotonic timestamp, so behaviour is fully deterministic and testable.
///
/// Lifecycle: `idle` → `running` (first inserted character) → `finished`
/// (time limit reached, or the end of the text when `finishesAtEndOfText`).
///
/// Backspace rules:
/// - Backspace removes the last typed character and is logged as an event.
/// - It never starts a session and does nothing on an empty buffer.
/// - It does not erase history: a mistake that was corrected still counts as
///   an incorrect keystroke for accuracy.
public struct TypingEngine: Sendable {
    public enum Phase: Sendable, Equatable {
        case idle, running, finished
    }

    public struct Configuration: Sendable, Equatable {
        /// Session length in seconds. `nil` means untimed.
        public var timeLimit: TimeInterval?
        /// Finish as soon as the typed buffer reaches the end of the target.
        public var finishesAtEndOfText: Bool

        public init(timeLimit: TimeInterval? = nil, finishesAtEndOfText: Bool = true) {
            self.timeLimit = timeLimit
            self.finishesAtEndOfText = finishesAtEndOfText
        }
    }

    public let configuration: Configuration
    public private(set) var target: [Character]
    public private(set) var typed: [Character] = []
    public private(set) var events: [TypingEvent] = []
    public private(set) var phase: Phase = .idle
    public private(set) var startTime: MonotonicTime?
    public private(set) var endTime: MonotonicTime?
    /// True when the session ended because the clock ran out.
    public private(set) var endedByTimeLimit = false

    public init(target: String, configuration: Configuration = Configuration()) {
        self.target = Array(target)
        self.configuration = configuration
    }

    /// Index of the next character to type.
    public var position: Int { typed.count }

    // MARK: Input

    /// Types one character. Returns whether it was accepted into the buffer.
    @discardableResult
    public mutating func insert(_ character: Character, at time: MonotonicTime) -> Bool {
        guard phase != .finished, position < target.count else { return false }
        if phase == .idle {
            phase = .running
            startTime = time
        }
        guard !expireIfNeeded(at: time) else { return false }

        events.append(TypingEvent(
            kind: .insert,
            time: relative(time),
            position: position,
            expected: target[position],
            typed: character
        ))
        typed.append(character)

        if configuration.finishesAtEndOfText, position == target.count {
            finish(at: time)
        }
        return true
    }

    /// Removes the last typed character. Returns whether anything was removed.
    @discardableResult
    public mutating func backspace(at time: MonotonicTime) -> Bool {
        guard phase == .running, !expireIfNeeded(at: time), let removed = typed.popLast() else {
            return false
        }
        events.append(TypingEvent(
            kind: .backspace,
            time: relative(time),
            position: position,
            expected: target[position],
            typed: removed
        ))
        return true
    }

    /// Removes back to the start of the current word (Option-Delete).
    /// Logged as one backspace event per removed character.
    /// Returns the number of characters removed.
    @discardableResult
    public mutating func deleteWord(at time: MonotonicTime) -> Int {
        var removed = 0
        while typed.last == " ", backspace(at: time) { removed += 1 }
        while let last = typed.last, last != " ", backspace(at: time) { removed += 1 }
        return removed
    }

    /// Advances the clock without input. Ends the session once the limit is reached.
    public mutating func tick(at time: MonotonicTime) {
        guard phase == .running else { return }
        expireIfNeeded(at: time)
    }

    /// Extends the target text (used to keep timed sessions supplied with words).
    public mutating func appendTarget(_ text: String) {
        guard phase != .finished else { return }
        target.append(contentsOf: text)
    }

    // MARK: Time

    /// Seconds since the first keystroke, clamped to the session's bounds.
    public func elapsed(at time: MonotonicTime) -> TimeInterval {
        guard let startTime else { return 0 }
        // Exactly the limit, not `(start + limit) - start`, which can be off by a rounding error.
        if endedByTimeLimit, let limit = configuration.timeLimit { return limit }
        let end = endTime ?? time
        let value = max(0, end - startTime)
        if let limit = configuration.timeLimit { return min(value, limit) }
        return value
    }

    /// Seconds left on the clock, or `nil` for untimed sessions.
    public func remaining(at time: MonotonicTime) -> TimeInterval? {
        guard let limit = configuration.timeLimit else { return nil }
        return max(0, limit - elapsed(at: time))
    }

    /// A snapshot suitable for metric calculation.
    public func session(at time: MonotonicTime) -> TypingSession {
        TypingSession(
            target: target,
            typed: typed,
            events: events,
            elapsed: elapsed(at: time),
            timeLimit: configuration.timeLimit,
            isFinished: phase == .finished
        )
    }

    // MARK: Private

    private func relative(_ time: MonotonicTime) -> TimeInterval {
        max(0, time - (startTime ?? time))
    }

    /// Finishes the session if `time` is at or past the limit. The session ends
    /// exactly at the limit, so input arriving late is never counted.
    @discardableResult
    private mutating func expireIfNeeded(at time: MonotonicTime) -> Bool {
        guard phase == .running, let startTime, let limit = configuration.timeLimit,
              time - startTime >= limit else { return false }
        endedByTimeLimit = true
        finish(at: startTime + limit)
        return true
    }

    private mutating func finish(at time: MonotonicTime) {
        phase = .finished
        endTime = time
    }
}
