import Carbon.HIToolbox
import Foundation

/// The keyboard layout macOS is typing with, for deciding whether
/// Typing Mechanics can judge which characters need Shift.
///
/// Shift and Caps Lock detection works on any layout. What depends on the
/// layout is the *requirement*: "@" needs Shift on US QWERTY but not on every
/// layout. Keyflow's requirements are US QWERTY's, so on other layouts the
/// technique for symbols is reported as unknown rather than judged.
struct KeyboardLayoutInfo: Equatable {
    /// e.g. "com.apple.keylayout.ABC".
    let identifier: String
    let name: String

    /// Layouts whose letter, digit and shifted-symbol keys match US QWERTY.
    /// Input methods report the layout they type Latin characters with.
    static let usCompatible: Set<String> = [
        "com.apple.keylayout.US",
        "com.apple.keylayout.ABC",
        "com.apple.keylayout.USExtended",
        "com.apple.keylayout.ABC-Extended",
        // Pinyin types on the US QWERTY arrangement. In Chinese mode its
        // punctuation is full-width ("；", "！"), which TypedCharacter maps back.
        "com.apple.keylayout.PinyinKeyboard",
    ]

    var isUSCompatible: Bool { Self.usCompatible.contains(identifier) }

    /// The layout under the current input source (for an input method, the
    /// layout it types Latin characters with).
    static func current() -> KeyboardLayoutInfo? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        func property(_ key: CFString) -> String? {
            guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
            return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        }
        guard let identifier = property(kTISPropertyInputSourceID) else { return nil }
        return KeyboardLayoutInfo(identifier: identifier, name: property(kTISPropertyLocalizedName) ?? identifier)
    }
}
