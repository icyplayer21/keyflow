import Foundation

/// One physical key of a US QWERTY keyboard.
public struct KeyboardKey: Sendable, Equatable, Hashable {
    /// The unshifted character ("a", "1", ";").
    public let base: Character
    /// The shifted symbol, where it is a different character ("!", ":").
    /// Letters have none: upper case is already folded into the base.
    public let shifted: Character?

    public var label: String { base == " " ? "space" : String(base) }
}

/// Typing statistics folded onto a physical key.
public struct KeyHeat: Sendable, Equatable, Identifiable {
    public let key: KeyboardKey
    public var attempts = 0
    public var errors = 0
    public var latencySamples = 0
    var latencyTotal: TimeInterval = 0

    public var id: Character { key.base }
    public var errorRate: Double? { attempts > 0 ? Double(errors) / Double(attempts) : nil }
    public var meanLatency: TimeInterval? { latencySamples > 0 ? latencyTotal / Double(latencySamples) : nil }
}

public enum KeyboardLayout {
    /// Rows top to bottom; the last row is the space bar alone.
    public static let rows: [[KeyboardKey]] = [
        keys("`1234567890-=", shifted: "~!@#$%^&*()_+"),
        keys("qwertyuiop[]\\", shifted: "          {}|"),
        keys("asdfghjkl;'", shifted: "         :\""),
        keys("zxcvbnm,./", shifted: "       <>?"),
        [KeyboardKey(base: " ", shifted: nil)],
    ]

    /// How far each row is indented, in key widths.
    public static let rowOffsets: [Double] = [0, 1.5, 1.8, 2.3, 4.3]
    /// Width of the space bar, in key widths.
    public static let spaceBarWidth = 6.0

    /// The profile's per-character statistics folded onto physical keys, in
    /// layout order. Shifted symbols count toward the key that produces them.
    public static func heat(for profile: TypingProfile) -> [[KeyHeat]] {
        rows.map { row in
            row.map { key in
                var heat = KeyHeat(key: key)
                for character in [key.base, key.shifted].compactMap({ $0 }) {
                    guard let stat = profile.keys[character] else { continue }
                    heat.attempts += stat.attempts
                    heat.errors += stat.errors
                    heat.latencySamples += stat.latencySamples
                    heat.latencyTotal += stat.latencyTotal
                }
                return heat
            }
        }
    }

    private static func keys(_ base: String, shifted: String) -> [KeyboardKey] {
        zip(base, shifted).map { KeyboardKey(base: $0, shifted: $1 == " " ? nil : $1) }
    }
}
