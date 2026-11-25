import Foundation
import Testing
@testable import KeyflowCore

@Suite struct KeyRepetitionCounterTests {
    private func counter(_ letter: Character = "p", goal: Int = 50) -> KeyRepetitionCounter {
        KeyRepetitionCounter(letter: letter, goal: goal)!
    }

    @Test func everyLetterAToZIsAccepted() {
        #expect(KeyRepetitionCounter.letters.count == 26)
        for letter in KeyRepetitionCounter.letters {
            let lower = KeyRepetitionCounter(letter: letter, goal: 25)
            let upper = KeyRepetitionCounter(letter: Character(letter.uppercased()), goal: 25)
            #expect(lower?.letter == letter)
            #expect(upper?.letter == letter)
            // Every letter has a recommended finger on the QWERTY map.
            #expect(FingerMap.finger(for: letter)?.hand != nil, "no finger for \(letter)")
        }
    }

    @Test func nonLettersAreRejected() {
        for character: Character in ["1", " ", ";", "é", "ß", "\r"] {
            #expect(KeyRepetitionCounter(letter: character, goal: 25) == nil)
        }
    }

    @Test func presetsAndCustomGoalsAreKeptInRange() {
        #expect(KeyRepetitionCounter.presets == [25, 50, 100, 200])
        #expect(KeyRepetitionCounter.defaultGoal == 50)
        for preset in KeyRepetitionCounter.presets { #expect(counter(goal: preset).goal == preset) }
        #expect(counter(goal: 0).goal == 5)
        #expect(counter(goal: -20).goal == 5)
        #expect(counter(goal: 37).goal == 37)
        #expect(counter(goal: 10_000).goal == 500)
    }

    @Test func correctAndIncorrectPressesAreCountedSeparately() {
        var c = counter()
        #expect(c.press("p", isRepeat: false, at: 1) == .correct)
        #expect(c.press("o", isRepeat: false, at: 2) == .incorrect)
        #expect(c.press("p", isRepeat: false, at: 3) == .correct)
        #expect(c.press("1", isRepeat: false, at: 4) == .incorrect)
        #expect(c.correct == 2)
        #expect(c.incorrect == 2)
        #expect(c.remaining == 48)
        #expect(c.attempts == 4)
    }

    @Test func mistakesDoNotAdvanceProgress() {
        var c = counter(goal: 5)
        for t in 0..<20 { c.press("q", isRepeat: false, at: Double(t)) }
        #expect(c.correct == 0)
        #expect(c.remaining == 5)
        #expect(!c.isFinished)
    }

    @Test func autoRepeatIsNeverCounted() {
        var c = counter(goal: 5)
        #expect(c.press("p", isRepeat: false, at: 1) == .correct)
        // Holding the key: hundreds of repeats change nothing, right or wrong.
        for t in 0..<500 {
            #expect(c.press("p", isRepeat: true, at: 1 + Double(t) * 0.03) == .ignored)
            #expect(c.press("x", isRepeat: true, at: 1 + Double(t) * 0.03) == .ignored)
        }
        #expect(c.correct == 1)
        #expect(c.incorrect == 0)
        #expect(!c.isFinished)
    }

    @Test func rapidSeparatePressesEachCountOnce() {
        var c = counter(goal: 100)
        for i in 0..<100 { c.press("p", isRepeat: false, at: 10 + Double(i) * 0.02) }
        #expect(c.correct == 100)
        #expect(c.isFinished)
    }

    @Test func spaceIsIgnored() {
        var c = counter()
        #expect(c.press(" ", isRepeat: false, at: 1) == .ignored)
        #expect(c.attempts == 0)
        #expect(c.phase == .ready)
        #expect(c.startTime == nil)
    }

    @Test func upperCaseCountsAsTheSameKey() {
        var c = counter()
        #expect(c.press("P", isRepeat: false, at: 1) == .correct)
        #expect(c.press("p", isRepeat: false, at: 2) == .correct)
        #expect(c.press("O", isRepeat: false, at: 3) == .incorrect)
        #expect(c.correct == 2)
    }

    @Test func accuracyIsCorrectOverCountedAttempts() {
        var c = counter()
        #expect(c.accuracy == nil)
        for t in 0..<3 { c.press("p", isRepeat: false, at: Double(t)) }
        c.press("o", isRepeat: false, at: 5)
        c.press("p", isRepeat: true, at: 6)   // not counted
        c.press(" ", isRepeat: false, at: 7)  // not counted
        #expect(c.accuracy == 0.75)
        let result = c.result(mode: .continuous, at: 8)
        #expect(result.accuracy == 0.75)
        #expect(result.attempts == 4)
    }

    @Test func finishesExactlyAtTheGoal() {
        var c = counter(goal: 25)
        for t in 0..<24 { c.press("p", isRepeat: false, at: Double(t)) }
        #expect(!c.isFinished)
        #expect(c.remaining == 1)
        c.press("p", isRepeat: false, at: 24)
        #expect(c.isFinished)
        #expect(c.correct == 25)
        #expect(c.remaining == 0)
        // Nothing counts after the goal.
        #expect(c.press("p", isRepeat: false, at: 25) == .ignored)
        #expect(c.press("x", isRepeat: false, at: 26) == .ignored)
        #expect(c.correct == 25)
        #expect(c.incorrect == 0)
    }

    @Test func pressesWhilePausedAreIgnored() {
        var c = counter()
        c.press("p", isRepeat: false, at: 1)
        c.pause(at: 2)
        #expect(c.phase == .paused)
        #expect(c.press("p", isRepeat: false, at: 3) == .ignored)
        #expect(c.press("x", isRepeat: false, at: 3) == .ignored)
        c.resume(at: 4)
        #expect(c.phase == .running)
        #expect(c.press("p", isRepeat: false, at: 5) == .correct)
        #expect(c.correct == 2)
        #expect(c.incorrect == 0)
    }

    @Test func durationRunsFromFirstAttemptAndLeavesOutPauses() {
        var c = counter(goal: 5)
        // Time before the first press and a pause before it are not counted.
        c.pause(at: 0)
        c.resume(at: 50)
        #expect(c.duration(at: 60) == 0)
        c.press("p", isRepeat: false, at: 100)
        c.pause(at: 102)
        #expect(c.duration(at: 500) == 2)   // frozen while paused
        c.resume(at: 130)
        c.press("p", isRepeat: false, at: 131)
        c.press("p", isRepeat: false, at: 132)
        c.press("p", isRepeat: false, at: 133)
        #expect(!c.isFinished)
        c.press("p", isRepeat: false, at: 134)
        #expect(c.isFinished)
        // 100→134 is 34 s, minus 28 s paused.
        #expect(c.duration(at: 999) == 6)
        #expect(c.result(mode: .returnToHome, at: 999).duration == 6)
    }

    @Test func resultCarriesModeAndNoSpeed() throws {
        var c = counter("j", goal: 5)
        for t in 0..<5 { c.press("j", isRepeat: false, at: Double(t)) }
        let result = c.result(mode: .returnToHome, at: 10)
        #expect(result.letter == "j")
        #expect(result.mode == .returnToHome)
        let json = String(data: try JSONEncoder().encode(result), encoding: .utf8)!
        #expect(!json.lowercased().contains("wpm"))
    }
}

@Suite struct KeyRepetitionHistoryTests {
    private func event(_ letter: String, correct: Int, incorrect: Int, daysAgo: Double) -> KeyRepetitionEvent {
        KeyRepetitionEvent(date: Date(timeIntervalSinceReferenceDate: 1_000_000 - daysAgo * 86_400),
                           result: KeyRepetitionResult(letter: letter, goal: correct, correct: correct,
                                                       incorrect: incorrect, mode: .continuous, duration: 30))
    }

