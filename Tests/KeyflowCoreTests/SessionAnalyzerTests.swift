import Testing
@testable import KeyflowCore

/// A session where every character of `target` is typed correctly at the given times.
private func session(_ target: String, times: [Double], elapsed: Double) -> TypingSession {
    let characters = Array(target)
    let events = zip(characters.indices, times).map { index, time in
        TypingEvent(kind: .insert, time: time, position: index, expected: characters[index], typed: characters[index])
    }
    return TypingSession(target: characters, typed: Array(characters.prefix(times.count)), events: events, elapsed: elapsed)
}

@Suite struct LatencyTests {
    @Test func latencyIsTheGapBetweenConsecutiveKeystrokes() {
        let analysis = SessionAnalyzer.analyze(session("abcd", times: [0, 0.25, 0.75, 1.5], elapsed: 1.5))
        #expect(analysis.meanLatency == 0.5)
        #expect(analysis.medianLatency == 0.5)
        #expect(analysis.keys.first { $0.character == "a" }?.latencySamples == 0)   // first key has no gap
        #expect(analysis.keys.first { $0.character == "b" }?.meanLatency == 0.25)
        #expect(analysis.keys.first { $0.character == "d" }?.meanLatency == 0.75)
    }

    @Test func medianOfAnEvenNumberOfGaps() {
        let analysis = SessionAnalyzer.analyze(session("abc", times: [0, 0.25, 1.0], elapsed: 1))
        #expect(analysis.medianLatency == 0.5)
    }

    @Test func pausesLongerThanTheThresholdAreNotSampled() {
        let analysis = SessionAnalyzer.analyze(session("abc", times: [0, 0.25, 4.0], elapsed: 4))
        #expect(analysis.meanLatency == 0.25)
        #expect(analysis.keys.first { $0.character == "c" }?.latencySamples == 0)
    }

    @Test func gapsAfterBackspaceAreNotSampled() {
        var engine = TypingEngine(target: "abc")
        engine.insert("a", at: 0)
        engine.insert("x", at: 0.25)      // wrong: sampled overall, not for the key
        engine.backspace(at: 0.5)
        engine.insert("b", at: 0.75)      // follows a backspace: not sampled
        engine.insert("c", at: 1.25)

        let analysis = SessionAnalyzer.analyze(engine.session(at: 1.25))
        #expect(analysis.meanLatency == 0.375)          // gaps 0.25 and 0.5
        let b = analysis.keys.first { $0.character == "b" }
        #expect(b?.attempts == 2)
        #expect(b?.errors == 1)
        #expect(b?.latencySamples == 0)
        #expect(analysis.keys.first { $0.character == "c" }?.meanLatency == 0.5)
    }

    @Test func emptySessionHasNoLatency() {
        let analysis = SessionAnalyzer.analyze(TypingEngine(target: "abc").session(at: 10))
        #expect(analysis.meanLatency == nil)
        #expect(analysis.medianLatency == nil)
        #expect(analysis.keys.isEmpty)
        #expect(analysis.errorsPerMinute == 0)
    }
}

@Suite struct BigramTests {
    @Test func pairsAreSampledWithinWordsOnlyAndIgnoreCase() {
        // "The the": T-h, h-e, (e-space, space-t skipped), t-h, h-e
        let analysis = SessionAnalyzer.analyze(
            session("The the", times: [0, 0.25, 0.5, 0.75, 1.0, 1.75, 2.0], elapsed: 2))
        #expect(analysis.bigrams.map(\.bigram) == ["he", "th"])
        let th = analysis.bigrams.first { $0.bigram == "th" }
        #expect(th?.samples == 2)
        #expect(th?.meanLatency == 0.5)      // 0.25 and 0.75
        #expect(analysis.bigrams.first { $0.bigram == "he" }?.meanLatency == 0.25)
    }

    @Test func pairsInvolvingAMistakeAreNotSampled() {
        var engine = TypingEngine(target: "then")
        type("txen", into: &engine)
        let analysis = SessionAnalyzer.analyze(engine.session(at: 200))
        #expect(analysis.bigrams.filter { $0.samples > 0 }.map(\.bigram) == ["en"])
        // Accuracy is tracked for every pair, whatever came before it.
        #expect(analysis.bigrams.first { $0.bigram == "th" }?.errors == 1)
        #expect(analysis.bigrams.first { $0.bigram == "he" }?.attempts == 1)
        #expect(analysis.bigrams.first { $0.bigram == "he" }?.errors == 0)
    }

    @Test func slowestBigramsNeedRepeatSamplesAndMustBeatTheAverage() {
        // th: 0.5, 0.5 (slow, repeated)   he: 0.25, 0.25 (fast)   xy: 0.75 (slow, seen once)
        let analysis = SessionAnalyzer.analyze(session(
            "the the xy",
            times: [0, 0.5, 0.75, 1.0, 1.25, 1.75, 2.0, 2.25, 2.5, 3.25],
            elapsed: 3.25))
        #expect(analysis.slowestBigrams().map(\.bigram) == ["th"])
        #expect(analysis.slowestBigrams(minimumSamples: 1).map(\.bigram) == ["xy", "th"])
    }

    @Test func noBigramsMeansNoFindings() {
        let analysis = SessionAnalyzer.analyze(session("a", times: [0], elapsed: 1))
        #expect(analysis.meanBigramLatency == nil)
        #expect(analysis.slowestBigrams().isEmpty)
        #expect(analysis.slowestKeys().isEmpty)
    }
}

