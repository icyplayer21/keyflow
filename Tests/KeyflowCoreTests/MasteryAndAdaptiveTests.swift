import Foundation
import Testing
@testable import KeyflowCore

func round(_ accuracy: Double, keys: [String: ErrorCount] = [:], pairs: [String: ErrorCount] = [:]) -> RoundResult {
    let keystrokes = 100
    return RoundResult(text: "fj fj", accuracy: accuracy, keystrokes: keystrokes,
                       correctKeystrokes: Int((accuracy * Double(keystrokes)).rounded()), backspaces: 0,
                       duration: 30, keys: keys, pairs: pairs)
}

/// A Home Row, Stage 1 event.
func event(_ kind: TrainingEvent.Kind, minute: Int) -> TrainingEvent {
    event(.homeRow, .singleKeys, kind, minute: minute)
}

func event(_ category: TrainingCategory, _ stage: TrainingStage, _ kind: TrainingEvent.Kind, minute: Int) -> TrainingEvent {
    TrainingEvent(date: Date(timeIntervalSince1970: 1_800_000_000 + Double(minute) * 60),
                  category: category, stage: stage, kind: kind)
}

@Suite struct MasteryTests {
    @Test func aNewStageIsOpenOnlyAtStageOne() {
        let tracker = MasteryTracker(events: [])
        #expect(tracker.status(.homeRow, .singleKeys) == .available)
        #expect(tracker.status(.homeRow, .transitions) == .locked)
        #expect(tracker.status(.homeRow, .words) == .locked)
        #expect(tracker.currentStage(.homeRow) == .singleKeys)
        #expect(tracker.progress(.homeRow, .singleKeys) == StageProgress())
    }

    @Test func threeQualifyingRoundsMasterAStage() {
        var events: [TrainingEvent] = []
        for minute in 0..<2 { events.append(event(.round(round(0.97)), minute: minute)) }
        #expect(!MasteryTracker(events: events).progress(.homeRow, .singleKeys).isMastered)
        #expect(MasteryTracker(events: events).status(.homeRow, .transitions) == .locked)

        events.append(event(.round(round(1.0)), minute: 3))
        let tracker = MasteryTracker(events: events)
        #expect(tracker.progress(.homeRow, .singleKeys).isMastered)
        #expect(tracker.status(.homeRow, .singleKeys) == .mastered)
        #expect(tracker.status(.homeRow, .transitions) == .available)
        #expect(tracker.currentStage(.homeRow) == .transitions)
        #expect(tracker.masteredStages(.homeRow) == 1)
    }

    @Test func roundsBelowNinetyFivePercentDoNotCount() {
        let events = (0..<10).map { event(.round(round(0.94)), minute: $0) }
        let progress = MasteryTracker(events: events).progress(.homeRow, .singleKeys)
        #expect(progress.rounds == 10)
        #expect(progress.qualifyingRounds == 0)
        #expect(!progress.isMastered)
        #expect(progress.accuracyHistory.count == 10)
    }

    @Test func exactlyNinetyFivePercentQualifies() {
        #expect(round(0.95).isQualifying)
        #expect(RoundResult(text: "", accuracy: 19.0 / 20.0, keystrokes: 20, correctKeystrokes: 19, backspaces: 0, duration: 1).isQualifying)
        #expect(!round(0.9499).isQualifying)
        #expect(!RoundResult(text: "", accuracy: 1, keystrokes: 0, correctKeystrokes: 0, backspaces: 0, duration: 0).isQualifying)
    }

    @Test func qualifyingRoundsNeedNotBeConsecutive() {
        let accuracies = [0.96, 0.80, 0.99, 0.90, 0.95]
        let events = accuracies.enumerated().map { event(.round(round($0.element)), minute: $0.offset) }
        let progress = MasteryTracker(events: events).progress(.homeRow, .singleKeys)
        #expect(progress.qualifyingRounds == 3)
        #expect(progress.isMastered)
        #expect(progress.bestAccuracy == 0.99)
        #expect(progress.accuracyHistory == accuracies)
    }

    @Test func skippingOpensTheNextStageButIsNotMastery() {
        let tracker = MasteryTracker(events: [event(.skip, minute: 0)])
        #expect(tracker.status(.homeRow, .singleKeys) == .skipped)
        #expect(!tracker.progress(.homeRow, .singleKeys).isMastered)
        #expect(tracker.progress(.homeRow, .singleKeys).skipped)
        #expect(tracker.status(.homeRow, .transitions) == .available)
        #expect(tracker.status(.homeRow, .patterns) == .locked)
        #expect(tracker.masteredStages(.homeRow) == 0)
        #expect(tracker.currentStage(.homeRow) == .transitions)
    }

    @Test func aSkippedStageCanStillBeMasteredLater() {
        var events = [event(.skip, minute: 0)]
        for minute in 1...3 { events.append(event(.round(round(0.98)), minute: minute)) }
        let tracker = MasteryTracker(events: events)
        #expect(tracker.status(.homeRow, .singleKeys) == .mastered)
        #expect(tracker.progress(.homeRow, .singleKeys).skipped)
    }

