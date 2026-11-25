import Foundation

/// Which Shift key is held.
public enum ShiftSide: String, Sendable, Codable, CaseIterable {
    case left, right, both
}

/// The modifier state that came with one keyboard event, as reported by
/// macOS. Built from the raw `NSEvent.modifierFlags` value so the decoding
/// can be tested without AppKit.
public struct ModifierSnapshot: Sendable, Equatable, Codable {
    public var leftShift: Bool
    public var rightShift: Bool
    /// The device-independent Shift flag. Usually set together with a side
    /// bit; some keyboards and remapping tools report it alone.
    public var shift: Bool
    public var capsLock: Bool

    public init(leftShift: Bool = false, rightShift: Bool = false, shift: Bool? = nil, capsLock: Bool = false) {
        self.leftShift = leftShift
        self.rightShift = rightShift
        self.shift = shift ?? (leftShift || rightShift)
        self.capsLock = capsLock
    }

    // Bits of NSEvent.ModifierFlags.rawValue. The device-dependent side bits
    // (NX_DEVICELSHIFTKEYMASK, NX_DEVICERSHIFTKEYMASK) are part of the raw
    // value macOS delivers to applications.
    public static let capsLockMask: UInt = 1 << 16
    public static let shiftMask: UInt = 1 << 17
    public static let leftShiftMask: UInt = 0x0002
    public static let rightShiftMask: UInt = 0x0004

    public init(rawFlags: UInt) {
        self.init(leftShift: rawFlags & Self.leftShiftMask != 0,
                  rightShift: rawFlags & Self.rightShiftMask != 0,
                  shift: rawFlags & Self.shiftMask != 0,
                  capsLock: rawFlags & Self.capsLockMask != 0)
    }

    /// Which Shift is held, if one is and the side is known.
    public var shiftSide: ShiftSide? {
        switch (leftShift, rightShift) {
        case (true, true): .both
        case (true, false): .left
        case (false, true): .right
        case (false, false): nil
        }
    }
}

/// A change of modifier state between key presses, from `flagsChanged`.
public enum ModifierEvent: Sendable, Equatable {
    case shiftDown(ShiftSide?, at: TimeInterval)
    case shiftUp(ShiftSide?, at: TimeInterval)
    case capsLock(on: Bool, at: TimeInterval)
    /// The window lost keyboard focus: key-ups may never arrive.
    case focusLost(at: TimeInterval)
    /// The full state, read when typing starts or focus returns.
    case sync(ModifierSnapshot, at: TimeInterval)

    public var time: TimeInterval {
        switch self {
        case .shiftDown(_, let t), .shiftUp(_, let t), .capsLock(_, let t), .focusLost(let t), .sync(_, let t): t
        }
    }

    // Hardware key codes (kVK_Shift, kVK_RightShift, kVK_CapsLock).
    public static let leftShiftKeyCode: UInt16 = 56
    public static let rightShiftKeyCode: UInt16 = 60
    public static let capsLockKeyCode: UInt16 = 57

    /// Interprets a `flagsChanged` event: which key changed and its new state.
    /// Returns `nil` for modifiers Typing Mechanics does not track.
    public static func from(flagsChangedKeyCode keyCode: UInt16, rawFlags: UInt, at time: TimeInterval) -> ModifierEvent? {
        let snapshot = ModifierSnapshot(rawFlags: rawFlags)
        switch keyCode {
        case leftShiftKeyCode:
            return snapshot.leftShift ? .shiftDown(.left, at: time) : .shiftUp(.left, at: time)
        case rightShiftKeyCode:
            return snapshot.rightShift ? .shiftDown(.right, at: time) : .shiftUp(.right, at: time)
        case capsLockKeyCode:
            return .capsLock(on: snapshot.capsLock, at: time)
        default:
            return nil
        }
    }
}

/// How an upper-case letter or shifted symbol was produced, as observed.
public enum CaseTechnique: String, Sendable, Codable, CaseIterable {
    case leftShift
    case rightShift
    /// Shift was held but which one could not be told.
    case shift
    case capsLock
    /// Caps Lock on and Shift held at once.
    case capsLockWithShift
    /// No modifier was needed or used (lower case, digits, unshifted symbols).
    case unmodified
    /// The character arrived but how it was produced cannot be established
    /// reliably (an input method, a remapping tool, missed modifier events).
    case unknown

    public var usesShift: Bool { [.leftShift, .rightShift, .shift, .capsLockWithShift].contains(self) }
    public var usesCapsLock: Bool { self == .capsLock || self == .capsLockWithShift }
}

/// What a character needs on a US QWERTY keyboard.
public enum CaseRequirement: Sendable, Equatable {
    /// "a", "1", ";", space.
    case plain
    /// "A": Shift or Caps Lock.
    case uppercaseLetter
    /// "!", "@", ":": Shift only (Caps Lock does not affect them).
    case shiftedSymbol
    /// Not on the US QWERTY layout ("é", "…").
    case unsupported

    public static func of(_ character: Character) -> CaseRequirement {
        if character == " " { return .plain }
        if character.isLetter, character.isASCII {
            return character.isUppercase ? .uppercaseLetter : .plain
        }
        for row in KeyboardLayout.rows {
            for key in row {
                if key.base == character { return .plain }
                if key.shifted == character { return .shiftedSymbol }
            }
        }
        return .unsupported
    }
}