@Suite struct ConsistencyTests {
    private func steady(perSecond: [Int]) -> TypingSession {
        var times: [Double] = []
        for (second, count) in perSecond.enumerated() {
            for index in 0..<count { times.append(Double(second) + (Double(index) + 0.5) / Double(count + 1)) }
        }
        return session(String(repeating: "a", count: times.count), times: times, elapsed: Double(perSecond.count))
    }

    @Test func perfectlyEvenPaceIsFullyConsistent() {
        let analysis = SessionAnalyzer.analyze(steady(perSecond: [5, 5, 5, 5]))
        #expect(analysis.consistency == 1)
        #expect(analysis.wpmTimeline == [60, 60, 60, 60])
    }

    @Test func consistencyIsOneMinusCoefficientOfVariation() {
        // Counts 8, 4, 8, 4: mean 6, standard deviation 2, so 1 - 2/6.
        let value = SessionAnalyzer.consistency(of: steady(perSecond: [8, 4, 8, 4]))
        #expect(abs((value ?? 0) - (1 - 2.0 / 6.0)) < 1e-12)
    }

    @Test func wildlyUnevenPaceFloorsAtZero() {
        #expect(SessionAnalyzer.consistency(of: steady(perSecond: [20, 0, 0, 0, 0, 0])) == 0)
    }

    @Test func sessionsShorterThanThreeSecondsAreNotJudged() {
        #expect(SessionAnalyzer.consistency(of: steady(perSecond: [5, 5])) == nil)
        #expect(SessionAnalyzer.consistency(of: steady(perSecond: [5, 5, 5])) != nil)
    }

    @Test func partialFinalSecondIsIgnored() {
        let partial = session("aaaaaa", times: [0.1, 0.5, 1.1, 1.5, 2.1, 2.5], elapsed: 3.9)
        #expect(SessionAnalyzer.wpmTimeline(of: partial) == [24, 24, 24])
    }
}

@Suite struct MistypedWordTests {
    @Test func wordsWithAnyWrongKeystrokeAreCounted() {
        var engine = TypingEngine(target: "the cat sat the mat on it")
        type("the cxt sat thx mat", into: &engine)
        let analysis = SessionAnalyzer.analyze(engine.session(at: 200))

        #expect(analysis.mistypedWords.map(\.word) == ["cat", "the"])
        #expect(analysis.mistypedWords.first { $0.word == "the" } == WordStat(word: "the", attempts: 2, mistakes: 1))
        #expect(analysis.mistypedWords.first { $0.word == "cat" }?.attempts == 1)
    }

    @Test func correctedMistakesStillCountOncePerOccurrence() {
        var engine = TypingEngine(target: "cat hat")
        engine.insert("c", at: 1)
        engine.insert("x", at: 2)
        engine.backspace(at: 3)
        engine.insert("z", at: 4)
        engine.backspace(at: 5)
        engine.insert("a", at: 6)
        engine.insert("t", at: 7)
        let analysis = SessionAnalyzer.analyze(engine.session(at: 7))
        #expect(analysis.mistypedWords == [WordStat(word: "cat", attempts: 1, mistakes: 1)])
    }

    @Test func punctuationAndCaseAreStrippedFromWords() {
        var engine = TypingEngine(target: "\"Wait,\" she said - don't!")
        type("\"Wxit,\" she said - dxn't!", into: &engine)
        let analysis = SessionAnalyzer.analyze(engine.session(at: 200))
        #expect(analysis.mistypedWords.map(\.word) == ["don't", "wait"])
    }

    @Test func errorsOnSpacesAndNumbersAreNotWords() {
        var engine = TypingEngine(target: "a 42 b")
        type("ax99xb", into: &engine)
        #expect(SessionAnalyzer.analyze(engine.session(at: 200)).mistypedWords.isEmpty)
    }

    @Test func mostFrequentlyMistypedComeFirst() {
        var engine = TypingEngine(target: "abc xyz xyz xyz")
        type("xbc xxz xyx xyz", into: &engine)
        let words = SessionAnalyzer.analyze(engine.session(at: 200)).mistypedWords
        #expect(words == [WordStat(word: "xyz", attempts: 3, mistakes: 2), WordStat(word: "abc", attempts: 1, mistakes: 1)])
    }
}

@Suite struct ErrorFrequencyTests {
    @Test func errorsPerMinuteUsesElapsedTime() {
        var engine = TypingEngine(target: String(repeating: "a", count: 40), configuration: .init(timeLimit: 30))
        type("aaxaaxaaxa", into: &engine)
        engine.tick(at: 1_000)
        let analysis = SessionAnalyzer.analyze(engine.session(at: 1_000))
        #expect(analysis.errorsPerMinute == 6)       // 3 errors in half a minute
    }

    @Test func mostMissedKeysRankByErrors() {
        var engine = TypingEngine(target: "aabbbcA")
        type("xxbxbcx", into: &engine)
        let missed = SessionAnalyzer.analyze(engine.session(at: 200)).mostMissedKeys()
        #expect(missed.map(\.character) == ["a", "b"])      // "A" folds into "a"
        #expect(missed.first?.errors == 3)
        #expect(missed.first?.attempts == 3)
        #expect(missed.last?.errorRate == 1.0 / 3.0)
    }

    @Test func slowestKeysNeedThreeSamplesAndMustBeatTheAverage() {
        // z is slow three times; q is slow only once; a is fast.
        let analysis = SessionAnalyzer.analyze(session(
            "azazazaqaa",
            times: [0, 1.0, 1.1, 2.1, 2.2, 3.2, 3.3, 4.3, 4.4, 4.5],
            elapsed: 4.5))
        #expect(analysis.slowestKeys().map(\.character) == ["z"])
    }
}
