import Foundation
import Testing
@testable import KeyflowCore

// MARK: Builders

func keyStat(_ character: Character, attempts: Int, errors: Int = 0, latencies: [Double] = []) -> KeyStat {
    KeyStat(character: character, attempts: attempts, errors: errors, latencySamples: latencies.count,
            latencyTotal: latencies.reduce(0, +), latencySquares: latencies.reduce(0) { $0 + $1 * $1 })
}

func pairStat(_ pair: String, attempts: Int, errors: Int = 0, latencies: [Double] = []) -> BigramStat {
    BigramStat(bigram: pair, attempts: attempts, errors: errors, samples: latencies.count,
               total: latencies.reduce(0, +), squares: latencies.reduce(0) { $0 + $1 * $1 })
}

func analysisOf(keys: [KeyStat] = [], bigrams: [BigramStat] = [], transitions: [BigramStat] = [],
                words: [WordStat] = []) -> SessionAnalysis {
    SessionAnalysis(consistency: nil, errorsPerMinute: 0, wpmTimeline: [], meanLatency: nil, medianLatency: nil,
                    keys: keys, bigrams: bigrams, transitions: transitions, words: words)
}

private func profile(keys: [KeyStat] = [], bigrams: [BigramStat] = [], transitions: [BigramStat] = [],
                     words: [WordStat] = []) -> TypingProfile {
    TypingProfile([analysisOf(keys: keys, bigrams: bigrams, transitions: transitions, words: words)])
}

/// 1000 keystrokes of "a": 1% errors, 100 ms each. A plain, ample baseline.
private let steadyA = keyStat("a", attempts: 1_000, errors: 10, latencies: Array(repeating: 0.1, count: 500))

@Suite struct WeaknessEvidenceTests {
    @Test func nothingIsReportedBelowTheOverallKeystrokeMinimum() {
        let report = WeaknessAnalyzer.analyze(profile(keys: [
            keyStat("a", attempts: 549, errors: 5),
            keyStat("q", attempts: 50, errors: 25, latencies: Array(repeating: 0.9, count: 40)),
        ]))
        #expect(report.keystrokes == 599)
        #expect(!report.hasEnoughData)
        #expect(report.accuracy.isEmpty && report.speed.isEmpty)
    }

    @Test func emptyProfileHasNotEnoughData() {
        let report = WeaknessAnalyzer.analyze(TypingProfile())
        #expect(!report.hasEnoughData)
        #expect(report.keystrokes == 0)
        #expect(report.keystrokesNeeded == 600)
        #expect(report.all.isEmpty)
    }

    @Test func aSingleIsolatedMistakeIsNeverAWeakness() {
        // 1 error in 40 is 2.5%, well above the 1% baseline, but it is one mistake.
        let report = WeaknessAnalyzer.analyze(profile(keys: [steadyA, keyStat("q", attempts: 40, errors: 1)]))
        #expect(report.hasEnoughData)
        #expect(report.accuracy.isEmpty)
    }

    @Test func twoMistakesAreStillNotEnough() {
        let report = WeaknessAnalyzer.analyze(profile(keys: [steadyA, keyStat("q", attempts: 40, errors: 2)]))
        #expect(report.accuracy.isEmpty)
    }

    @Test func aHighErrorRateOnTooFewAttemptsIsNotReported() {
        let report = WeaknessAnalyzer.analyze(profile(keys: [steadyA, keyStat("q", attempts: 29, errors: 15)]))
        #expect(report.accuracy.isEmpty)
    }

    @Test func aClearRepeatedProblemIsConfirmed() throws {
        let report = WeaknessAnalyzer.analyze(profile(keys: [steadyA, keyStat("q", attempts: 40, errors: 8)]))
        let weakness = try #require(report.accuracy.first)
        #expect(report.accuracy.count == 1)
        #expect(weakness.category == .key)
        #expect(weakness.dimension == .accuracy)
        #expect(weakness.item == "q")
        #expect(weakness.samples == 40)
        #expect(weakness.errors == 8)
        #expect(weakness.value == 0.2)
        #expect(weakness.baseline == 18.0 / 1_040.0)        // the user's own overall error rate
        #expect(weakness.severity > 10)
        #expect(weakness.id == "accuracy.key.q")
        #expect(report.speed.isEmpty)
    }

