import Testing
@testable import KeyflowCore

@Suite struct LineLayoutTests {
    private func lines(_ text: String, columns: Int) -> [String] {
        let characters = Array(text)
        return LineLayout.wrap(characters, columns: columns).map { String(characters[$0]) }
    }

    @Test func wrapsBetweenWordsKeepingTrailingSpace() {
        #expect(lines("the quick brown fox", columns: 10) == ["the quick ", "brown fox"])
    }

    @Test func rangesAreContiguousAndCoverTheText() {
        let text = Array("one two three four five six seven eight nine ten")
        for columns in 1...30 {
            let ranges = LineLayout.wrap(text, columns: columns)
            #expect(ranges.first?.lowerBound == 0)
            #expect(ranges.last?.upperBound == text.count)
            for (a, b) in zip(ranges, ranges.dropFirst()) { #expect(a.upperBound == b.lowerBound) }
            #expect(ranges.allSatisfy { $0.count <= columns && !$0.isEmpty })
        }
    }

    @Test func hardSplitsWordsLongerThanALine() {
        #expect(lines("abcdefghij kl", columns: 4) == ["abcd", "efgh", "ij ", "kl"])
    }

    @Test func emptyAndDegenerateInput() {
        #expect(LineLayout.wrap([], columns: 10).isEmpty)
        #expect(LineLayout.wrap(Array("abc"), columns: 0) == [0..<3])
    }

    @Test func appendingTextNeverChangesEarlierLines() {
        let short = Array("the quick brown fox jumps")
        let long = short + Array(" over the lazy dog again")
        let before = LineLayout.wrap(short, columns: 12)
        let after = LineLayout.wrap(long, columns: 12)
        #expect(Array(after.prefix(before.count - 1)) == Array(before.dropLast()))
    }

    @Test func lineIndexOfPosition() {
        let ranges = LineLayout.wrap(Array("the quick brown fox"), columns: 10)
        #expect(LineLayout.lineIndex(of: 0, in: ranges) == 0)
        #expect(LineLayout.lineIndex(of: 9, in: ranges) == 0)
        #expect(LineLayout.lineIndex(of: 10, in: ranges) == 1)
        #expect(LineLayout.lineIndex(of: 19, in: ranges) == 1)   // end of text
        #expect(LineLayout.lineIndex(of: 0, in: []) == 0)
    }
}

@Suite struct WordStreamTests {
    @Test func sameSeedProducesSameText() {
        var a = WordStream(seed: 42)
        var b = WordStream(seed: 42)
        #expect(a.next(50) == b.next(50))
    }

    @Test func differentSeedsProduceDifferentText() {
        var a = WordStream(seed: 1)
        var b = WordStream(seed: 2)
        #expect(a.next(50) != b.next(50))
    }

    @Test func producesRequestedCountWithSingleSpaces() {
        var stream = WordStream(seed: 7)
        let text = stream.next(40)
        #expect(text.split(separator: " ", omittingEmptySubsequences: false).count == 40)
        #expect(!text.hasPrefix(" ") && !text.hasSuffix(" ") && !text.contains("  "))
        #expect(stream.next(0).isEmpty)
    }

    @Test func neverRepeatsAWordBackToBack() {
        var stream = WordStream(words: ["a", "b"], seed: 3)
        let words = stream.next(200).split(separator: " ")
        for (first, second) in zip(words, words.dropFirst()) { #expect(first != second) }
    }

    @Test func commonWordListIsCleanAndUnique() {
        #expect(WordList.common.count >= 200)
        #expect(Set(WordList.common).count == WordList.common.count)
        #expect(WordList.common.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isLetter) })
    }
}
