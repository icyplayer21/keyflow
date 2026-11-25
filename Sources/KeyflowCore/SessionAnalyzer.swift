import Foundation

/// How one key (case-insensitive) fared in a session.
public struct KeyStat: Sendable, Equatable {
    public let character: Character
    /// Times this character was the one expected, including retries.
    public var attempts = 0
    /// Attempts where something else was typed.
    public var errors = 0
    public var latencySamples = 0
    var latencyTotal: TimeInterval = 0
    var latencySquares: TimeInterval = 0

    /// Mean time from the previous keystroke to a correct press of this key.
    public var meanLatency: TimeInterval? {
        latencySamples > 0 ? latencyTotal / Double(latencySamples) : nil
    }
    public var errorRate: Double { attempts > 0 ? Double(errors) / Double(attempts) : 0 }
}

/// How one two-character sequence fared. Used both for letter pairs inside a
/// word ("th") and for transitions that involve a space, digit or symbol.
public struct BigramStat: Sendable, Equatable {
    public let bigram: String
    /// Times the second character was attempted right after the first.
    public var attempts = 0
    /// Attempts where the second character was typed wrong.
    public var errors = 0
    /// Latency samples: both characters typed correctly, one straight after the other.
    public var samples = 0
    var total: TimeInterval = 0
    var squares: TimeInterval = 0

    public var meanLatency: TimeInterval { samples > 0 ? total / Double(samples) : 0 }
    public var errorRate: Double { attempts > 0 ? Double(errors) / Double(attempts) : 0 }
}

public struct WordStat: Sendable, Equatable {
    public let word: String
    /// Occurrences the user started typing.
    public var attempts = 0
    /// Occurrences with at least one incorrect keystroke.
    public var mistakes = 0
}

/// Detailed findings for one session. See `SessionAnalyzer` for definitions.
public struct SessionAnalysis: Sendable, Equatable {
    /// 0...1, or `nil` when the session is too short to judge.
    public var consistency: Double?
    public var errorsPerMinute: Double
    /// Raw WPM for each full second of the session.
    public var wpmTimeline: [Double]
    public var meanLatency: TimeInterval?
    public var medianLatency: TimeInterval?
    public var keys: [KeyStat]
    /// Pairs of letters inside a word.
    public var bigrams: [BigramStat]
    /// Pairs where at least one side is a space, digit or symbol.
    public var transitions: [BigramStat]
    /// Every word the user started typing.
    public var words: [WordStat]

    /// Words with at least one mistake, most-mistyped first.
    public var mistypedWords: [WordStat] {
        words.filter { $0.mistakes > 0 }.sorted { ($0.mistakes, $1.word) > ($1.mistakes, $0.word) }
    }

    /// Mean latency across all sampled letter pairs.
    public var meanBigramLatency: TimeInterval? {
        let samples = bigrams.reduce(0) { $0 + $1.samples }
        guard samples > 0 else { return nil }
        return bigrams.reduce(0) { $0 + $1.total } / Double(samples)
    }

    /// Letter pairs slower than the session's pair average, slowest first.
    /// Pairs seen fewer than `minimumSamples` times are ignored.
    public func slowestBigrams(minimumSamples: Int = 2, limit: Int = 5) -> [BigramStat] {
        guard let average = meanBigramLatency else { return [] }
        return bigrams
            .filter { $0.samples >= minimumSamples && $0.meanLatency > average }
            .sorted { ($0.meanLatency, $1.bigram) > ($1.meanLatency, $0.bigram) }
            .prefix(limit).map { $0 }
    }

    /// Keys slower than the session's average keystroke, slowest first.
    public func slowestKeys(minimumSamples: Int = 3, limit: Int = 5) -> [KeyStat] {
        guard let average = meanLatency else { return [] }
        return keys
            .filter { $0.latencySamples >= minimumSamples && ($0.meanLatency ?? 0) > average }
            .sorted { ($0.meanLatency ?? 0, String($1.character)) > ($1.meanLatency ?? 0, String($0.character)) }
            .prefix(limit).map { $0 }
    }

    /// Keys with errors, most errors first.
    public func mostMissedKeys(limit: Int = 5) -> [KeyStat] {
        keys.filter { $0.errors > 0 }
            .sorted { ($0.errors, $0.errorRate, String($1.character)) > ($1.errors, $1.errorRate, String($0.character)) }
            .prefix(limit).map { $0 }
    }
}

/// Turns a session's keystroke log into detailed findings.
///
/// Definitions:
/// - **Latency** is the time between two consecutive character keystrokes.
///   A gap that follows a Backspace, or that exceeds `pauseThreshold`, is a
///   correction or a pause rather than typing rhythm and is not sampled.
/// - **Key latency** samples only correct presses of that key.
/// - **Letter-pair latency** samples two letters of the same word typed
///   correctly, one straight after the other. Pairs involving a space, digit
///   or symbol are tracked separately as **transitions**.
/// - A pair's **attempts** count every time its second character was due
///   right after its first in the text; an **error** is a wrong second character.
/// - **Consistency** is `1 − (standard deviation ÷ mean)` of the number of
///   keystrokes in each full second, floored at 0. Needs at least
///   `minimumConsistencySeconds` full seconds.
/// - A word is **mistyped** when any keystroke inside it was wrong, even if
///   corrected. Each occurrence counts once.
/// - Keys and words are compared case-insensitively.
public enum SessionAnalyzer {
    public static let pauseThreshold: TimeInterval = 2.0
    public static let minimumConsistencySeconds = 3

