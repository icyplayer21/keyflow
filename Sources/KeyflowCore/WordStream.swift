import Foundation

/// SplitMix64. Small, fast, and reproducible from a seed, which keeps text
/// generation deterministic under test.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49FB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// An endless supply of words drawn from a list, never repeating a word
/// back-to-back.
public struct WordStream: Sendable {
    private let words: [String]
    private var generator: SeededGenerator
    private var last: String?

    public init(words: [String] = WordList.common, seed: UInt64) {
        precondition(!words.isEmpty, "WordStream needs at least one word")
        self.words = words
        self.generator = SeededGenerator(seed: seed)
    }

    public mutating func nextWord() -> String {
        var word = words.randomElement(using: &generator)!
        if words.count > 1 {
            while word == last { word = words.randomElement(using: &generator)! }
        }
        last = word
        return word
    }

    /// `count` words joined by single spaces, with no leading or trailing space.
    public mutating func next(_ count: Int) -> String {
        (0..<max(0, count)).map { _ in nextWord() }.joined(separator: " ")
    }
}
