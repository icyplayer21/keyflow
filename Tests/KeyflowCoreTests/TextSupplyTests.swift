import Testing
@testable import KeyflowCore

@Suite struct TextSupplyTests {
    private static let endlessModes: [PracticeMode] = [.commonWords, .sentences, .punctuation, .numbersSymbols]

    private func isTypable(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { (0x20...0x7E).contains($0.value) }
    }

    @Test(arguments: endlessModes)
    func sameSeedGivesSameTextAndDifferentSeedsDiffer(mode: PracticeMode) {
        var a = TextSupply(mode: mode, seed: 11)
        var b = TextSupply(mode: mode, seed: 11)
        var c = TextSupply(mode: mode, seed: 12)
        let text = a.next(atLeast: 400)
        #expect(text == b.next(atLeast: 400))
        #expect(text != c.next(atLeast: 400))
        #expect(a.next(atLeast: 400) == b.next(atLeast: 400))
    }

    @Test(arguments: endlessModes)
    func chunksAreLongEnoughCleanAndTypable(mode: PracticeMode) {
        var supply = TextSupply(mode: mode, seed: 5)
        #expect(supply.isEndless)
        for _ in 0..<20 {
            let chunk = supply.next(atLeast: 300)
            #expect(chunk.count >= 300)
            #expect(!chunk.hasPrefix(" ") && !chunk.hasSuffix(" ") && !chunk.contains("  "))
            #expect(isTypable(chunk))
        }
    }

    @Test func modesProduceTheirOwnKindOfText() {
        var words = TextSupply(mode: .commonWords, seed: 1)
        #expect(words.next(atLeast: 300).allSatisfy { $0.isLetter || $0 == " " })

        var numbers = TextSupply(mode: .numbersSymbols, seed: 1)
        let numberText = numbers.next(atLeast: 600)
        let hasDigits = numberText.contains(where: \.isNumber)
        #expect(hasDigits)
        let symbols = Set("$%#@^&*()[]{}<>=+~_/")
        let hasSymbols = numberText.contains(where: symbols.contains)
        #expect(hasSymbols)

        var punctuation = TextSupply(mode: .punctuation, seed: 1)
        let marks = punctuation.next(atLeast: 600).filter { ",.;:'\"?!-()".contains($0) }
        #expect(marks.count > 40)
    }

    @Test(arguments: [PracticeMode.sentences, .punctuation])
    func passagesDoNotRepeatUntilAllWereUsed(mode: PracticeMode) {
        let corpus = mode == .sentences ? Corpus.sentences : Corpus.punctuation
        let total = corpus.reduce(-1) { $0 + $1.count + 1 }   // every passage, joined by spaces
        var supply = TextSupply(mode: mode, seed: 9)
        let everything = supply.next(atLeast: total)
        #expect(everything.count == total)
        #expect(corpus.allSatisfy { everything.contains($0) })
    }

    @Test func corporaAreUniqueTypableAndBigEnough() {
        for corpus in [Corpus.sentences, Corpus.punctuation] {
            #expect(Set(corpus).count == corpus.count)
            #expect(corpus.allSatisfy { isTypable($0) && !$0.contains("  ") && $0 == TextNormalizer.normalize($0) })
        }
        // A 120 s test at 150 WPM needs about 1500 characters without repeats.
        #expect(Corpus.sentences.reduce(0) { $0 + $1.count } > 3_000)
        #expect(Corpus.punctuation.count >= 30)
    }

    @Test func generatedArithmeticIsCorrect() {
        var generator = SeededGenerator(seed: 3)
        var checked = 0
        for _ in 0..<2_000 {
            let token = NumberSymbolGenerator.token(using: &generator)
            let sides = token.components(separatedBy: " = ")
            guard sides.count == 2, let result = Int(sides[1]) else { continue }
            let terms = sides[0].split(separator: " ")
            guard terms.count == 3, let a = Int(terms[0]), let b = Int(terms[2]) else { continue }
            switch terms[1] {
            case "+": #expect(a + b == result)
            case "-": #expect(a - b == result && result >= 0)
            case "*": #expect(a * b == result)
            default: Issue.record("Unexpected operator in \(token)")
            }
            checked += 1
        }
        #expect(checked > 100)
    }

    @Test func customTextIsHandedOverOnceNormalised() {
        var supply = TextSupply(mode: .customText, customText: "  It\u{2019}s  a\n\n\u{201C}test\u{201D} \u{2014} really\u{2026}  ", seed: 1)
        #expect(!supply.isEndless)
        #expect(supply.next(atLeast: 500) == "It's a \"test\" - really...")
        #expect(supply.next(atLeast: 500).isEmpty)
    }
}

@Suite struct TextNormalizerTests {
    @Test func collapsesWhitespaceAndTrims() {
        #expect(TextNormalizer.normalize("  one\ttwo\n\nthree \r\n four\u{00A0}five  ") == "one two three four five")
        #expect(TextNormalizer.normalize(" \n\t ").isEmpty)
        #expect(TextNormalizer.normalize("").isEmpty)
    }

    @Test func replacesTypographicCharacters() {
        #expect(TextNormalizer.normalize("\u{2018}a\u{2019} \u{201C}b\u{201D} c\u{2013}d e\u{2014}f g\u{2026}") == "'a' \"b\" c-d e-f g...")
    }

    @Test func dropsInvisibleCharactersButKeepsOtherText() {
        #expect(TextNormalizer.normalize("a\u{200B}b\u{0007}c caf\u{00E9}") == "abc caf\u{00E9}")
    }

    @Test func capsVeryLongText() {
        let long = String(repeating: "word ", count: 10_000)
        let result = TextNormalizer.normalize(long)
        #expect(result.count <= TextNormalizer.maximumLength)
        #expect(!result.hasSuffix(" "))
    }

    @Test func isIdempotent() {
        let once = TextNormalizer.normalize("  \u{201C}Hello\u{201D},\n world\u{2026} ")
        #expect(TextNormalizer.normalize(once) == once)
    }
}

@Suite struct SessionKindTests {
    @Test func storageKeysRoundTrip() {
        let kinds = [SessionKind.test] + PracticeMode.allCases.map(SessionKind.practice)
        for kind in kinds {
            #expect(SessionKind(storageKey: kind.storageKey) == kind)
        }
        #expect(Set(kinds.map(\.storageKey)).count == kinds.count)
        #expect(SessionKind(storageKey: "practice.unknown") == nil)
        #expect(SessionKind(storageKey: "") == nil)
    }
}
