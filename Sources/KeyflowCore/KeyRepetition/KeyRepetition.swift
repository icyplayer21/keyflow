import Foundation

/// Key Repetition: press one letter a set number of times, to make finding
/// that key familiar.
///
/// What counts, and why:
/// - **One count per physical press.** Auto-repeat from a held key is never
///   counted (macOS flags it), so holding a key cannot complete a session;
///   each repetition needs a fresh key-down.
/// - **Upper case counts as the same letter.** The goal is the key's
///   location, and Shift or Caps Lock change the case, not the key. So with
///   P as the target, "p" and "P" are both correct.
/// - **The letter is what the active keyboard layout typed**, as everywhere
///   else in Keyflow. On US QWERTY that is the key the finger guidance shows.
/// - **Space is ignored**, so a habit of spacing between letters neither
///   helps nor hurts. Any other typed character is a counted mistake.
///   Modifier keys alone and keys that type nothing are not attempts.
/// - **Accuracy** = correct presses ÷ counted attempts (correct + incorrect).
/// - **Time** runs from the first counted attempt to the press that reaches
///   the goal, leaving out time spent paused.
public struct KeyRepetitionCounter: Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case ready, running, paused, finished }
    public enum Outcome: Sendable, Equatable { case correct, incorrect, ignored }

    public static let presets = [25, 50, 100, 200]
    public static let defaultGoal = 50
    /// Custom goals are kept within this range.
    public static let goalRange = 5...500
    public static let letters: [Character] = Array("abcdefghijklmnopqrstuvwxyz")

    /// Always a lower-case letter a–z.
    public let letter: Character
    public let goal: Int
    public private(set) var correct = 0
    public private(set) var incorrect = 0
    public private(set) var phase: Phase = .ready
    /// The first counted attempt.
    public private(set) var startTime: MonotonicTime?
    public private(set) var endTime: MonotonicTime?
    private var pausedTotal: TimeInterval = 0
    private var pausedAt: MonotonicTime?
    /// What the phase was before pausing.
    private var phaseBeforePause: Phase = .ready

    /// Nil unless `letter` is a–z (either case).
    public init?(letter: Character, goal: Int) {
        guard let normalized = Self.normalize(letter) else { return nil }
        self.letter = normalized
        self.goal = Self.clampGoal(goal)
    }

    public static func normalize(_ letter: Character) -> Character? {
        guard let lower = letter.lowercased().first, letters.contains(lower), letter.lowercased().count == 1 else { return nil }
        return lower
    }

    public static func clampGoal(_ goal: Int) -> Int { min(goalRange.upperBound, max(goalRange.lowerBound, goal)) }

    public var attempts: Int { correct + incorrect }
    public var remaining: Int { max(0, goal - correct) }
    /// Nil before the first counted attempt.
    public var accuracy: Double? { attempts == 0 ? nil : Double(correct) / Double(attempts) }
    public var isFinished: Bool { phase == .finished }

    /// One key-down. `isRepeat` is macOS's auto-repeat flag.
    @discardableResult
    public mutating func press(_ character: Character, isRepeat: Bool, at time: MonotonicTime) -> Outcome {
        guard phase == .ready || phase == .running, !isRepeat, character != " " else { return .ignored }
        if phase == .ready {
            phase = .running
            startTime = time
        }
        guard Self.normalize(character) == letter else {
            incorrect += 1
            return .incorrect
        }
        correct += 1
        if correct >= goal {
            phase = .finished
            endTime = time
        }
        return .correct
    }

    /// Stops counting. Presses while paused are ignored.
    public mutating func pause(at time: MonotonicTime) {
        guard phase == .ready || phase == .running else { return }
        phaseBeforePause = phase
        phase = .paused
        pausedAt = time
    }

    public mutating func resume(at time: MonotonicTime) {
        guard phase == .paused else { return }
        // Time paused before the first attempt is not part of the session anyway.
        if let pausedAt, startTime != nil { pausedTotal += max(0, time - pausedAt) }
        pausedAt = nil
        phase = phaseBeforePause
    }

    /// Seconds of active practice: first counted attempt to now (or the
    /// finishing press), without paused time.
    public func duration(at time: MonotonicTime) -> TimeInterval {
        guard let startTime else { return 0 }
        let end = endTime ?? pausedAt ?? time
        return max(0, end - startTime - pausedTotal)
    }

    public func result(mode: KeyRepetitionMode, at time: MonotonicTime) -> KeyRepetitionResult {
        KeyRepetitionResult(letter: String(letter), goal: goal, correct: correct, incorrect: incorrect,
                            mode: mode, duration: duration(at: time))
    }
}

/// Continuous: the letter again and again. Return to Home: after each press,
/// a reminder to bring the fingers back to the home row first. Keyflow
/// cannot see hands, so that is an instruction, never a measurement.
public enum KeyRepetitionMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case continuous, returnToHome

    public var id: Self { self }
    public var title: String { self == .continuous ? "Continuous" : "Return to Home" }
}

/// A finished session, as saved.
public struct KeyRepetitionResult: Codable, Sendable, Equatable {
    /// Lower-case letter.
    public let letter: String
    public let goal: Int
    public let correct: Int
    public let incorrect: Int
    public let mode: KeyRepetitionMode
    /// Seconds, without pauses.
    public let duration: TimeInterval

    public init(letter: String, goal: Int, correct: Int, incorrect: Int, mode: KeyRepetitionMode, duration: TimeInterval) {
        self.letter = letter
        self.goal = goal
        self.correct = correct
        self.incorrect = incorrect
        self.mode = mode
        self.duration = duration
    }

    public var attempts: Int { correct + incorrect }
    /// Correct ÷ counted attempts.
    public var accuracy: Double { attempts == 0 ? 0 : Double(correct) / Double(attempts) }
}

/// A saved Key Repetition session; `date` is when it was completed.
public struct KeyRepetitionEvent: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    public let result: KeyRepetitionResult

    public init(id: UUID = UUID(), date: Date = .now, result: KeyRepetitionResult) {
        self.id = id
        self.date = date
        self.result = result
    }
}

/// Per-key totals over completed sessions. No invented score: just counts.
public struct KeyRepetitionHistory: Sendable {
    public struct KeyStats: Sendable, Equatable, Identifiable {
        public let letter: Character
        public let sessions: Int
        /// Correct presses over all sessions.
        public let repetitions: Int
        public let mistakes: Int
        public let lastPractised: Date
        public let lastAccuracy: Double
        public var id: Character { letter }
        /// Correct ÷ counted attempts, over all sessions.
        public var accuracy: Double { repetitions + mistakes == 0 ? 0 : Double(repetitions) / Double(repetitions + mistakes) }
    }

    /// Keys practised at least once, most recently practised first.
    public let keys: [KeyStats]

    public init(events: [KeyRepetitionEvent]) {
        var grouped: [Character: [KeyRepetitionEvent]] = [:]
        for event in events {
            guard let letter = event.result.letter.first else { continue }
            grouped[letter, default: []].append(event)
        }
        keys = grouped.map { letter, events in
            let sorted = events.sorted { $0.date < $1.date }
            return KeyStats(letter: letter, sessions: sorted.count,
                            repetitions: sorted.reduce(0) { $0 + $1.result.correct },
                            mistakes: sorted.reduce(0) { $0 + $1.result.incorrect },
                            lastPractised: sorted.last!.date, lastAccuracy: sorted.last!.result.accuracy)
        }
        .sorted { ($0.lastPractised, $1.letter) > ($1.lastPractised, $0.letter) }
    }

    public func stats(for letter: Character) -> KeyStats? { keys.first { $0.letter == letter } }
}