    public static func analyze(_ session: TypingSession) -> SessionAnalysis {
        var keys: [Character: KeyStat] = [:]
        var bigrams: [String: BigramStat] = [:]
        var transitions: [String: BigramStat] = [:]
        var latencies: [TimeInterval] = []
        var errorPositions = Set<Int>()
        var furthest = -1
        var errors = 0

        var previous: TypingEvent?
        for event in session.events {
            defer { previous = event }
            guard event.kind == .insert else { continue }

            let key = lowercased(event.expected)
            keys[key, default: KeyStat(character: key)].attempts += 1
            furthest = max(furthest, event.position)
            if !event.isCorrect {
                keys[key]!.errors += 1
                errorPositions.insert(event.position)
                errors += 1
            }

            // Accuracy of the pair ending here, judged against the target text.
            var pair: String?
            var isLetterPair = false
            if event.position > 0, event.position <= session.target.count {
                let before = session.target[event.position - 1]
                let name = String([lowercased(before), key])
                pair = name
                isLetterPair = before.isLetter && event.expected.isLetter
                if isLetterPair {
                    bigrams[name, default: BigramStat(bigram: name)].attempts += 1
                    if !event.isCorrect { bigrams[name]!.errors += 1 }
                } else {
                    transitions[name, default: BigramStat(bigram: name)].attempts += 1
                    if !event.isCorrect { transitions[name]!.errors += 1 }
                }
            }

            guard let previous, previous.kind == .insert else { continue }
            let gap = event.time - previous.time
            guard gap >= 0, gap <= pauseThreshold else { continue }
            latencies.append(gap)
            guard event.isCorrect else { continue }

            keys[key]!.latencySamples += 1
            keys[key]!.latencyTotal += gap
            keys[key]!.latencySquares += gap * gap

            if let pair, previous.isCorrect, event.position == previous.position + 1 {
                if isLetterPair {
                    bigrams[pair]!.samples += 1
                    bigrams[pair]!.total += gap
                    bigrams[pair]!.squares += gap * gap
                } else {
                    transitions[pair]!.samples += 1
                    transitions[pair]!.total += gap
                    transitions[pair]!.squares += gap * gap
                }
            }
        }

        let timeline = wpmTimeline(of: session)
        let sorted = latencies.sorted()
        return SessionAnalysis(
            consistency: consistency(ofTimeline: timeline),
            errorsPerMinute: session.elapsed > 0 ? Double(errors) / (session.elapsed / 60) : 0,
            wpmTimeline: timeline,
            meanLatency: sorted.isEmpty ? nil : sorted.reduce(0, +) / Double(sorted.count),
            medianLatency: median(ofSorted: sorted),
            keys: keys.values.sorted { String($0.character) < String($1.character) },
            bigrams: bigrams.values.sorted { $0.bigram < $1.bigram },
            transitions: transitions.values.sorted { $0.bigram < $1.bigram },
            words: words(in: session.target, errorPositions: errorPositions, furthest: furthest)
        )
    }

    public static func consistency(of session: TypingSession) -> Double? {
        consistency(ofTimeline: wpmTimeline(of: session))
    }

    /// Raw WPM in each full second: keystrokes in that second × 60 ÷ 5.
    public static func wpmTimeline(of session: TypingSession) -> [Double] {
        let seconds = Int(session.elapsed.rounded(.down))
        guard seconds > 0 else { return [] }
        var counts = [Int](repeating: 0, count: seconds)
        for event in session.events where event.kind == .insert {
            let bucket = Int(event.time.rounded(.down))
            if bucket >= 0, bucket < seconds { counts[bucket] += 1 }
        }
        return counts.map { Double($0) * 60 / PerformanceCalculator.charactersPerWord }
    }

    // MARK: Private

    private static func consistency(ofTimeline timeline: [Double]) -> Double? {
        guard timeline.count >= minimumConsistencySeconds else { return nil }
        let mean = timeline.reduce(0, +) / Double(timeline.count)
        guard mean > 0 else { return nil }
        let variance = timeline.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(timeline.count)
        return max(0, 1 - variance.squareRoot() / mean)
    }

    private static func median(ofSorted values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
    }

    private static func lowercased(_ character: Character) -> Character {
        let lower = character.lowercased()
        return lower.count == 1 ? lower.first! : character
    }

    private static func words(in target: [Character], errorPositions: Set<Int>, furthest: Int) -> [WordStat] {
        var stats: [String: WordStat] = [:]
        var index = 0
        while index < target.count, index <= furthest {
            guard target[index] != " " else { index += 1; continue }
            var end = index
            while end < target.count, target[end] != " " { end += 1 }

            let word = normalizedWord(target[index..<end])
            if !word.isEmpty {
                stats[word, default: WordStat(word: word)].attempts += 1
                if (index..<end).contains(where: errorPositions.contains) {
                    stats[word]!.mistakes += 1
                }
            }
            index = end
        }
        return stats.values.sorted { $0.word < $1.word }
    }

    /// Lowercased, with surrounding punctuation removed. Empty unless the
    /// token contains a letter.
    private static func normalizedWord(_ slice: ArraySlice<Character>) -> String {
        var characters = slice
        while let first = characters.first, !first.isLetter, !first.isNumber { characters.removeFirst() }
        while let last = characters.last, !last.isLetter, !last.isNumber { characters.removeLast() }
        guard characters.contains(where: \.isLetter) else { return "" }
        return String(characters).lowercased()
    }
}