    @Test func worseThanBaselineButPlausiblyChanceIsNotReported() {
        // 4 errors in 30 (13%) against an 8% baseline: above the ratio, but the
        // Wilson lower bound (about 4%) does not clear the baseline.
        let noisyA = keyStat("a", attempts: 10_000, errors: 800)
        let report = WeaknessAnalyzer.analyze(profile(keys: [noisyA, keyStat("q", attempts: 30, errors: 4)]))
        #expect(report.accuracy.isEmpty)

        // The same rate with twenty times the evidence is confirmed.
        let confirmed = WeaknessAnalyzer.analyze(profile(keys: [noisyA, keyStat("q", attempts: 600, errors: 80)]))
        #expect(confirmed.accuracy.map(\.item) == ["q"])
    }

    @Test func slightlyWorseThanBaselineIsNotMeaningful() {
        // 1.2x the baseline with overwhelming evidence still fails the ratio test.
        let report = WeaknessAnalyzer.analyze(profile(keys: [
            keyStat("a", attempts: 100_000, errors: 5_000),
            keyStat("q", attempts: 50_000, errors: 3_000),
        ]))
        #expect(report.accuracy.isEmpty)
    }

    @Test func wilsonLowerBoundMatchesKnownValues() {
        #expect(WeaknessAnalyzer.wilsonLowerBound(errors: 0, attempts: 50, z: 1.96) == 0)
        #expect(WeaknessAnalyzer.wilsonLowerBound(errors: 0, attempts: 0, z: 1.96) == 0)
        #expect(abs(WeaknessAnalyzer.wilsonLowerBound(errors: 5, attempts: 10, z: 1.96) - 0.2366) < 0.0005)
        #expect(abs(WeaknessAnalyzer.wilsonLowerBound(errors: 50, attempts: 100, z: 1.96) - 0.4038) < 0.0005)
        // More evidence at the same rate tightens the bound.
        let small = WeaknessAnalyzer.wilsonLowerBound(errors: 3, attempts: 30, z: 1.645)
        let large = WeaknessAnalyzer.wilsonLowerBound(errors: 30, attempts: 300, z: 1.645)
        #expect(small < large && large < 0.1)
    }
}

@Suite struct SpeedWeaknessTests {
    @Test func aReliablySlowKeyIsASpeedWeaknessOnly() throws {
        let report = WeaknessAnalyzer.analyze(profile(keys: [
            steadyA, keyStat("z", attempts: 25, latencies: Array(repeating: 0.2, count: 25)),
        ]))
        let weakness = try #require(report.speed.first)
        #expect(report.speed.count == 1)
        #expect(weakness.item == "z")
        #expect(weakness.dimension == .speed)
        #expect(abs(weakness.value - 0.2) < 1e-12)
        #expect(abs(weakness.baseline - 55.0 / 525.0) < 1e-12)       // mean latency over all keys
        #expect(weakness.errors == 0)
        #expect(report.accuracy.isEmpty)
    }

    @Test func tooFewTimedSamplesIsNotReported() {
        let report = WeaknessAnalyzer.analyze(profile(keys: [
            steadyA, keyStat("z", attempts: 19, latencies: Array(repeating: 0.9, count: 19)),
        ]))
        #expect(report.speed.isEmpty)
    }

    @Test func aSlowAverageFromErraticTimingIsNotReported() {
        // Mean 160 ms against ~102 ms, but half the presses are instant and
        // half very slow: the gap is within the required standard errors.
        let erratic = Array(repeating: 0.0, count: 10) + Array(repeating: 0.32, count: 10)
        let report = WeaknessAnalyzer.analyze(profile(keys: [steadyA, keyStat("z", attempts: 20, latencies: erratic)]))
        #expect(report.speed.isEmpty)

        // The same mean, typed steadily, is confirmed.
        let steady = Array(repeating: 0.16, count: 20)
        let confirmed = WeaknessAnalyzer.analyze(profile(keys: [steadyA, keyStat("z", attempts: 20, latencies: steady)]))
        #expect(confirmed.speed.map(\.item) == ["z"])
    }

