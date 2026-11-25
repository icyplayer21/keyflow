import Testing
@testable import KeyflowCore

@Suite struct TypedCharacterTests {
    @Test func pinyinPunctuationBecomesTheKeysCharacter() {
        let pairs: [(Character, Character)] = [
            ("；", ";"), ("：", ":"), ("，", ","), ("。", "."), ("、", ","), ("？", "?"), ("！", "!"),
            ("“", "\""), ("”", "\""), ("‘", "'"), ("’", "'"), ("（", "("), ("）", ")"), ("《", "<"), ("》", ">"),
            ("【", "["), ("】", "]"), ("「", "["), ("」", "]"), ("￥", "$"), ("·", "`"), ("～", "~"), ("／", "/"),
            ("\u{3000}", " "),
        ]
        for (typed, expected) in pairs {
            #expect(TypedCharacter.normalize(typed) == expected, "\(typed)")
        }
    }

    @Test func fullWidthLettersAndDigitsBecomeAscii() {
        #expect(TypedCharacter.normalize("Ａ") == "A")
        #expect(TypedCharacter.normalize("ｚ") == "z")
        #expect(TypedCharacter.normalize("７") == "7")
    }

    @Test func ordinaryCharactersAreUnchanged() {
        for character in "abcXYZ019;:,./?!'\" -_[]{}()<>@#$%^&*+=~`\\|" {
            #expect(TypedCharacter.normalize(character) == character, "\(character)")
        }
        #expect(TypedCharacter.normalize("é") == "é")
        #expect(TypedCharacter.normalize("中") == "中")
    }
}
