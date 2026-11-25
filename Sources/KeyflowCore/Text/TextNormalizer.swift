import Foundation

/// Makes pasted text typable on a standard English keyboard.
public enum TextNormalizer {
    /// Longest custom passage kept, in characters.
    public static let maximumLength = 20_000

    private static let replacements: [Character: String] = [
        "\u{2018}": "'", "\u{2019}": "'", "\u{201A}": "'", "\u{2032}": "'",
        "\u{201C}": "\"", "\u{201D}": "\"", "\u{201E}": "\"", "\u{2033}": "\"",
        "\u{2013}": "-", "\u{2014}": "-", "\u{2212}": "-", "\u{2010}": "-", "\u{2011}": "-",
        "\u{2026}": "...",
        "\u{00A0}": " ", "\u{2009}": " ", "\u{202F}": " ", "\u{2003}": " ", "\u{2002}": " ",
    ]

    /// - Typographic quotes, dashes and ellipses become their keyboard equivalents.
    /// - Line breaks, tabs and runs of spaces collapse to a single space.
    /// - Control and other invisible characters are dropped.
    /// - Leading and trailing whitespace is removed.
    public static func normalize(_ text: String) -> String {
        var result = ""
        var pendingSpace = false

        for character in text {
            let mapped = replacements[character] ?? String(character)
            for piece in mapped {
                if piece.isWhitespace {
                    pendingSpace = !result.isEmpty
                } else if isVisible(piece) {
                    if pendingSpace { result.append(" ") }
                    pendingSpace = false
                    result.append(piece)
                }
            }
            if result.count >= maximumLength { break }
        }
        return String(result.prefix(maximumLength)).trimmingCharacters(in: .whitespaces)
    }

    private static func isVisible(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .surrogate, .privateUse, .unassigned, .lineSeparator, .paragraphSeparator:
                false
            default:
                true
            }
        }
    }
}