    @Test func totalsPerKeyMostRecentFirst() throws {
        let history = KeyRepetitionHistory(events: [
            event("p", correct: 50, incorrect: 10, daysAgo: 3),
            event("f", correct: 25, incorrect: 0, daysAgo: 2),
            event("p", correct: 50, incorrect: 0, daysAgo: 1),
        ])
        #expect(history.keys.map(\.letter) == ["p", "f"])
        let p = try #require(history.stats(for: "p"))
        #expect(p.sessions == 2)
        #expect(p.repetitions == 100)
        #expect(p.mistakes == 10)
        #expect(abs(p.accuracy - 100.0 / 110.0) < 1e-9)
        #expect(p.lastAccuracy == 1)
        #expect(history.stats(for: "z") == nil)
    }

    @Test func emptyHistory() {
        #expect(KeyRepetitionHistory(events: []).keys.isEmpty)
    }
}

@MainActor
@Suite struct KeyRepetitionStoreTests {
    @Test func savedSessionsRoundTripAndStaySeparate() throws {
        let store = try TrainingStore.inMemory()
        let result = KeyRepetitionResult(letter: "p", goal: 50, correct: 50, incorrect: 4,
                                         mode: .returnToHome, duration: 41.5)
        let event = KeyRepetitionEvent(date: Date(timeIntervalSinceReferenceDate: 800_000_000), result: result)
        try store.record(event)

        #expect(store.keyRepetitionEvents == [event])
        // Other Learn histories are untouched by it, and it is not read as one of them.
        #expect(store.events.isEmpty)
        #expect(store.fingerFocusEvents.isEmpty)
        #expect(store.assessmentEvents.isEmpty)
        #expect(store.mechanicsEvents.isEmpty)
    }

    @Test func survivesReopeningTheStoreOnDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("keyrep-\(UUID().uuidString)").appendingPathComponent("Training.store")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let event = KeyRepetitionEvent(result: KeyRepetitionResult(letter: "q", goal: 25, correct: 25, incorrect: 1,
                                                                   mode: .continuous, duration: 12))
        do {
            let store = try TrainingStore.onDisk(at: url)
            try store.record(event)
        }
        let reopened = try TrainingStore.onDisk(at: url)
        #expect(reopened.keyRepetitionEvents.count == 1)
        #expect(reopened.keyRepetitionEvents.first?.id == event.id)
        #expect(reopened.keyRepetitionEvents.first?.result == event.result)
    }
}
