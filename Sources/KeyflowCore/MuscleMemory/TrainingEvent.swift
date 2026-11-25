import Foundation

public struct ErrorCount: Codable, Sendable, Equatable {
    public var attempts: Int
    public var errors: Int

    public init(attempts: Int = 0, errors: Int = 0) {
        self.attempts = attempts
        self.errors = errors
    }

    public var rate: Double { attempts > 0 ? Double(errors) / Double(attempts) : 0 }

    public static func + (lhs: Self, rhs: Self) -> Self {
        ErrorCount(attempts: lhs.attempts + rhs.attempts, errors: lhs.errors + rhs.errors)
    }
}

/// The outcome of one completed Muscle Memory round.
public struct RoundResult: Codable, Sendable, Equatable {
    public var text: String
    /// Correct keystrokes ÷ all character keystrokes, as everywhere in Keyflow.
    public var accuracy: Double
    public var keystrokes: Int
    public var correctKeystrokes: Int
    public var backspaces: Int
    public var duration: TimeInterval
    /// Per key, lower-cased. Space is left out.
    public var keys: [String: ErrorCount]
    /// Per two-key transition ("dk", "j;"). Pairs involving a space are left out.
    public var pairs: [String: ErrorCount]

    public init(text: String, accuracy: Double, keystrokes: Int, correctKeystrokes: Int, backspaces: Int,
                duration: TimeInterval, keys: [String: ErrorCount] = [:], pairs: [String: ErrorCount] = [:]) {
        self.text = text
        self.accuracy = accuracy
        self.keystrokes = keystrokes
        self.correctKeystrokes = correctKeystrokes
        self.backspaces = backspaces
        self.duration = duration
        self.keys = keys
        self.pairs = pairs
    }

    public init(session: TypingSession) {
        let metrics = PerformanceCalculator.metrics(for: session)
        let analysis = SessionAnalyzer.analyze(session)

        var keys: [String: ErrorCount] = [:]
        for key in analysis.keys where key.character != " " {
            keys[String(key.character), default: ErrorCount()] = keys[String(key.character), default: ErrorCount()]
                + ErrorCount(attempts: key.attempts, errors: key.errors)
        }
        var pairs: [String: ErrorCount] = [:]
        for pair in analysis.bigrams + analysis.transitions where !pair.bigram.contains(" ") {
            pairs[pair.bigram, default: ErrorCount()] = pairs[pair.bigram, default: ErrorCount()]
                + ErrorCount(attempts: pair.attempts, errors: pair.errors)
        }

        self.init(text: String(session.target), accuracy: metrics.accuracy, keystrokes: metrics.totalKeystrokes,
                  correctKeystrokes: metrics.correctKeystrokes, backspaces: metrics.backspaces,
                  duration: metrics.elapsed, keys: keys, pairs: pairs)
    }

    /// Counts toward mastery.
    public var isQualifying: Bool { keystrokes > 0 && accuracy >= MasteryTracker.requiredAccuracy }
}

/// Something that happened in Muscle Memory training: a completed round, or
/// a stage the user chose to skip.
public struct TrainingEvent: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case round(RoundResult)
        case skip
    }

    public let id: UUID
    public let date: Date
    public let category: TrainingCategory
    public let stage: TrainingStage
    public let kind: Kind

    public init(id: UUID = UUID(), date: Date = .now, category: TrainingCategory, stage: TrainingStage, kind: Kind) {
        self.id = id
        self.date = date
        self.category = category
        self.stage = stage
        self.kind = kind
    }

    public var round: RoundResult? {
        if case .round(let result) = kind { return result }
        return nil
    }
}
