import Foundation
import Testing
@testable import Keyflow
import KeyflowCore

@MainActor
@Suite struct FingerFocusModelTests {
    /// Types the rest of the round. Every `wrongEvery`-th key is typed wrong.
    private func typeRound(_ model: FingerFocusModel, wrongEvery: Int? = nil,
                           substitute: (Character) -> String = { String($0) }) {
        var time = 1_000.0
        var index = 0
        while model.phase != .finished, let expected = model.nextKey {
            if let wrongEvery, index % wrongEvery == wrongEvery - 1 {
                _ = model.handle(key(expected == "k" ? "j" : "k", at: time))
            } else {
                _ = model.handle(key(substitute(expected), at: time))
            }
            time += 0.15
            index += 1
        }
    }

    private func pressReturn(_ model: FingerFocusModel) {
        _ = model.handle(key("\r", code: KeyPress.return, at: 2_000))
    }

    @Test func startsWithLeftPinkyActivation() {
        let model = FingerFocusModel(seed: 1)
        #expect(model.target == .leftPinky)
        #expect(model.level == .activation)
        #expect(model.recommendedLevel == .activation)
        #expect(model.roundInSet == 1)
        #expect(model.roundsPerSet == 5)
        #expect(model.restSeconds == 0)
        #expect(model.exercise.keys == ["a", "q", "z"])
        #expect(model.nextKey == model.exercise.text.first)
    }

    @Test func aRoundIsSavedAndReturnMovesToTheNextRound() throws {
        let store = try TrainingStore.inMemory()
        let model = FingerFocusModel(store: store, seed: 1)
        typeRound(model)

        let summary = try #require(model.summary)
        #expect(summary.result.accuracy == 1)
        #expect(!summary.completesSet)
        #expect(store.fingerFocusEvents.count == 1)
        #expect(store.fingerFocusEvents.first?.target == .leftPinky)
        #expect(store.fingerFocusEvents.first?.level == .activation)
        #expect(store.events.isEmpty, "Finger Focus must not appear as a lesson")
        #expect(model.levelProgress.qualifyingRounds == 1)

        let previous = model.exercise.text
        pressReturn(model)
        #expect(model.roundInSet == 2)
        #expect(model.phase == .idle)
        #expect(model.summary == nil)
        #expect(model.setResults.count == 1)
        #expect(model.exercise.text != previous || model.exercise.text.count > 0)
    }

    @Test func aSetEndsAfterTheChosenNumberOfRounds() throws {
        let model = FingerFocusModel(seed: 2)
        model.roundsPerSet = 3
        for round in 1...3 {
            #expect(model.roundInSet == round)
            typeRound(model, wrongEvery: round == 2 ? 10 : nil)
            if round < 3 { pressReturn(model) }
        }
        #expect(model.isSetComplete)
        #expect(model.setResults.count == 3)
        let accuracy = try #require(model.setAccuracy)
        #expect(accuracy < 1 && accuracy > 0.9)

        pressReturn(model)
        #expect(model.roundInSet == 1)
        #expect(model.setResults.isEmpty)
        #expect(!model.isSetComplete)
    }

    @Test func repeatingAFinishedRoundReplacesItInTheSet() {
        let model = FingerFocusModel(seed: 3)
        typeRound(model, wrongEvery: 4)
        #expect(model.setResults.count == 1)
        let text = model.exercise.text
        _ = model.handle(key("\t", code: KeyPress.tab, at: 3_000))
        #expect(model.setResults.isEmpty)
        #expect(model.exercise.text == text)
        #expect(model.roundInSet == 1)
        typeRound(model)
        #expect(model.setResults.map(\.accuracy) == [1])
    }

    @Test func restStartsAfterARoundAndReturnEndsItEarly() {
        let model = FingerFocusModel(seed: 4)
        model.restSeconds = 20
        typeRound(model)
        #expect(model.restRemaining == 20)
        pressReturn(model)
        #expect(model.restRemaining == nil)
        #expect(model.roundInSet == 2)
        #expect(model.phase == .idle)
    }

    @Test func restEndsByItselfAndStartsTheNextRound() async throws {
        let model = FingerFocusModel(seed: 5)
        model.restSeconds = 1
        typeRound(model)
        #expect(model.restRemaining == 1)
        // The rest ticks on the main actor; allow for a busy test run.
        for _ in 0..<50 where model.restRemaining != nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(model.restRemaining == nil)
        #expect(model.roundInSet == 2)
        #expect(model.summary == nil)
    }

    @Test func noRestAfterTheLastRoundOfASet() {
        let model = FingerFocusModel(seed: 6)
        model.roundsPerSet = 3
        model.restSeconds = 10
        for _ in 1...3 {
            typeRound(model)
            if !model.isSetComplete { pressReturn(model) }
        }
        #expect(model.isSetComplete)
        #expect(model.restRemaining == nil)
    }

    @Test func choosingAFingerStartsANewSetAtItsRecommendedLevel() {
        let model = FingerFocusModel(seed: 7)
        typeRound(model)
        pressReturn(model)
        model.select(.rightPinky)
        #expect(model.target == .rightPinky)
        #expect(model.level == .activation)
        #expect(model.roundInSet == 1)
        #expect(model.exercise.keys == [";", "p", "/"])
    }

    @Test func anyLevelCanBeChosenManually() {
        let model = FingerFocusModel(seed: 8)
        model.select(.words)
        #expect(model.level == .words)
        #expect(model.exercise.level == .words)
        #expect(model.recommendedLevel == .activation)
    }

    @Test func steadyRoundsMoveTheRecommendationAndRaiseComplexity() throws {
        let store = try TrainingStore.inMemory()
        let model = FingerFocusModel(store: store, seed: 9)
        model.roundsPerSet = 8
        for _ in 0..<3 {
            typeRound(model)
            pressReturn(model)
        }
        #expect(model.levelProgress.isSteady)
        #expect(model.recommendedLevel == .coordination)
        #expect(model.exercise.complexity == 1)

        // A new model reads the same history from the store.
        let reopened = FingerFocusModel(store: store, seed: 10)
        #expect(reopened.level == .coordination)
    }

    @Test func repeatedMissesAddExtraPracticeAndARecommendation() throws {
        let model = FingerFocusModel(seed: 11)
        model.select(.rightRing)
        model.roundsPerSet = 8
        for _ in 0..<3 {
            typeRound(model, wrongEvery: 3)
            pressReturn(model)
        }
        #expect(!model.recommendations.isEmpty)
        #expect(!model.exercise.focus.isEmpty)
        #expect(model.keyStats.contains { ($0.accuracy ?? 1) < 0.9 })
    }

    @Test func pinyinPunctuationCountsForTheRightPinky() throws {
        let model = FingerFocusModel(seed: 12)
        model.select(.rightPinky)
        typeRound(model) { character in
            switch character {
            case ";": "；"
            case "/": "／"
            default: String(character)
            }
        }
        #expect(try #require(model.summary).result.accuracy == 1)
        #expect(model.lastMiss == nil)
    }

    @Test func settingsPersist() throws {
        let defaults = try #require(UserDefaults(suiteName: "keyflow-finger-\(UUID().uuidString)"))
        let model = FingerFocusModel(defaults: defaults, seed: 13)
        model.select(.bothRings)
        model.roundsPerSet = 8
        model.restSeconds = 30
        model.showsKeyboard = false

        let reopened = FingerFocusModel(defaults: defaults, seed: 14)
        #expect(reopened.target == .bothRings)
        #expect(reopened.roundsPerSet == 8)
        #expect(reopened.restSeconds == 30)
        #expect(!reopened.showsKeyboard)
    }
}
