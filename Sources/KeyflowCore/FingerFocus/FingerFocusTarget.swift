import Foundation

/// The fingers Finger Focus can train. Ring fingers and pinkies come first:
/// they are the weakest and least independent, so they gain most from
/// isolation. Middle and index fingers can be trained too, mainly when
/// Finger Intelligence points to them. Thumbs only press Space and have no
/// drills of their own.
public enum FingerFocusTarget: String, CaseIterable, Identifiable, Sendable {
    case leftPinky, leftRing, rightRing, rightPinky, bothPinkies, bothRings
    case leftMiddle, leftIndex, rightIndex, rightMiddle

    public var id: Self { self }

    /// The ring-finger and pinky targets offered up front.
    public static let primary: [FingerFocusTarget] = [.leftPinky, .leftRing, .rightRing, .rightPinky, .bothPinkies, .bothRings]

    public var title: String {
        switch self {
        case .leftPinky: "Left Pinky"
        case .leftRing: "Left Ring"
        case .rightRing: "Right Ring"
        case .rightPinky: "Right Pinky"
        case .bothPinkies: "Both Pinkies"
        case .bothRings: "Both Ring Fingers"
        case .leftMiddle: "Left Middle"
        case .leftIndex: "Left Index"
        case .rightIndex: "Right Index"
        case .rightMiddle: "Right Middle"
        }
    }

    public var fingers: [Finger] {
        switch self {
        case .leftPinky: [.leftPinky]
        case .leftRing: [.leftRing]
        case .rightRing: [.rightRing]
        case .rightPinky: [.rightPinky]
        case .bothPinkies: [.leftPinky, .rightPinky]
        case .bothRings: [.leftRing, .rightRing]
        case .leftMiddle: [.leftMiddle]
        case .leftIndex: [.leftIndex]
        case .rightIndex: [.rightIndex]
        case .rightMiddle: [.rightMiddle]
        }
    }

    /// Every key the target fingers are trained on, finger by finger, each
    /// as home, top, bottom row.
    public var keys: [Character] { fingers.flatMap(FingerKeys.keys(for:)) }

    /// Keys an exercise for this target may contain besides the target keys:
    /// those of the neighbouring fingers on the same hand.
    public var neighbourKeys: [Character] {
        fingers.flatMap { finger in FingerKeys.neighbours(of: finger).flatMap(FingerKeys.keys(for:)) }
    }

    /// Every key an exercise for levels 1–3 may contain, besides space.
    public var drillKeys: Set<Character> { Set(keys + neighbourKeys) }
}

/// The keys standard US QWERTY touch typing assigns to each finger, limited
/// to the three letter rows Finger Focus trains.
///
/// This is placement guidance only. Keyflow sees which key was pressed, never
/// which finger pressed it.
public enum FingerKeys {
    /// Home, top, bottom row, in that order. The index fingers' two columns
    /// are listed inner column last.
    public static func keys(for finger: Finger) -> [Character] {
        switch finger {
        case .leftPinky: ["a", "q", "z"]
        case .leftRing: ["s", "w", "x"]
        case .leftMiddle: ["d", "e", "c"]
        case .leftIndex: ["f", "r", "v", "g", "t", "b"]
        case .thumb: []
        case .rightIndex: ["j", "u", "m", "h", "y", "n"]
        case .rightMiddle: ["k", "i", ","]
        case .rightRing: ["l", "o", "."]
        case .rightPinky: [";", "p", "/"]
        }
    }

    /// The key a finger uses on a row: 0 home, 1 top, 2 bottom.
    public static func key(for finger: Finger, row: Int) -> Character? {
        let keys = keys(for: finger)
        return keys.indices.contains(row) ? keys[row] : nil
    }

    /// The fingers directly beside this one on the same hand.
    public static func neighbours(of finger: Finger) -> [Finger] {
        switch finger {
        case .leftPinky: [.leftRing]
        case .leftRing: [.leftPinky, .leftMiddle]
        case .leftMiddle: [.leftRing, .leftIndex]
        case .leftIndex: [.leftMiddle]
        case .thumb: []
        case .rightIndex: [.rightMiddle]
        case .rightMiddle: [.rightIndex, .rightRing]
        case .rightRing: [.rightMiddle, .rightPinky]
        case .rightPinky: [.rightRing]
        }
    }
}

/// The four Finger Focus levels. Unlike Learn lessons they are never locked:
/// the user may pick any level, and Keyflow only recommends one.
public enum FingerFocusLevel: Int, CaseIterable, Identifiable, Sendable, Comparable {
    case activation = 1, coordination, movement, words

    public var id: Self { self }

    public var title: String {
        switch self {
        case .activation: "Activation"
        case .coordination: "Coordination"
        case .movement: "Movement"
        case .words: "Words"
        }
    }

    public var instructions: String {
        switch self {
        case .activation:
            "Press each key a few times in a row. Move only the target finger and let it return to its home key."
        case .coordination:
            "Alternate between the target finger and the finger beside it, keeping both on their own keys."
        case .movement:
            "Reach between the target finger's own keys: home to top, home to bottom, and across."
        case .words:
            "Short English words chosen because they use the target finger's keys often."
        }
    }

    public var next: FingerFocusLevel? { FingerFocusLevel(rawValue: rawValue + 1) }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
