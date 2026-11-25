import Foundation
import Testing
@testable import Keyflow
import KeyflowCore

@MainActor
@Suite struct MuscleMemoryModelTests {
    private var clock = 1_000.0

    /// Types the rest of the exercise. Every `wrongEvery`-th key is typed wrong first.
    private func typeExercise(_ model: MuscleMemoryModel, wrongEvery: Int? = nil, fix: Bool = false) {
        var time = 1_000.0
        var index = 0
        while model.phase != .finished, let expected = model.nextKey {
            if let wrongEvery, index % wrongEvery == wrongEvery - 1 {
                _ = model.handle(key(expected == "x" ? "z" : "x", at: time))
                time += 0.1
                if fix {
                    _ = model.handle(key("\u{7F}", code: KeyPress.delete, at: time))
                    time += 0.1
                    _ = model.handle(key(String(expected), at: time))
                }
            } else {
                _ = model.handle(key(String(expected), at: time))
            }
            time += 0.12
            index += 1
        }
    }

    @Test func startsBeginnersOnHomeRowStageOne() {
        let model = MuscleMemoryModel(seed: 1)
        #expect(model.category == .homeRow)
        #expect(model.stage == .singleKeys)
        #expect(model.phase == .idle)
        #expect(model.nextKey == model.exercise.text.first)
        #expect(!model.exercise.text.isEmpty)
        #expect(model.status(of: .transitions) == .locked)
        #expect(model.canSkipStage)
    }

    @Test func finishingARoundRecordsItAndCountsTowardMastery() throws {
        let store = try TrainingStore.inMemory()
        let model = MuscleMemoryModel(store: store, seed: 1)
        typeExercise(model)

        #expect(model.phase == .finished)
        #expect(model.nextKey == nil)
        let summary = try #require(model.summary)
        #expect(summary.result.accuracy == 1)
        #expect(summary.result.isQualifying)
        #expect(summary.progress.qualifyingRounds == 1)
        #expect(!summary.justMastered)
        #expect(store.events.count == 1)
        #expect(store.events.first?.category == .homeRow)
        #expect(store.events.first?.round?.text == model.exercise.text)
    }

    @Test func threeAccurateRoundsMasterTheStageAndReturnContinues() throws {
        let store = try TrainingStore.inMemory()
        let model = MuscleMemoryModel(store: store, seed: 2)
        for roundIndex in 1...3 {
            typeExercise(model)
            #expect(model.summary?.justMastered == (roundIndex == 3))
            if roundIndex < 3 {
                #expect(model.nextStageToContinue == nil)
                #expect(model.handle(key("\r", code: KeyPress.return, at: 5_000)))
                #expect(model.stage == .singleKeys)
                #expect(model.phase == .idle)
            }
        }
        #expect(model.status(of: .singleKeys) == .mastered)
        #expect(model.nextStageToContinue == .transitions)

        #expect(model.handle(key("\r", code: KeyPress.return, at: 6_000)))
        #expect(model.stage == .transitions)
        #expect(model.phase == .idle)
        #expect(model.exercise.stage == .transitions)
    }

    @Test func inaccurateRoundsDoNotCount() throws {
        let model = MuscleMemoryModel(seed: 3)
        typeExercise(model, wrongEvery: 5)
        let summary = try #require(model.summary)
        #expect(summary.result.accuracy < 0.95)
        #expect(!summary.result.isQualifying)
        #expect(summary.progress.qualifyingRounds == 0)
        #expect(summary.progress.rounds == 1)
    }

    @Test func correctedMistakesStillCountAgainstAccuracy() throws {
        let model = MuscleMemoryModel(seed: 4)
        typeExercise(model, wrongEvery: 4, fix: true)
        let result = try #require(model.summary?.result)
        #expect(result.backspaces > 0)
        #expect(result.accuracy < 0.95)
        #expect(result.keys.values.contains { $0.errors > 0 })
        #expect(model.engine.typed == model.engine.target)             // every mistake was fixed
    }

    @Test func wrongKeysAreReportedForTheFlash() {
        let model = MuscleMemoryModel(seed: 5)
        let expected = model.nextKey!
        _ = model.handle(key(expected == "q" ? "w" : "q", at: 10))
        #expect(model.lastMiss?.expected == expected)
        #expect(model.lastMiss?.id == 1)
        _ = model.handle(key("\u{7F}", code: KeyPress.delete, at: 11))
        #expect(model.engine.position == 0)
        _ = model.handle(key(String(expected), at: 12))
        #expect(model.lastMiss?.id == 1)                               // a correct key does not flash
    }

    @Test func spacesAndPunctuationAreTypedLikeAnyOtherKey() throws {
        let model = MuscleMemoryModel(seed: 6)
        model.select(.rightHand)
        let text = model.exercise.text
        #expect(text.contains(" "))
        typeExercise(model)
        #expect(model.summary?.result.accuracy == 1)
        #expect(String(model.engine.typed) == text)
    }