    @Test func whenEverythingIsPassedTheFirstSkippedStageIsCurrent() {
        var events: [TrainingEvent] = []
        var minute = 0
        for stage in TrainingStage.allCases {
            if stage == .patterns {
                events.append(event(.homeRow, stage, .skip, minute: minute)); minute += 1
            } else {
                for _ in 0..<3 { events.append(event(.homeRow, stage, .round(round(1)), minute: minute)); minute += 1 }
            }
        }
        let tracker = MasteryTracker(events: events)
        #expect(tracker.currentStage(.homeRow) == .patterns)
        #expect(tracker.masteredStages(.homeRow) == 3)
    }

    @Test func categoriesAndStagesAreTrackedSeparately() {
        let events = (0..<3).map { event(.topRow, .singleKeys, .round(round(1)), minute: $0) }
            + [event(.homeRow, .transitions, .round(round(1)), minute: 10)]
        let tracker = MasteryTracker(events: events)
        #expect(tracker.status(.topRow, .singleKeys) == .mastered)
        #expect(tracker.status(.homeRow, .singleKeys) == .available)
        #expect(tracker.progress(.homeRow, .transitions).rounds == 1)
        #expect(tracker.progress(.homeRow, .singleKeys).rounds == 0)
        #expect(tracker.status(.bottomRow, .singleKeys) == .available)
    }

    @Test func eventsAreAppliedInDateOrder() {
        // Arrival order must not matter.
        let events = [event(.homeRow, .singleKeys, .skip, minute: 5), event(.round(round(1)), minute: 1)]
        let tracker = MasteryTracker(events: events)
        #expect(tracker.progress(.homeRow, .singleKeys).rounds == 1)
        #expect(tracker.progress(.homeRow, .singleKeys).skipped)
    }

    @Test func frequentlyMistypedKeysAreAggregated() {
        let events = [
            event(.round(round(0.9, keys: ["k": ErrorCount(attempts: 20, errors: 3), "f": ErrorCount(attempts: 20, errors: 1)])), minute: 0),
            event(.round(round(0.9, keys: ["k": ErrorCount(attempts: 20, errors: 2), "f": ErrorCount(attempts: 20, errors: 0),
                                           ";": ErrorCount(attempts: 10, errors: 4)])), minute: 1),
            event(.topRow, .singleKeys, .round(round(0.9, keys: ["r": ErrorCount(attempts: 10, errors: 9)])), minute: 2),
        ]
        let tracker = MasteryTracker(events: events)
        let homeRow = tracker.mistypedKeys(in: .homeRow)
        #expect(homeRow.map(\.key) == ["k", ";"])                 // f's single error is not "frequent"
        #expect(homeRow.first?.count == ErrorCount(attempts: 40, errors: 5))
        #expect(tracker.mistypedKeys().map(\.key) == ["r", "k", ";"])
        #expect(tracker.mistypedKeys(limit: 1).count == 1)
    }
}

@Suite struct AdaptiveRepetitionTests {
    private func keys(_ counts: [String: (Int, Int)]) -> [String: ErrorCount] {
        counts.mapValues { ErrorCount(attempts: $0.0, errors: $0.1) }
    }

    @Test func anOccasionalMistakeDoesNotTriggerExtraPractice() {
        var adaptive = AdaptiveRepetition()
        adaptive.record(keys: keys(["k": (12, 1)]), pairs: [:])
        #expect(adaptive.level(of: "k") == 0)
        #expect(adaptive.focusItems().isEmpty)

        // Two mistakes at a low rate are not enough either.
        adaptive.record(keys: keys(["k": (40, 2)]), pairs: [:])
        #expect(adaptive.level(of: "k") == 0)
    }

    @Test func repeatedMistakesRaiseTheLevelUpToTheCap() {
        var adaptive = AdaptiveRepetition()
        for expected in [1, 2, 3, 3, 3] {
            adaptive.record(keys: keys(["k": (8, 3)]), pairs: [:])
            #expect(adaptive.level(of: "k") == expected)
        }
        #expect(adaptive.focusItems() == [FocusItem(item: "k", level: 3)])
    }

    @Test func transitionsAreTrackedLikeKeys() {
        var adaptive = AdaptiveRepetition()
        adaptive.record(keys: [:], pairs: keys(["dk": (8, 4), "fj": (8, 0), "f ": (8, 8)]))
        #expect(adaptive.level(of: "dk") == 1)
        #expect(adaptive.level(of: "fj") == 0)
        #expect(adaptive.level(of: "f ") == 0)                     // anything with a space is ignored
    }

