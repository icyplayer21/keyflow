import Foundation

/// What kind of movement led into a keystroke. Latencies are only ever
/// compared within one kind: a repeated key is naturally faster than a
/// same-finger reach, so comparing raw speeds across fingers would mostly
/// measure which keys they happen to own.
public enum TransitionKind: String, CaseIterable, Sendable, Codable {
    /// The same key twice ("ll").
    case repeatKey
    /// Two different keys on one finger ("ed").
    case sameFinger
    /// Two fingers of the same hand ("as").
    case sameHand
    /// One key on each hand ("al").
    case alternateHand
    /// Into or out of the Space bar.
    case space
}

/// Running sums of latency samples: enough for a mean and a variance.
public struct LatencySums: Sendable, Equatable, Codable {
    public var count = 0
    public var sum: TimeInterval = 0
    public var squares: TimeInterval = 0

    public init(count: Int = 0, sum: TimeInterval = 0, squares: TimeInterval = 0) {
        self.count = count
        self.sum = sum
        self.squares = squares
    }

    public mutating func add(_ value: TimeInterval) {
        count += 1
        sum += value
        squares += value * value
    }

    public var mean: TimeInterval? { count > 0 ? sum / Double(count) : nil }

    /// Sample variance, or `nil` with fewer than two samples.
    public var variance: Double? {
        guard count > 1 else { return nil }
        return max(0, (squares - sum * sum / Double(count)) / Double(count - 1))
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        LatencySums(count: lhs.count + rhs.count, sum: lhs.sum + rhs.sum, squares: lhs.squares + rhs.squares)
    }
}

/// A transition into one of a finger's keys, as typed.
public struct TransitionTiming: Sendable, Equatable {
    public let kind: TransitionKind
    public var latency = LatencySums()
}

/// Everything observed for one finger, from the keys standard touch typing
/// assigns to it. Keyflow sees which key was expected and which was pressed;
/// it never sees which finger actually moved.
///
/// Accounting, so nothing is counted twice:
/// - Every character keystroke where one of this finger's keys was expected
///   is one **press**: either **successful** or **incorrect**.
/// - A text position that received at least one incorrect press is one
///   **mistyped position**. It is **corrected** if the final text is right
///   there (or the character was deleted), **uncorrected** if it is still
///   wrong. Two wrong presses at one position are two incorrect presses but
///   one mistyped position.
/// - Accuracy is successful ÷ presses, the same definition Keyflow uses
///   everywhere: a mistake fixed with Backspace still counted as a mistake
///   when it was made, and is not counted again when fixed.
public struct FingerObservation: Sendable, Equatable {
    public var presses = 0
    public var successful = 0
    public var incorrect = 0
    public var correctedErrors = 0
    public var uncorrectedErrors = 0
    /// Per key (unshifted base key).
    public var keys: [Character: ErrorCount] = [:]
    /// Latency into this finger's keys, by transition kind.
    public var timing: [TransitionKind: LatencySums] = [:]
    /// Latency per transition, "ed" meaning e then d.
    public var transitions: [String: TransitionTiming] = [:]

    public init() {}

    public var timingSamples: Int { timing.values.reduce(0) { $0 + $1.count } }
    public var errorRate: Double? { presses > 0 ? Double(incorrect) / Double(presses) : nil }

    public mutating func merge(_ other: FingerObservation) {
        presses += other.presses
        successful += other.successful
        incorrect += other.incorrect
        correctedErrors += other.correctedErrors
        uncorrectedErrors += other.uncorrectedErrors
        keys.merge(other.keys) { $0 + $1 }
        timing.merge(other.timing) { $0 + $1 }
        for (name, transition) in other.transitions {
            if var existing = transitions[name] {
                existing.latency = existing.latency + transition.latency
                transitions[name] = existing
            } else {
                transitions[name] = transition
            }
        }
    }
}

/// Observations for every finger, from one or more sessions.
public struct FingerObservations: Sendable, Equatable {
    public var fingers: [Finger: FingerObservation] = [:]
    public var sessions = 0

