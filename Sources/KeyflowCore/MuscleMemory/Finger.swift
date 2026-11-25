import Foundation

public enum Hand: String, Sendable, CaseIterable {
    case left, right

    public var title: String { self == .left ? "Left hand" : "Right hand" }
}

/// The finger that standard touch typing assigns to a key. This is a
/// recommendation only: Keyflow cannot see which finger is actually used.
public enum Finger: String, Sendable, CaseIterable, Hashable {
    case leftPinky, leftRing, leftMiddle, leftIndex, thumb, rightIndex, rightMiddle, rightRing, rightPinky

    public var hand: Hand? {
        switch self {
        case .leftPinky, .leftRing, .leftMiddle, .leftIndex: .left
        case .thumb: nil
        case .rightIndex, .rightMiddle, .rightRing, .rightPinky: .right
        }
    }

    /// "Pinky", "Ring", "Middle", "Index" or "Thumb".
    public var name: String {
        switch self {
        case .leftPinky, .rightPinky: "Pinky"
        case .leftRing, .rightRing: "Ring"
        case .leftMiddle, .rightMiddle: "Middle"
        case .leftIndex, .rightIndex: "Index"
        case .thumb: "Thumb"
        }
    }

    /// "left index finger", "thumb".
    public var title: String {
        guard let hand else { return "thumb" }
        return "\(hand == .left ? "left" : "right") \(name.lowercased()) finger"
    }

    /// The home-row key this finger rests on. The thumb rests on the space bar.
    public var homeKey: Character? {
        switch self {
        case .leftPinky: "a"
        case .leftRing: "s"
        case .leftMiddle: "d"
        case .leftIndex: "f"
        case .thumb: nil
        case .rightIndex: "j"
        case .rightMiddle: "k"
        case .rightRing: "l"
        case .rightPinky: ";"
        }
    }
}

public enum FingerMap {
    private static let table: [Character: Finger] = {
        var table: [Character: Finger] = [" ": .thumb]
        let columns: [(String, Finger)] = [
            ("`1qaz", .leftPinky), ("2wsx", .leftRing), ("3edc", .leftMiddle), ("45rtfgvb", .leftIndex),
            ("67yuhjnm", .rightIndex), ("8ik,", .rightMiddle), ("9ol.", .rightRing), ("0-=p[]\\;'/", .rightPinky),
        ]
        for (keys, finger) in columns {
            for key in keys { table[key] = finger }
        }
        return table
    }()

    /// The recommended finger for a character. Upper-case letters and shifted
    /// symbols use the finger of the key that produces them.
    public static func finger(for character: Character) -> Finger? {
        table[KeyboardLayout.baseKey(for: character) ?? character]
    }

    public static func hand(for character: Character) -> Hand? {
        finger(for: character)?.hand
    }
}

/// Where a key sits: row 0 is the number row, row 4 the space bar.
public struct KeyPosition: Sendable, Hashable {
    public let row: Int
    public let column: Int
}

extension KeyboardLayout {
    private static let index: [Character: (base: Character, position: KeyPosition)] = {
        var index: [Character: (base: Character, position: KeyPosition)] = [:]
        for (row, keys) in rows.enumerated() {
            for (column, key) in keys.enumerated() {
                let entry = (key.base, KeyPosition(row: row, column: column))
                index[key.base] = entry
                if let shifted = key.shifted { index[shifted] = entry }
            }
        }
        for letter in "abcdefghijklmnopqrstuvwxyz" {
            index[Character(letter.uppercased())] = index[letter]
        }
        return index
    }()

    /// The unshifted key that produces `character` ("A" → "a", "!" → "1").
    public static func baseKey(for character: Character) -> Character? {
        index[character]?.base
    }

    public static func position(of character: Character) -> KeyPosition? {
        index[character]?.position
    }
}
