import Foundation

/// Headline numbers for a session. See `PerformanceCalculator` for definitions.
public struct PerformanceMetrics: Sendable, Equatable {
    /// Correct characters left in the final buffer ÷ 5, per minute.
    public var netWPM: Double
    /// Every character keystroke (right or wrong, even if later deleted) ÷ 5, per minute.
    public var rawWPM: Double
    /// Correct character keystrokes ÷ all character keystrokes, 0...1.
    /// Corrected mistakes still count against accuracy. 1 when nothing was typed.
    public var accuracy: Double
    public var elapsed: TimeInterval

    /// Character keystrokes (inserts). Backspaces are not counted here.
    public var totalKeystrokes: Int
    public var correctKeystrokes: Int
    public var incorrectKeystrokes: Int
    public var backspaces: Int

    /// Characters in the final buffer that match the target.
    public var correctCharacters: Int
    /// Characters in the final buffer that do not match (uncorrected errors).
    public var incorrectCharacters: Int
}

/// Metric definitions, in one place.
///
/// - A "word" is 5 characters, spaces and punctuation included.
/// - Time runs from the first keystroke to the end of the session.
/// - Backspace is never a keystroke for WPM or accuracy purposes; it only
///   changes the final buffer (and therefore net WPM).
public enum PerformanceCalculator {
    public static let charactersPerWord = 5.0

    public static func wpm(characters: Int, elapsed: TimeInterval) -> Double {
        guard elapsed > 0, characters > 0 else { return 0 }
        return Double(characters) / charactersPerWord / (elapsed / 60)
    }

    public static func metrics(for session: TypingSession) -> PerformanceMetrics {
        var total = 0, correct = 0, backspaces = 0
        for event in session.events {
            switch event.kind {
            case .insert:
                total += 1
                if event.isCorrect { correct += 1 }
            case .backspace:
                backspaces += 1
            }
        }
        let correctCharacters = zip(session.typed, session.target).count { $0 == $1 }

        return PerformanceMetrics(
            netWPM: wpm(characters: correctCharacters, elapsed: session.elapsed),
            rawWPM: wpm(characters: total, elapsed: session.elapsed),
            accuracy: total == 0 ? 1 : Double(correct) / Double(total),
            elapsed: session.elapsed,
            totalKeystrokes: total,
            correctKeystrokes: correct,
            incorrectKeystrokes: total - correct,
            backspaces: backspaces,
            correctCharacters: correctCharacters,
            incorrectCharacters: session.typed.count - correctCharacters
        )
    }
}
