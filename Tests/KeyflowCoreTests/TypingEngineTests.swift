import Testing
@testable import KeyflowCore

/// Types `text` one character every `interval` seconds, starting at `start`.
/// Returns the timestamp of the last keystroke.
@discardableResult
func type(_ text: String, into engine: inout TypingEngine, from start: MonotonicTime = 100, every interval: Double = 0.1) -> MonotonicTime {
    var time = start
    for (offset, character) in text.enumerated() {
        time = start + Double(offset) * interval
        engine.insert(character, at: time)
    }
    return time
}

@Suite struct TimerTransitionTests {
    @Test func startsIdleAndRunsOnFirstCharacter() {
        var engine = TypingEngine(target: "hello world", configuration: .init(timeLimit: 30))
        #expect(engine.phase == .idle)
        #expect(engine.elapsed(at: 500) == 0)

        engine.insert("h", at: 100)
        #expect(engine.phase == .running)
        #expect(engine.startTime == 100)
        #expect(engine.events.first?.time == 0)
    }

    @Test func tickBeforeLimitKeepsRunning() {
        var engine = TypingEngine(target: "hello world", configuration: .init(timeLimit: 30))
        engine.insert("h", at: 100)
        engine.tick(at: 129.99)
        #expect(engine.phase == .running)
        #expect(engine.remaining(at: 110) == 20)
    }

    @Test func tickAtLimitFinishesExactlyAtLimit() {
        var engine = TypingEngine(target: "hello world", configuration: .init(timeLimit: 30))
        engine.insert("h", at: 100)
        engine.tick(at: 130.4)
        #expect(engine.phase == .finished)
        #expect(engine.endTime == 130)
        #expect(engine.endedByTimeLimit)
        #expect(engine.elapsed(at: 999) == 30)
        #expect(engine.remaining(at: 999) == 0)
    }

    @Test func elapsedIsExactlyTheLimitWhateverTheStartTime() {
        // 1000.05 + 30 - 1000.05 is not exactly 30 in floating point.
        for start in [1_000.05, 73_411.337, 0.1, 918_273.6451] {
            var engine = TypingEngine(target: "hello world", configuration: .init(timeLimit: 30))
            engine.insert("h", at: start)
            engine.tick(at: start + 45)
            #expect(engine.elapsed(at: start + 500) == 30)
            #expect(engine.session(at: start + 500).elapsed == 30)
            #expect(engine.remaining(at: start + 500) == 0)
        }
    }

    @Test func finishingTheTextIsNotATimeLimitEnding() {
        var engine = TypingEngine(target: "hi", configuration: .init(timeLimit: 30))
        engine.insert("h", at: 10)
        engine.insert("i", at: 12.5)
        #expect(engine.phase == .finished)
        #expect(!engine.endedByTimeLimit)
        #expect(engine.elapsed(at: 99) == 2.5)
    }

    @Test func tickWhileIdleDoesNothing() {
        var engine = TypingEngine(target: "hello", configuration: .init(timeLimit: 30))
        engine.tick(at: 1_000)
        #expect(engine.phase == .idle)
    }

    @Test func keystrokeAfterLimitIsRejectedAndEndsSession() {
        var engine = TypingEngine(target: "hello world", configuration: .init(timeLimit: 30))
        engine.insert("h", at: 100)
        let accepted = engine.insert("e", at: 130)
        #expect(!accepted)
        #expect(engine.phase == .finished)
        #expect(engine.typed == ["h"])
        #expect(engine.elapsed(at: 200) == 30)
    }