    @Test func onlySlightlySlowIsNotMeaningful() {
        let report = WeaknessAnalyzer.analyze(profile(keys: [
            steadyA, keyStat("z", attempts: 200, latencies: Array(repeating: 0.115, count: 200)),
        ]))
        #expect(report.speed.isEmpty)
    }

    @Test func accuracyAndSpeedAreJudgedSeparately() {
        let report = WeaknessAnalyzer.analyze(profile(keys: [
            steadyA,
            keyStat("q", attempts: 40, errors: 10, latencies: Array(repeating: 0.1, count: 30)),   // inaccurate, normal speed
            keyStat("z", attempts: 40, errors: 0, latencies: Array(repeating: 0.25, count: 40)),   // accurate, slow
            keyStat("x", attempts: 40, errors: 10, latencies: Array(repeating: 0.25, count: 30)),  // both
        ]))
        #expect(Set(report.accuracy.map(\.item)) == ["q", "x"])
        #expect(Set(report.speed.map(\.item)) == ["z", "x"])
        #expect(report.accuracy.allSatisfy { $0.dimension == .accuracy })
        #expect(report.speed.allSatisfy { $0.dimension == .speed })
    }
}

@Suite struct WeaknessCategoryTests {
    private let fastPairs = pairStat("an", attempts: 400, errors: 4, latencies: Array(repeating: 0.1, count: 400))

    @Test func letterCombinationsAreJudgedAgainstOtherCombinations() {
        let report = WeaknessAnalyzer.analyze(profile(
            keys: [steadyA],
            bigrams: [
                fastPairs,
                pairStat("th", attempts: 20, errors: 0, latencies: Array(repeating: 0.22, count: 20)),
                pairStat("ie", attempts: 20, errors: 6, latencies: Array(repeating: 0.1, count: 14)),
                pairStat("qu", attempts: 11, errors: 9, latencies: Array(repeating: 0.5, count: 2)),       // too rare
            ]))
        #expect(report.speed.map(\.id) == ["speed.combination.th"])
        #expect(report.accuracy.map(\.id) == ["accuracy.combination.ie"])
        #expect(abs((report.accuracy.first?.baseline ?? 0) - 19.0 / 451.0) < 1e-12)
    }

    @Test func transitionsAreSpeedOnly() {
        let report = WeaknessAnalyzer.analyze(profile(
            keys: [steadyA],
            transitions: [
                pairStat("e ", attempts: 300, errors: 3, latencies: Array(repeating: 0.1, count: 300)),
                pairStat(", ", attempts: 30, errors: 20, latencies: Array(repeating: 0.3, count: 10)),
            ]))
        #expect(report.speed.map(\.id) == ["speed.transition., "])
        #expect(report.speed.first?.category == .transition)
        #expect(report.accuracy.isEmpty)                    // errors on transitions are not reported
    }

    @Test func wordsNeedRepeatedMistakesAcrossSeveralAttempts() {
        let common = WordStat(word: "the", attempts: 300, mistakes: 6)
        func accuracyItems(_ word: WordStat) -> [String] {
            WeaknessAnalyzer.analyze(profile(keys: [steadyA], words: [common, word])).accuracy.map(\.item)
        }
        #expect(accuracyItems(WordStat(word: "their", attempts: 6, mistakes: 4)) == ["their"])
        #expect(accuracyItems(WordStat(word: "their", attempts: 5, mistakes: 5)).isEmpty)      // too few attempts
        #expect(accuracyItems(WordStat(word: "their", attempts: 9, mistakes: 2)).isEmpty)      // too few mistakes
        #expect(accuracyItems(common).isEmpty)                                                 // the baseline itself
    }