    public init() {}

    public subscript(finger: Finger) -> FingerObservation { fingers[finger] ?? FingerObservation() }

    public mutating func merge(_ other: FingerObservations) {
        sessions += other.sessions
        fingers.merge(other.fingers) { a, b in
            var merged = a
            merged.merge(b)
            return merged
        }
    }

    /// Latency over all fingers, by transition kind.
    public var timingByKind: [TransitionKind: LatencySums] {
        fingers.values.reduce(into: [:]) { totals, observation in totals.merge(observation.timing) { $0 + $1 } }
    }
}

/// Turns keystroke logs into per-finger observations.
///
/// Timing rules, shared with `SessionAnalyzer`:
/// - A latency sample is the gap between two **correct** presses at
///   consecutive positions, the second of which is credited to its finger.
/// - Gaps after a Backspace or longer than `SessionAnalyzer.pauseThreshold`
///   are corrections or pauses, not rhythm, and are not sampled.
/// - Presses that need Shift (capitals, shifted symbols) are left out of
///   timing because the extra key makes them incomparable.
public enum FingerAnalyzer {
    public static func observe(_ session: TypingSession) -> FingerObservations {
        var result = FingerObservations()
        result.sessions = 1
        var mistyped: [Int: Finger] = [:]

        var previous: TypingEvent?
        for event in session.events {
            defer { previous = event }
            guard event.kind == .insert, let finger = FingerMap.finger(for: event.expected) else { continue }
            let base = KeyboardLayout.baseKey(for: event.expected) ?? event.expected

            var observation = result.fingers[finger] ?? FingerObservation()
            observation.presses += 1
            if event.isCorrect {
                observation.successful += 1
                observation.keys[base, default: ErrorCount()].attempts += 1
            } else {
                observation.incorrect += 1
                observation.keys[base, default: ErrorCount()] = observation.keys[base, default: ErrorCount()]
                    + ErrorCount(attempts: 1, errors: 1)
                if mistyped[event.position] == nil { mistyped[event.position] = finger }
            }

            if let previous, previous.kind == .insert, previous.isCorrect, event.isCorrect,
               event.position == previous.position + 1,
               let previousFinger = FingerMap.finger(for: previous.expected),
               !needsShift(previous.expected), !needsShift(event.expected) {
                let gap = event.time - previous.time
                if gap > 0, gap <= SessionAnalyzer.pauseThreshold {
                    let previousBase = KeyboardLayout.baseKey(for: previous.expected) ?? previous.expected
                    let kind = kind(from: (previousBase, previousFinger), to: (base, finger))
                    observation.timing[kind, default: LatencySums()].add(gap)
                    let name = String([previousBase, base])
                    observation.transitions[name, default: TransitionTiming(kind: kind)].latency.add(gap)
                }
            }
            result.fingers[finger] = observation
        }

        for (position, finger) in mistyped {
            let fixed = position >= session.typed.count
                || (position < session.target.count && session.typed[position] == session.target[position])
            if fixed {
                result.fingers[finger]!.correctedErrors += 1
            } else {
                result.fingers[finger]!.uncorrectedErrors += 1
            }
        }
        return result
    }

    public static func observe(_ sessions: some Sequence<TypingSession>) -> FingerObservations {
        sessions.reduce(into: FingerObservations()) { $0.merge(observe($1)) }
    }

    public static func kind(from previous: (key: Character, finger: Finger), to current: (key: Character, finger: Finger)) -> TransitionKind {
        if previous.key == current.key { return .repeatKey }
        if previous.finger == .thumb || current.finger == .thumb { return .space }
        if previous.finger == current.finger { return .sameFinger }
        return previous.finger.hand == current.finger.hand ? .sameHand : .alternateHand
    }

    /// True for characters typed with Shift held: capitals and shifted symbols.
    public static func needsShift(_ character: Character) -> Bool {
        guard let base = KeyboardLayout.baseKey(for: character) else { return false }
        return base != character
    }
}
