import Foundation

/// Everything known about how the user types, summed over a set of sessions.
/// This is the user's own baseline that weaknesses are measured against.
public struct TypingProfile: Sendable, Equatable {
    public private(set) var sessions = 0
    public private(set) var keys: [Character: KeyStat] = [:]
    public private(set) var bigrams: [String: BigramStat] = [:]
    public private(set) var transitions: [String: BigramStat] = [:]
    public private(set) var words: [String: WordStat] = [:]

    public init() {}

    public init(_ analyses: some Sequence<SessionAnalysis>) {
        for analysis in analyses { add(analysis) }
    }

    public mutating func add(_ analysis: SessionAnalysis) {
        sessions += 1
        for key in analysis.keys {
            keys[key.character, default: KeyStat(character: key.character)].merge(key)
        }
        for pair in analysis.bigrams {
            bigrams[pair.bigram, default: BigramStat(bigram: pair.bigram)].merge(pair)
        }
        for pair in analysis.transitions {
            transitions[pair.bigram, default: BigramStat(bigram: pair.bigram)].merge(pair)
        }
        for word in analysis.words {
            words[word.word, default: WordStat(word: word.word)].attempts += word.attempts
            words[word.word]!.mistakes += word.mistakes
        }
    }

    // MARK: Baselines

    /// Character keystrokes across all sessions.
    public var keystrokes: Int { keys.values.reduce(0) { $0 + $1.attempts } }

    /// Share of keystrokes that were wrong.
    public var keyErrorRate: Double? {
        rate(keys.values.reduce(0) { $0 + $1.errors }, of: keystrokes)
    }

    /// Mean latency of a correct keystroke.
    public var meanKeyLatency: TimeInterval? {
        mean(keys.values.reduce(0) { $0 + $1.latencyTotal }, over: keys.values.reduce(0) { $0 + $1.latencySamples })
    }

    public var bigramErrorRate: Double? { Self.errorRate(of: bigrams) }
    public var meanBigramLatency: TimeInterval? { Self.meanLatency(of: bigrams) }
    public var meanTransitionLatency: TimeInterval? { Self.meanLatency(of: transitions) }

    /// Share of word occurrences with at least one wrong keystroke.
    public var wordMistakeRate: Double? {
        rate(words.values.reduce(0) { $0 + $1.mistakes }, of: words.values.reduce(0) { $0 + $1.attempts })
    }

    // MARK: Private

    private static func errorRate(of pairs: [String: BigramStat]) -> Double? {
        let attempts = pairs.values.reduce(0) { $0 + $1.attempts }
        return attempts > 0 ? Double(pairs.values.reduce(0) { $0 + $1.errors }) / Double(attempts) : nil
    }

    private static func meanLatency(of pairs: [String: BigramStat]) -> TimeInterval? {
        let samples = pairs.values.reduce(0) { $0 + $1.samples }
        return samples > 0 ? pairs.values.reduce(0) { $0 + $1.total } / Double(samples) : nil
    }

    private func rate(_ part: Int, of whole: Int) -> Double? {
        whole > 0 ? Double(part) / Double(whole) : nil
    }

    private func mean(_ total: TimeInterval, over samples: Int) -> TimeInterval? {
        samples > 0 ? total / Double(samples) : nil
    }
}

extension KeyStat {
    mutating func merge(_ other: KeyStat) {
        attempts += other.attempts
        errors += other.errors
        latencySamples += other.latencySamples
        latencyTotal += other.latencyTotal
        latencySquares += other.latencySquares
    }
}

extension BigramStat {
    mutating func merge(_ other: BigramStat) {
        attempts += other.attempts
        errors += other.errors
        samples += other.samples
        total += other.total
        squares += other.squares
    }
}
