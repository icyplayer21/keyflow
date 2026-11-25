import Foundation
import Testing
@testable import Keyflow
import KeyflowCore

@MainActor
@Suite struct FingerIntelligenceNavigationTests {
    private func app() throws -> AppModel {
        AppModel(store: try StatisticsStore.inMemory(), trainingStore: try TrainingStore.inMemory(), defaults: nil)
    }

    private func type(_ model: FingerFocusModel) {
        var time = 1_000.0
        while model.phase != .finished, let expected = model.nextKey {
            _ = model.handle(key(String(expected), at: time))
            time += 0.15
        }
    }

    @Test func startFingerTrainingOpensFingerFocusWithThatFinger() throws {
        let app = try app()
        app.section = .progress
        app.trainFinger(.rightRing)
        #expect(app.section == .muscleMemory)
        #expect(app.learnMode == .fingerFocus)
        #expect(app.fingerFocus.target == .rightRing)
        #expect(!app.fingerFocus.isCheck)
        #expect(app.fingerFocus.roundInSet == 1)
    }

    @Test func trainingAMiddleOrIndexFingerUsesTheSameModule() throws {
        let app = try app()
        app.trainFinger(.leftIndex)
        #expect(app.fingerFocus.target == .leftIndex)
        #expect(app.fingerFocus.exercise.keys.isSubset(of: FingerFocusTarget.leftIndex.drillKeys))
    }

    @Test func reopeningTheSameFingerStartsAFreshSetAndLeavesAnyCheck() throws {
        let app = try app()
        app.trainFinger(.leftPinky)
        type(app.fingerFocus)
        app.fingerFocus.performPrimaryAction()
        #expect(app.fingerFocus.roundInSet == 2)
        app.checkFinger(.leftPinky)
        #expect(app.fingerFocus.isCheck)
        app.section = .progress
        app.trainFinger(.leftPinky)
        #expect(!app.fingerFocus.isCheck)
        #expect(app.fingerFocus.roundInSet == 1)
    }

    @Test func baselineThenTrainingThenRetestIsCompared() throws {
        let store = try TrainingStore.inMemory()
        let app = AppModel(store: try StatisticsStore.inMemory(), trainingStore: store, defaults: nil)
        let model = app.fingerFocus

        app.checkFinger(.leftPinky)
        #expect(model.checkTitle == "Baseline Check")
        let baselineText = model.exercise.text
        type(model)
        let baseline = try #require(model.checkSummary)
        #expect(baseline.comparison == nil)
        #expect(store.assessmentEvents.count == 1)
        #expect(store.fingerFocusEvents.isEmpty, "a check is not a training round")

        model.performPrimaryAction()                // back to training
        #expect(!model.isCheck)
        type(model)
        #expect(store.fingerFocusEvents.count == 1)

        #expect(model.checkTitle == "Retest This Finger")
        model.startCheck()
        #expect(model.exercise.text != baselineText, "a retest must not repeat the baseline text")
        type(model)
        let retest = try #require(model.checkSummary?.comparison)
        #expect(retest.trainingRounds == 1)
        #expect(retest.baseline.id == baseline.event.id)
        #expect(store.assessmentEvents.count == 2)
    }

    @Test func aFinishedCheckIsNeverRetypedWithTheSameText() throws {
        let model = FingerFocusModel(seed: 4)
        model.startCheck()
        let text = model.exercise.text
        type(model)
        model.restart()
        #expect(model.exercise.text != text)
        #expect(model.checkSummary == nil)
        #expect(model.isCheck)
    }

    @Test func practiceAndTestStillWorkAlongside() throws {
        let app = try app()
        app.section = .test
        let test = try #require(app.activeSession)
        var time = ProcessInfo.processInfo.systemUptime
        for _ in 0..<20 {
            _ = test.handle(key(String(test.engine.target[test.engine.position]), at: time))
            time += 0.1
        }
        #expect(test.phase == .running)
        app.restartCurrent()
        #expect(test.phase == .idle)
    }
}
