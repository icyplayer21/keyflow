import Testing
@testable import KeyflowCore

@Suite struct WPMTests {
    @Test func fiveCharactersIsOneWord() {
        #expect(PerformanceCalculator.wpm(characters: 250, elapsed: 60) == 50)
        #expect(PerformanceCalculator.wpm(characters: 100, elapsed: 30) == 40)
        #expect(PerformanceCalculator.wpm(characters: 5, elapsed: 1) == 60)
    }

    @Test func zeroTimeOrZeroCharactersIsZero() {
        #expect(PerformanceCalculator.wpm(characters: 100, elapsed: 0) == 0)
        #expect(PerformanceCalculator.wpm(characters: 0, elapsed: 60) == 0)
    }

    @Test func netCountsOnlyCorrectCharactersInFinalBuffer() {
        // 100 characters of target; type 60 in a 30 s session, 6 of them wrong.
        let target = String(repeating: "abcde ", count: 20)
        var engine = TypingEngine(target: target, configuration: .init(timeLimit: 30))
        var typed = Array(target.prefix(60))
        for index in stride(from: 0, to: 60, by: 10) { typed[index] = "#" }
        type(String(typed), into: &engine, every: 0.25)
        engine.tick(at: 200)

        let metrics = PerformanceCalculator.metrics(for: engine.session(at: 200))
        #expect(metrics.elapsed == 30)
        #expect(metrics.correctCharacters == 54)
        #expect(metrics.incorrectCharacters == 6)
        #expect(metrics.rawWPM == 24)           // 60 / 5 / 0.5 min
        #expect(metrics.netWPM == 21.6)         // 54 / 5 / 0.5 min
    }

    @Test func deletedCharactersCountTowardRawButNotNet() {
        var engine = TypingEngine(target: String(repeating: "a", count: 50), configuration: .init(timeLimit: 60))
        type(String(repeating: "a", count: 20), into: &engine)
        for step in 0..<10 { engine.backspace(at: 110 + Double(step)) }
        engine.tick(at: 1_000)

        let metrics = PerformanceCalculator.metrics(for: engine.session(at: 1_000))
        #expect(metrics.rawWPM == 4)    // 20 keystrokes / 5 / 1 min
        #expect(metrics.netWPM == 2)    // 10 remaining / 5 / 1 min
        #expect(metrics.backspaces == 10)
    }

    @Test func liveSnapshotUsesElapsedSoFar() {
        var engine = TypingEngine(target: String(repeating: "a", count: 100), configuration: .init(timeLimit: 60))
        type(String(repeating: "a", count: 25), into: &engine, from: 100, every: 0.1)
        let metrics = PerformanceCalculator.metrics(for: engine.session(at: 106))
        #expect(metrics.elapsed == 6)
        #expect(metrics.netWPM == 50)   // 25 / 5 / 0.1 min
    }
}

@Suite struct AccuracyTests {
    @Test func accuracyIsCorrectOverTotalKeystrokes() {
        var engine = TypingEngine(target: "abcdefghij")
        type("abXdefgYij", into: &engine)
        let metrics = PerformanceCalculator.metrics(for: engine.session(at: 200))
        #expect(metrics.accuracy == 0.8)
        #expect(metrics.incorrectKeystrokes == 2)
    }

    @Test func noKeystrokesIsFullAccuracyAndZeroWPM() {
        let engine = TypingEngine(target: "abc")
        let metrics = PerformanceCalculator.metrics(for: engine.session(at: 10))
        #expect(metrics.accuracy == 1)
        #expect(metrics.netWPM == 0)
        #expect(metrics.rawWPM == 0)
        #expect(metrics.totalKeystrokes == 0)
    }

    @Test func caseAndSpacesAreSignificant() {
        var engine = TypingEngine(target: "A b")
        type("a_b", into: &engine)
        let metrics = PerformanceCalculator.metrics(for: engine.session(at: 200))
        #expect(metrics.correctKeystrokes == 1)
        #expect(metrics.correctCharacters == 1)
    }

    @Test func retypingAfterBackspaceCountsEveryAttempt() {
        var engine = TypingEngine(target: "abc")
        engine.insert("a", at: 1)
        for attempt in 0..<3 {
            engine.insert("x", at: 2 + Double(attempt))
            engine.backspace(at: 2.5 + Double(attempt))
        }
        engine.insert("b", at: 6)
        let metrics = PerformanceCalculator.metrics(for: engine.session(at: 6))
        #expect(metrics.totalKeystrokes == 5)
        #expect(metrics.accuracy == 0.4)
        #expect(metrics.incorrectCharacters == 0)
    }
}
