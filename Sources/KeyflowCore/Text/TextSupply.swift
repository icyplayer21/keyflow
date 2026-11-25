import Foundation

/// Produces the text for a session, chunk by chunk. Deterministic for a seed.
///
/// Every mode except Custom Text is endless; Custom Text hands over the
/// (normalised) passage once and is then exhausted.
public struct TextSupply: Sendable {
    public let mode: PracticeMode

    private var generator: SeededGenerator
    private var words: WordStream
    private var deck: [String] = []
    private var lastDrawn: String?
    private var custom: String?

    public init(mode: PracticeMode, customText: String = "", seed: UInt64) {
        self.mode = mode
        var generator = SeededGenerator(seed: seed)
        self.words = WordStream(seed: generator.next())
        self.generator = generator
        self.custom = mode == .customText ? TextNormalizer.normalize(customText) : nil
    }

    public var isEndless: Bool { mode != .customText }

    /// The next chunk: at least `minimum` characters for endless modes, with no
    /// leading or trailing space. Returns an empty string once exhausted.
    public mutating func next(atLeast minimum: Int) -> String {
        if mode == .customText {
            defer { custom = nil }
            return custom ?? ""
        }
        var pieces: [String] = []
        var length = 0
        while length < minimum || pieces.isEmpty {
            let piece = nextPiece()
            length += piece.count + (pieces.isEmpty ? 0 : 1)
            pieces.append(piece)
        }
        return pieces.joined(separator: " ")
    }

    private mutating func nextPiece() -> String {
        switch mode {
        case .commonWords: words.nextWord()
        case .sentences: draw(from: Corpus.sentences)
        case .punctuation: draw(from: Corpus.punctuation)
        case .numbersSymbols: NumberSymbolGenerator.token(using: &generator)
        case .customText: ""
        }
    }

    /// Deals passages like a shuffled deck: none repeats until all were used,
    /// and a reshuffle never puts the same passage twice in a row.
    private mutating func draw(from corpus: [String]) -> String {
        if deck.isEmpty {
            deck = corpus.shuffled(using: &generator)
            if deck.count > 1, deck.last == lastDrawn { deck.swapAt(0, deck.count - 1) }
        }
        let passage = deck.removeLast()
        lastDrawn = passage
        return passage
    }
}

/// Short tokens that exercise the number row and symbol keys.
public enum NumberSymbolGenerator {
    public static func token<G: RandomNumberGenerator>(using generator: inout G) -> String {
        let a = Int.random(in: 2...99, using: &generator)
        let b = Int.random(in: 2...99, using: &generator)
        func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }

        switch Int.random(in: 0..<24, using: &generator) {
        case 0: return "\(a * b)"
        case 1: return "\(a).\(b)"
        case 2: return "$\(a).\(two(b))"
        case 3: return "\(a)%"
        case 4: return "\(a % 12 + 1):\(two(b % 60))"
        case 5: return "\(a % 12 + 1)/\(b % 28 + 1)/\(1990 + a % 40)"
        case 6: return "\(a) + \(b) = \(a + b)"
        case 7: return "\(max(a, b)) - \(min(a, b)) = \(abs(a - b))"
        case 8: return "\(a % 11 + 2) * \(b % 11 + 2) = \((a % 11 + 2) * (b % 11 + 2))"
        case 9: return "#\(a)"
        case 10: return "(\(a))"
        case 11: return "[\(a), \(b)]"
        case 12: return "\(a) < \(a + b)"
        case 13: return "\(a + b) > \(b)"
        case 14: return "\(a)/\(b)"
        case 15: return "user\(a)@mail.com"
        case 16: return "\(a)^2"
        case 17: return "~\(a)"
        case 18: return "{id: \(a)}"
        case 19: return "v\(a % 10).\(b % 10).\(a % 7)"
        case 20: return "\(a) & \(b)"
        case 21: return "+\(a)-\(b)"
        case 22: return "\(a)_\(b)"
        default: return a == b ? "\(a) == \(b)" : "\(a) != \(b)"
        }
    }
}
