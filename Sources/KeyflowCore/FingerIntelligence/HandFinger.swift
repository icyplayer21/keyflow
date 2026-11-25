import Foundation

/// All ten fingers, for display. Typing analysis uses `Finger`, which has a
/// single thumb: the Space key is shared by both thumbs, so Keyflow cannot
/// tell them apart and both thumbs show the same Space-key estimate.
public enum HandFinger: String, CaseIterable, Identifiable, Sendable, Hashable {
    case leftPinky, leftRing, leftMiddle, leftIndex, leftThumb
    case rightThumb, rightIndex, rightMiddle, rightRing, rightPinky

    public var id: Self { self }

    public var hand: Hand {
        switch self {
        case .leftPinky, .leftRing, .leftMiddle, .leftIndex, .leftThumb: .left
        default: .right
        }
    }

    /// The finger standard touch typing analyses for this one.
    public var finger: Finger {
        switch self {
        case .leftPinky: .leftPinky
        case .leftRing: .leftRing
        case .leftMiddle: .leftMiddle
        case .leftIndex: .leftIndex
        case .leftThumb, .rightThumb: .thumb
        case .rightIndex: .rightIndex
        case .rightMiddle: .rightMiddle
        case .rightRing: .rightRing
        case .rightPinky: .rightPinky
        }
    }

    public var isThumb: Bool { finger == .thumb }

    /// "Left ring finger", "Right thumb".
    public var title: String {
        let side = hand == .left ? "Left" : "Right"
        return isThumb ? "\(side) thumb" : "\(side) \(finger.name.lowercased()) finger"
    }

    /// "Ring", "Thumb".
    public var shortName: String { finger.name }

    /// The keys standard US QWERTY touch typing assigns to this finger,
    /// including the number row and outer punctuation keys.
    public var assignedKeys: [Character] { FingerAssignment.keys(for: finger) }

    /// The Finger Focus target that trains this finger, if there is one.
    public var trainingTarget: FingerFocusTarget? { FingerFocusTarget.single(finger) }

    /// Left pinky first, across to right pinky: the order fingers sit on the keyboard.
    public static let keyboardOrder: [HandFinger] = allCases
}

/// The full US QWERTY touch-typing assignment, every key of the main block.
/// `FingerMap` answers "which finger types this character"; this answers
/// "which keys belong to this finger".
public enum FingerAssignment {
    private static let table: [Finger: [Character]] = {
        var table: [Finger: [Character]] = [:]
        for row in KeyboardLayout.rows {
            for key in row {
                guard let finger = FingerMap.finger(for: key.base) else { continue }
                table[finger, default: []].append(key.base)
            }
        }
        return table
    }()

    /// Keys in keyboard order, top row first. The thumb has only Space.
    public static func keys(for finger: Finger) -> [Character] {
        table[finger] ?? []
    }
}

extension FingerFocusTarget {
    /// The single-finger target for a finger, or `nil` for the thumb.
    public static func single(_ finger: Finger) -> FingerFocusTarget? {
        allCases.first { $0.fingers == [finger] }
    }
}
