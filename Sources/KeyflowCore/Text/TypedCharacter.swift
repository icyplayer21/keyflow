import Foundation

/// Turns what a key press produced into the plain character printed on the key.
///
/// Chinese, Japanese and Korean input methods replace punctuation with
/// full-width forms: with Pinyin in Chinese mode, the ; key types "；"
/// (U+FF1B), not ";". Those look alike but would never match the passage,
/// so they are mapped back to their ASCII equivalents before comparison.
public enum TypedCharacter {
    private static let punctuation: [Character: Character] = [
        "\u{3000}": " ",                    // ideographic space
        "\u{3002}": ".", "\u{FF61}": ".",   // 。 ｡
        "\u{3001}": ",", "\u{FF64}": ",",   // 、 ､
        "\u{201C}": "\"", "\u{201D}": "\"", // “ ”
        "\u{2018}": "'", "\u{2019}": "'",   // ‘ ’
        "\u{300A}": "<", "\u{300B}": ">",   // 《 》
        "\u{3008}": "<", "\u{3009}": ">",   // 〈 〉
        "\u{3010}": "[", "\u{3011}": "]",   // 【 】
        "\u{300C}": "[", "\u{300D}": "]",   // 「 」
        "\u{00B7}": "`",                    // · (the ` key in Pinyin)
        "\u{FFE5}": "$", "\u{00A5}": "$",   // ￥ ¥ (Shift-4 in Pinyin)
        "\u{2026}": "^",                    // … (Shift-6 in Pinyin)
        "\u{2014}": "_",                    // — (Shift-minus in Pinyin)
    ]

    public static func normalize(_ character: Character) -> Character {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else { return character }
        // Full-width ASCII block: "！" (FF01) … "～" (FF5E) → "!" … "~".
        if (0xFF01...0xFF5E).contains(scalar.value), let ascii = Unicode.Scalar(scalar.value - 0xFEE0) {
            return Character(ascii)
        }
        return punctuation[character] ?? character
    }
}
