import Foundation

/// A region of the keyboard to learn. Categories build on each other in
/// order: the top and bottom rows are reached from the home row, so their
/// exercises may also use home-row keys.
public enum TrainingCategory: String, CaseIterable, Identifiable, Sendable {
    case homeRow, topRow, bottomRow, leftHand, rightHand, fullKeyboard

    public var id: Self { self }

    public var title: String {
        switch self {
        case .homeRow: "Home Row"
        case .topRow: "Top Row"
        case .bottomRow: "Bottom Row"
        case .leftHand: "Left Hand"
        case .rightHand: "Right Hand"
        case .fullKeyboard: "Full Keyboard"
        }
    }

    public var instructions: String {
        switch self {
        case .homeRow:
            "Rest your left fingers on A S D F and your right fingers on J K L ;. The bumps on F and J let you find them without looking."
        case .topRow:
            "Reach up from the home row to the top row, then come back. Each finger stays in its own column."
        case .bottomRow:
            "Reach down from the home row to the bottom row, then come back to your resting keys."
        case .leftHand:
            "Every letter on the left side of the keyboard, typed with the left hand only."
        case .rightHand:
            "Every key on the right side of the keyboard, typed with the right hand only."
        case .fullKeyboard:
            "All letter keys together, plus ; , . and /. Keep returning to the home row."
        }
    }

    /// The keys taught here, in the order they are introduced. Keys in a
    /// group are learned together; row categories pair mirror-image keys.
    public var keyGroups: [[Character]] {
        switch self {
        case .homeRow: [["f", "j"], ["d", "k"], ["s", "l"], ["a", ";"], ["g", "h"]]
        case .topRow: [["r", "u"], ["e", "i"], ["w", "o"], ["q", "p"], ["t", "y"]]
        case .bottomRow: [["v", "m"], ["c", ","], ["x", "."], ["z", "/"], ["b", "n"]]
        case .leftHand: [["f", "d", "s", "a"], ["r", "e", "w", "q"], ["v", "c", "x", "z"], ["g", "t", "b"]]
        case .rightHand: [["j", "k", "l", ";"], ["u", "i", "o", "p"], ["m", ",", ".", "/"], ["h", "y", "n"]]
        case .fullKeyboard:
            [["f", "j", "d", "k", "s", "l", "a", ";"], ["r", "u", "e", "i", "w", "o", "q", "p"],
             ["v", "m", "c", ",", "x", ".", "z", "/"], ["g", "h", "t", "y", "b", "n"]]
        }
    }

    /// Every key an exercise in this category may contain, besides space.
    public var allowedKeys: Set<Character> {
        switch self {
        case .homeRow: Set(Self.home)
        case .topRow: Set(Self.home + Self.top)
        case .bottomRow, .fullKeyboard: Set(Self.home + Self.top + Self.bottom)
        case .leftHand: Set("qwertasdfgzxcvb")
        case .rightHand: Set("yuiophjkl;nm,./")
        }
    }

    private static let home = "asdfghjkl;"
    private static let top = "qwertyuiop"
    private static let bottom = "zxcvbnm,./"
}

public enum TrainingStage: Int, CaseIterable, Identifiable, Sendable, Comparable {
    case singleKeys = 1, transitions, patterns, words

    public var id: Self { self }

    public var title: String {
        switch self {
        case .singleKeys: "Single Keys"
        case .transitions: "Key Transitions"
        case .patterns: "Patterns"
        case .words: "Words"
        }
    }

    public var instructions: String {
        switch self {
        case .singleKeys: "Press each key four times. Keep your eyes on the screen, not your hands."
        case .transitions: "Alternate between two keys to build the movement from one to the other."
        case .patterns: "Short sequences that roll across neighbouring fingers and back."
        case .words: "Real words that use only the keys in this category."
        }
    }

    public var next: TrainingStage? { TrainingStage(rawValue: rawValue + 1) }
    public var previous: TrainingStage? { TrainingStage(rawValue: rawValue - 1) }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