    @Test func aWeakKeyIsReportedOnceNotAsEveryPairAndWordContainingIt() {
        // Every "v" is a coin flip, whatever precedes it.
        let report = WeaknessAnalyzer.analyze(profile(
            keys: [steadyA, keyStat("v", attempts: 160, errors: 80), keyStat("e", attempts: 400, errors: 4)],
            bigrams: [
                fastPairs,
                pairStat("ev", attempts: 60, errors: 31), pairStat("av", attempts: 50, errors: 24),
                pairStat("iv", attempts: 50, errors: 25),
            ],
            words: [
                WordStat(word: "the", attempts: 300, mistakes: 6),
                WordStat(word: "every", attempts: 12, mistakes: 7),
                WordStat(word: "their", attempts: 12, mistakes: 7),
            ]))
        #expect(Set(report.accuracy.map(\.id)) == ["accuracy.key.v", "accuracy.word.their"])
    }

    @Test func aPairWorseThanItsKeyIsThePairsProblemNotTheKeys() {
        // "e" is fine (2.5% wrong) except straight after "i" (40% wrong).
        let report = WeaknessAnalyzer.analyze(profile(
            keys: [steadyA, keyStat("e", attempts: 200, errors: 20)],
            bigrams: [fastPairs, pairStat("ie", attempts: 40, errors: 16), pairStat("he", attempts: 160, errors: 4)],
            words: [WordStat(word: "the", attempts: 300, mistakes: 6), WordStat(word: "field", attempts: 10, mistakes: 6)]))
        #expect(report.accuracy.map(\.id) == ["accuracy.combination.ie"])       // not key "e", not word "field"
        #expect(report.accuracy.first?.baseline == 24.0 / 600.0)                // all pairs; "e" elsewhere is lower still
    }

    @Test func aSlowPairDoesNotMakeItsKeySlow() {
        // "h" takes 240 ms after "t" and 100 ms otherwise.
        let afterT = Array(repeating: 0.24, count: 60), otherwise = Array(repeating: 0.1, count: 40)
        let report = WeaknessAnalyzer.analyze(profile(
            keys: [steadyA, keyStat("h", attempts: 100, latencies: afterT + otherwise)],
            bigrams: [fastPairs, pairStat("th", attempts: 60, latencies: afterT), pairStat("ch", attempts: 40, latencies: otherwise)]))
        #expect(report.speed.map(\.id) == ["speed.combination.th"])

        // Without the pair data the key itself is the finding.
        let keyOnly = WeaknessAnalyzer.analyze(profile(keys: [steadyA, keyStat("h", attempts: 100, latencies: afterT + otherwise)]))
        #expect(keyOnly.speed.map(\.id) == ["speed.key.h"])
    }

    @Test func aKeySlowEverywhereStaysAKeyFinding() {
        let slow = Array(repeating: 0.25, count: 30)
        let report = WeaknessAnalyzer.analyze(profile(
            keys: [steadyA, keyStat("z", attempts: 60, latencies: slow + slow)],
            bigrams: [fastPairs, pairStat("az", attempts: 30, latencies: slow), pairStat("iz", attempts: 30, latencies: slow)]))
        #expect(report.speed.map(\.id) == ["speed.key.z"])
    }

    @Test func mostSevereComeFirst() {
        let report = WeaknessAnalyzer.analyze(profile(keys: [
            steadyA,
            keyStat("q", attempts: 50, errors: 10),
            keyStat("x", attempts: 50, errors: 30),
            keyStat("j", attempts: 50, errors: 20),
        ]))
        #expect(report.accuracy.map(\.item) == ["x", "j", "q"])
        #expect(report.accuracy.map(\.severity) == report.accuracy.map(\.severity).sorted(by: >))
    }

    @Test func thresholdsCanBeTightened() {
        var strict = WeaknessAnalyzer.Thresholds()
        strict.keyAttempts = 100
        let keys = [steadyA, keyStat("q", attempts: 40, errors: 8)]
        #expect(WeaknessAnalyzer.analyze(profile(keys: keys)).accuracy.count == 1)
        #expect(WeaknessAnalyzer.analyze(profile(keys: keys), thresholds: strict).accuracy.isEmpty)
    }
}

