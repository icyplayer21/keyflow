import Foundation
import Testing
@testable import Keyflow
import KeyflowCore

@MainActor
@Suite struct TodayTests {
    private func makeApp(_ store: TrainingStore? = nil) throws -> (AppModel, TrainingStore) {
        let training = try store ?? TrainingStore.inMemory()
        return (AppModel(store: try StatisticsStore.inMemory(), trainingStore: training, defaults: nil), training)
    }

    private func key(_ c: Character, at time: Double) -> KeyPress {
        KeyPress(keyCode: 1, characters: String(c), hasCommandOrControl: false, hasOption: false, timestamp: time)
    }

    private var round: RoundResult {
        RoundResult(text: "fj", accuracy: 1, keystrokes: 10, correctKeystrokes: 10, backspaces: 0, duration: 5)
    }

    @Test func learnOpensOnTodayFirst() throws {
        let (app, _) = try makeApp()
        #expect(LearnMode.allCases.first == .today)
        #expect(app.learnMode == .today)
        app.section = .muscleMemory
        #expect(!app.isExerciseRunning)
        #expect(!app.canRestart, "Today has nothing to restart")
        #expect(!app.hasNextLearnExercise)
        #expect(!app.learnShowsKeyboard)
    }

    @Test func pickUpRowsOnlyForModesYouHaveUsed() throws {
        let (app, store) = try makeApp()
        #expect(app.pickUps.isEmpty)

        try store.record(TrainingEvent(category: .homeRow, stage: .singleKeys, kind: .skip))
        #expect(app.pickUps.isEmpty, "a skipped stage is not practice")

        try store.record(TrainingEvent(category: .homeRow, stage: .singleKeys, kind: .round(round)))
        try store.record(KeyRepetitionEvent(result: KeyRepetitionResult(letter: "p", goal: 50, correct: 50, incorrect: 0,
                                                                        mode: .continuous, duration: 30)))
        #expect(app.pickUps.map(\.id) == ["lessons", "keyRepetition"])
        #expect(app.pickUps.last == .keyRepetition("p"))

        try store.record(FingerFocusEvent(target: .rightPinky, level: .activation, result: round))
        #expect(app.pickUps.map(\.id) == ["lessons", "fingerFocus", "keyRepetition"])
    }

    @Test func pickingUpOpensTheModeAndKeepsASessionUnderWay() throws {
        let (app, store) = try makeApp()
        try store.record(KeyRepetitionEvent(result: KeyRepetitionResult(letter: "p", goal: 50, correct: 50, incorrect: 0,
                                                                        mode: .continuous, duration: 30)))
        app.section = .muscleMemory
        app.pickUp(.keyRepetition("p"))
        #expect(app.learnMode == .keyRepetition)
        #expect(app.keyRepetition.letter == "p")

        // A session on another key is under way: Today shows that key and opening it changes nothing.
        app.keyRepetition.select("f")
        app.keyRepetition.start()
        _ = app.keyRepetition.handle(key("f", at: 1))
        app.learnMode = .today
        #expect(app.pickUps.last == .keyRepetition("f"))
        app.pickUp(.keyRepetition("p"))
        #expect(app.keyRepetition.letter == "f")
        #expect(app.keyRepetition.counter.correct == 1)
    }

    @Test func startBeginsDailyFlowAndNeverRestartsOne() throws {
        let (app, _) = try makeApp()
        app.section = .muscleMemory
        app.startDailyFlowFromToday()
        #expect(app.learnMode == .dailyFlow)
        #expect(app.dailyFlow.stage == .flowing)
        let first = app.dailyFlow.engine.target.first!
        _ = app.dailyFlow.handle(key(first, at: 1))
        let typed = app.dailyFlow.engine.typed

        app.learnMode = .today
        app.dailyFlow.pause()
        app.startDailyFlowFromToday()
        #expect(app.learnMode == .dailyFlow)
        #expect(app.dailyFlow.engine.typed == typed, "the session under way is kept")
    }

    @Test func afterTodaysSessionStartOnlyOpensDailyFlow() throws {
        let (app, _) = try makeApp()
        app.startDailyFlowFromToday()
        let text = app.dailyFlow.engine.target
        for (i, c) in text.enumerated() { _ = app.dailyFlow.handle(key(c, at: Double(i))) }
        app.dailyFlow.endEarly()
        app.dailyFlow.done()
        #expect(app.dailyFlow.hasPractisedToday)
        app.learnMode = .today
        app.startDailyFlowFromToday()
        #expect(app.learnMode == .dailyFlow)
        #expect(app.dailyFlow.stage == .start, "Practice More opens Daily Flow without starting")
    }

    @Test func practiceDaysComeFromEverySavedKind() throws {
        let (app, store) = try makeApp()
        #expect(app.practiceDays.days.isEmpty)
        try store.record(TrainingEvent(category: .homeRow, stage: .singleKeys, kind: .skip))
        #expect(app.practiceDays.days.isEmpty, "skips are not practice")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        try store.record(FingerFocusEvent(date: yesterday, target: .rightPinky, level: .activation, result: round))
        try store.record(TrainingEvent(category: .homeRow, stage: .singleKeys, kind: .round(round)))
        #expect(app.practiceDays.days.count == 2)
        #expect(app.practiceDays.streak(asOf: .now) == 2)
    }

    @Test func theCurrentWordRunsToTheNextSpace() {
        let text = Array("the quick fox")
        #expect(TypingSurfaceView.currentWordEnd(in: text, at: 0) == 3)
        #expect(TypingSurfaceView.currentWordEnd(in: text, at: 1) == 3)
        #expect(TypingSurfaceView.currentWordEnd(in: text, at: 3) == 9, "on a space, the next word")
        #expect(TypingSurfaceView.currentWordEnd(in: text, at: 10) == 13)
        #expect(TypingSurfaceView.currentWordEnd(in: text, at: 13) == 13)
    }
}