    @Test func improvementReducesRepetitionGradually() {
        var adaptive = AdaptiveRepetition()
        for _ in 0..<3 { adaptive.record(keys: keys(["k": (8, 3)]), pairs: [:]) }
        #expect(adaptive.level(of: "k") == 3)

        adaptive.record(keys: keys(["k": (20, 0)]), pairs: [:])
        #expect(adaptive.level(of: "k") == 2)
        adaptive.record(keys: keys(["k": (20, 1)]), pairs: [:])      // 5%: still counts as recovered
        #expect(adaptive.level(of: "k") == 1)
        adaptive.record(keys: keys(["k": (20, 2)]), pairs: [:])      // 10%: neither, level holds
        #expect(adaptive.level(of: "k") == 1)
        adaptive.record(keys: keys(["k": (20, 0)]), pairs: [:])
        #expect(adaptive.level(of: "k") == 0)
        #expect(adaptive.items.isEmpty)
    }

    @Test func roundsWithoutTheKeyLeaveItsLevelAlone() {
        var adaptive = AdaptiveRepetition()
        adaptive.record(keys: keys(["k": (8, 3)]), pairs: [:])
        adaptive.record(keys: keys(["f": (20, 0)]), pairs: [:])
        adaptive.record(keys: keys(["k": (2, 0)]), pairs: [:])      // too few attempts to judge
        #expect(adaptive.level(of: "k") == 1)
    }

    @Test func nothingIsDrilledForever() {
        var adaptive = AdaptiveRepetition()
        var levels: [Int] = []
        for _ in 0..<20 {
            adaptive.record(keys: keys(["k": (8, 4)]), pairs: [:])
            levels.append(adaptive.level(of: "k"))
        }
        // Six rounds in focus, then a rest of three rounds, then it may return.
        #expect(Array(levels.prefix(6)) == [1, 2, 3, 3, 3, 0])
        #expect(Array(levels[6..<9]) == [0, 0, 0])
        #expect(levels[9] == 1)
        #expect(levels.filter { $0 == 0 }.count >= 6)
    }

    @Test func focusItemsAreOrderedAndLimited() {
        var adaptive = AdaptiveRepetition()
        adaptive.record(keys: keys(["a": (8, 3), "b": (8, 3), "c": (8, 3), "d": (8, 3)]), pairs: [:])
        adaptive.record(keys: keys(["c": (8, 3), "d": (8, 3)]), pairs: [:])
        let focus = adaptive.focusItems()
        #expect(focus.count == 3)
        #expect(focus.map(\.item) == ["c", "d", "a"])
        #expect(focus.map(\.level) == [2, 2, 1])
        #expect(adaptive.focusItems(limit: 10).count == 4)
    }

    @Test func trackerReplaysAdaptiveStatePerCategory() {
        let struggling = round(0.8, keys: ["k": ErrorCount(attempts: 8, errors: 3)])
        let events = [event(.round(struggling), minute: 0), event(.round(struggling), minute: 1),
                      event(.topRow, .singleKeys, .round(round(1)), minute: 2)]
        let tracker = MasteryTracker(events: events)
        #expect(tracker.adaptive(for: .homeRow).level(of: "k") == 2)
        #expect(tracker.adaptive(for: .topRow).focusItems().isEmpty)
    }
}

@Suite struct RoundResultTests {
    @Test func resultsComeFromTheTypedSession() throws {
        var engine = TypingEngine(target: "fj fj", configuration: .init(timeLimit: nil, finishesAtEndOfText: true))
        engine.insert("f", at: 0)
        engine.insert("k", at: 0.5)        // wrong
        engine.backspace(at: 0.7)
        engine.insert("j", at: 1)
        engine.insert(" ", at: 1.3)
        engine.insert("f", at: 1.6)
        engine.insert("j", at: 2)
        #expect(engine.phase == .finished)

        let result = RoundResult(session: engine.session(at: 2))
        #expect(result.text == "fj fj")
        #expect(result.keystrokes == 6)
        #expect(result.correctKeystrokes == 5)
        #expect(result.backspaces == 1)
        #expect(result.duration == 2)
        #expect(abs(result.accuracy - 5.0 / 6.0) < 1e-12)
        #expect(!result.isQualifying)
        #expect(result.keys["j"] == ErrorCount(attempts: 3, errors: 1))
        #expect(result.keys["f"] == ErrorCount(attempts: 2, errors: 0))
        #expect(result.keys[" "] == nil)
        #expect(result.pairs["fj"] == ErrorCount(attempts: 3, errors: 1))
        #expect(result.pairs.keys.allSatisfy { !$0.contains(" ") })
    }

    @Test func punctuationKeysAreTracked() {
        var engine = TypingEngine(target: "l; l;", configuration: .init(timeLimit: nil, finishesAtEndOfText: true))
        type("l: l;", into: &engine, from: 0, every: 0.2)
        let result = RoundResult(session: engine.session(at: 10))
        #expect(result.keys[";"] == ErrorCount(attempts: 2, errors: 1))
        #expect(result.pairs["l;"] == ErrorCount(attempts: 2, errors: 1))
    }
}