    @Test func backspaceAfterLimitIsRejected() {
        var engine = TypingEngine(target: "hello world", configuration: .init(timeLimit: 30))
        type("he", into: &engine)
        do { let accepted = engine.backspace(at: 131); #expect(!accepted) }
        #expect(engine.phase == .finished)
        #expect(engine.typed == ["h", "e"])
    }

    @Test func finishesWhenTextIsCompleted() {
        var engine = TypingEngine(target: "hi", configuration: .init(timeLimit: nil))
        engine.insert("h", at: 10)
        engine.insert("i", at: 12)
        #expect(engine.phase == .finished)
        #expect(engine.elapsed(at: 50) == 2)
        #expect(engine.remaining(at: 50) == nil)
    }

    @Test func doesNotFinishAtEndOfTextWhenDisabled() {
        var engine = TypingEngine(target: "hi", configuration: .init(timeLimit: 30, finishesAtEndOfText: false))
        type("hi", into: &engine)
        #expect(engine.phase == .running)
        do { let accepted = engine.insert("x", at: 105); #expect(!accepted) }

        engine.appendTarget(" there")
        do { let accepted = engine.insert(" ", at: 106); #expect(accepted) }
        #expect(engine.position == 3)
    }

    @Test func inputIsIgnoredOnceFinished() {
        var engine = TypingEngine(target: "hi")
        type("hi", into: &engine)
        let events = engine.events
        do { let accepted = engine.insert("x", at: 200); #expect(!accepted) }
        do { let accepted = engine.backspace(at: 201); #expect(!accepted) }
        engine.appendTarget(" more")
        #expect(engine.events == events)
        #expect(engine.target == ["h", "i"])
    }
}

@Suite struct BackspaceTests {
    @Test func backspaceDoesNotStartASession() {
        var engine = TypingEngine(target: "hello")
        do { let accepted = engine.backspace(at: 100); #expect(!accepted) }
        #expect(engine.phase == .idle)
        #expect(engine.events.isEmpty)
    }

    @Test func backspaceRemovesLastCharacterAndIsLogged() {
        var engine = TypingEngine(target: "hello")
        type("hx", into: &engine)
        do { let accepted = engine.backspace(at: 100.5); #expect(accepted) }
        #expect(engine.typed == ["h"])
        #expect(engine.position == 1)

        let event = engine.events.last
        #expect(event?.kind == .backspace)
        #expect(event?.position == 1)
        #expect(event?.expected == "e")
        #expect(event?.typed == "x")
        #expect(event?.time == 0.5)
    }

    @Test func backspaceOnEmptyBufferIsANoOp() {
        var engine = TypingEngine(target: "hello")
        engine.insert("h", at: 100)
        do { let accepted = engine.backspace(at: 101); #expect(accepted) }
        do { let accepted = engine.backspace(at: 102); #expect(!accepted) }
        #expect(engine.typed.isEmpty)
        #expect(engine.phase == .running)
        #expect(engine.events.count == 2)
    }

    @Test func deleteWordRemovesBackToWordStart() {
        var engine = TypingEngine(target: "the quick brown")
        type("the quick", into: &engine)
        do { let removed = engine.deleteWord(at: 105); #expect(removed == 5) }
        #expect(String(engine.typed) == "the ")

        // With trailing spaces, removes the spaces and the word before them.
        do { let removed = engine.deleteWord(at: 106); #expect(removed == 4) }
        #expect(engine.typed.isEmpty)
        do { let removed = engine.deleteWord(at: 107); #expect(removed == 0) }
    }

    @Test func correctedMistakeStillCountsAgainstAccuracy() {
        var engine = TypingEngine(target: "cat")
        engine.insert("c", at: 100)
        engine.insert("x", at: 101)   // wrong
        engine.backspace(at: 102)
        engine.insert("a", at: 103)
        engine.insert("t", at: 104)

        let metrics = PerformanceCalculator.metrics(for: engine.session(at: 104))
        #expect(metrics.totalKeystrokes == 4)
        #expect(metrics.correctKeystrokes == 3)
        #expect(metrics.incorrectKeystrokes == 1)
        #expect(metrics.backspaces == 1)
        #expect(metrics.accuracy == 0.75)
        #expect(metrics.correctCharacters == 3)
        #expect(metrics.incorrectCharacters == 0)
    }
}