    @Test func tabRestartsTheSameTextAndNextExerciseChangesIt() {
        let model = MuscleMemoryModel(seed: 7)
        let text = model.exercise.text
        _ = model.handle(key(String(model.nextKey!), at: 10))
        #expect(model.phase == .running)
        #expect(model.handle(key("\t", code: KeyPress.tab, at: 11)))
        #expect(model.phase == .idle)
        #expect(model.exercise.text == text)
        var texts: Set<String> = []
        for _ in 0..<5 {
            model.nextExercise()
            texts.insert(model.exercise.text)
        }
        #expect(texts.subtracting([text]).count > 0)
        #expect(model.stage == .singleKeys)
    }

    @Test func skippingMovesOnWithoutMastery() throws {
        let store = try TrainingStore.inMemory()
        let model = MuscleMemoryModel(store: store, seed: 8)
        model.skipStage()
        #expect(model.stage == .transitions)
        #expect(model.status(of: .singleKeys) == .skipped)
        #expect(model.status(of: .transitions) == .available)
        #expect(model.tracker.masteredStages(.homeRow) == 0)
        #expect(store.events.map(\.kind) == [.skip])

        // A skipped stage cannot be skipped again; selecting it is still allowed.
        model.select(.singleKeys)
        #expect(model.stage == .singleKeys)
        #expect(!model.canSkipStage)
        model.skipStage()
        #expect(store.events.count == 1)
    }

    @Test func lockedStagesCannotBeSelected() {
        let model = MuscleMemoryModel(seed: 9)
        model.select(.words)
        #expect(model.stage == .singleKeys)
    }

    @Test func choosingACategoryStartsAtItsCurrentStage() throws {
        let store = try TrainingStore.inMemory()
        try store.record(TrainingEvent(category: .topRow, stage: .singleKeys, kind: .skip))
        let model = MuscleMemoryModel(store: store, seed: 10)
        model.select(.topRow)
        #expect(model.category == .topRow)
        #expect(model.stage == .transitions)
        #expect(model.exercise.category == .topRow)
        #expect(model.exercise.keys.isSubset(of: TrainingCategory.topRow.allowedKeys))
    }

    @Test func repeatedMistakesBringExtraPractice() throws {
        let store = try TrainingStore.inMemory()
        let model = MuscleMemoryModel(store: store, seed: 11)
        let weak = model.exercise.newKeys.first!
        // Miss the same key every time it comes up, for two rounds.
        for _ in 0..<2 {
            var time = 100.0
            while model.phase != .finished, let expected = model.nextKey {
                _ = model.handle(key(expected == weak ? "x" : String(expected), at: time))
                time += 0.1
            }
            model.nextExercise()
        }
        #expect(model.tracker.adaptive(for: .homeRow).level(of: String(weak)) == 2)
        #expect(model.exercise.focus.contains { $0.item == String(weak) })
    }

    @Test func progressAndSettingsPersistAcrossLaunches() throws {
        let store = try TrainingStore.inMemory()
        let suite = "keyflow-mm-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = MuscleMemoryModel(store: store, defaults: defaults, seed: 12)
        first.select(.leftHand)
        first.showsKeyboard = false
        typeExercise(first)

        let second = MuscleMemoryModel(store: store, defaults: defaults, seed: 13)
        #expect(second.category == .leftHand)
        #expect(!second.showsKeyboard)
        #expect(second.stageProgress.qualifyingRounds == 1)
        #expect(second.stageProgress.accuracyHistory == [1])
    }

    @Test func modifierShortcutsAndNonPrintingKeysPassThrough() {
        let model = MuscleMemoryModel(seed: 14)
        #expect(!model.handle(key("r", command: true, at: 1)))
        #expect(!model.handle(key("\u{F700}", code: 126, at: 1)))
        #expect(!model.handle(key("\r", code: KeyPress.return, at: 1)))
        #expect(model.phase == .idle)
    }

    @Test func pinyinFullWidthSemicolonCountsAsCorrect() throws {
        let store = try TrainingStore.inMemory()
        let model = MuscleMemoryModel(store: store, seed: 20)
        // Advance Home Row Stage 1 until the semicolon group is introduced.
        while !model.exercise.text.contains(";") {
            var time = 100.0
            while model.phase != .finished, let expected = model.nextKey {
                _ = model.handle(key(String(expected), at: time))
                time += 0.1
            }
            model.nextExercise()
        }
        var time = 1_000.0
        while model.phase != .finished, let expected = model.nextKey {
            // Type every semicolon the way Pinyin delivers it.
            _ = model.handle(key(expected == ";" ? "；" : String(expected), at: time))
            time += 0.1
        }
        #expect(model.lastMiss == nil)
        #expect(model.summary?.result.accuracy == 1)
        #expect(model.summary?.result.keys[";"] == ErrorCount(attempts: model.exercise.text.filter { $0 == ";" }.count, errors: 0))
    }
}