@Suite struct TypingProfileTests {
    @Test func sessionsAreSummed() {
        let first = analysisOf(
            keys: [keyStat("a", attempts: 10, errors: 1, latencies: [0.1, 0.3])],
            bigrams: [pairStat("th", attempts: 4, errors: 1, latencies: [0.2])],
            transitions: [pairStat("e ", attempts: 3, latencies: [0.1])],
            words: [WordStat(word: "the", attempts: 2, mistakes: 1)])
        let second = analysisOf(
            keys: [keyStat("a", attempts: 30, errors: 3, latencies: [0.2]), keyStat("b", attempts: 10)],
            bigrams: [pairStat("th", attempts: 6, errors: 0, latencies: [0.4])],
            words: [WordStat(word: "the", attempts: 3, mistakes: 0), WordStat(word: "cat", attempts: 5, mistakes: 1)])

        var profile = TypingProfile([first])
        profile.add(second)

        #expect(profile.sessions == 2)
        #expect(profile.keystrokes == 50)
        #expect(profile.keys["a"]?.attempts == 40)
        #expect(profile.keys["a"]?.errors == 4)
        #expect(abs((profile.keys["a"]?.meanLatency ?? 0) - 0.2) < 1e-12)
        #expect(profile.keyErrorRate == 0.08)
        #expect(abs((profile.meanKeyLatency ?? 0) - 0.2) < 1e-12)
        #expect(profile.bigrams["th"]?.attempts == 10)
        #expect(profile.bigramErrorRate == 0.1)
        #expect(abs((profile.meanBigramLatency ?? 0) - 0.3) < 1e-12)
        #expect(profile.meanTransitionLatency == 0.1)
        #expect(profile.words["the"] == WordStat(word: "the", attempts: 5, mistakes: 1))
        #expect(profile.wordMistakeRate == 0.2)
        #expect(profile == TypingProfile([first, second]))
    }

    @Test func emptyProfileHasNoBaselines() {
        let profile = TypingProfile()
        #expect(profile.keyErrorRate == nil)
        #expect(profile.meanKeyLatency == nil)
        #expect(profile.bigramErrorRate == nil)
        #expect(profile.meanBigramLatency == nil)
        #expect(profile.wordMistakeRate == nil)
    }
}

@Suite struct PairAnalysisTests {
    @Test func pairsWithSpacesDigitsOrSymbolsAreTransitions() {
        var engine = TypingEngine(target: "an 7, on")
        type("an 7, on", into: &engine, from: 0, every: 0.25)
        let analysis = SessionAnalyzer.analyze(engine.session(at: 10))

        #expect(analysis.bigrams.map(\.bigram) == ["an", "on"])
        #expect(analysis.transitions.map(\.bigram) == [" 7", " o", ", ", "7,", "n "])
        #expect(analysis.transitions.allSatisfy { $0.attempts == 1 && $0.samples == 1 && $0.meanLatency == 0.25 })
    }

    @Test func pairAccuracyCountsEveryAttemptAtTheSecondCharacter() {
        var engine = TypingEngine(target: "the then go")
        type("thx thxn", into: &engine)
        engine.backspace(at: 300)
        engine.backspace(at: 301)
        engine.insert("e", at: 302)
        let analysis = SessionAnalyzer.analyze(engine.session(at: 302))

        let he = analysis.bigrams.first { $0.bigram == "he" }
        #expect(he?.attempts == 3)          // twice at first, once after the correction
        #expect(he?.errors == 2)
        #expect(he?.samples == 0)           // the correct one followed a Backspace
        #expect(analysis.bigrams.first { $0.bigram == "th" }?.errors == 0)
        #expect(analysis.words.map(\.word) == ["the", "then"])
        #expect(analysis.mistypedWords.count == 2)
    }

    @Test func untouchedWordsAreNotCounted() {
        var engine = TypingEngine(target: "one two three")
        type("one t", into: &engine)
        let words = SessionAnalyzer.analyze(engine.session(at: 200)).words
        #expect(words == [WordStat(word: "one", attempts: 1, mistakes: 0), WordStat(word: "two", attempts: 1, mistakes: 0)])
    }
}
