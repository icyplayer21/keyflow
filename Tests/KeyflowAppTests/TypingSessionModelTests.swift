import Foundation
import Testing
@testable import Keyflow
import KeyflowCore

@MainActor
func key(_ characters: String, code: UInt16 = 0, command: Bool = false, option: Bool = false, at time: Double) -> KeyPress {
    KeyPress(keyCode: code, characters: characters, hasCommandOrControl: command, hasOption: option, timestamp: time)
}

/// Types the next `count` target characters correctly, `interval` seconds apart.
@MainActor
func typeCorrectly(_ count: Int, into model: TypingSessionModel, from start: Double = 100, every interval: Double = 0.1) {
    for offset in 0..<count {
        let character = model.engine.target[model.engine.position]
        _ = model.handle(key(String(character), at: start + Double(offset) * interval))
    }
}

@MainActor
@Suite struct TypingSessionModelTests {
    private func practice(duration: Int = 30, mode: PracticeMode = .commonWords, store: StatisticsStore? = nil) -> TypingSessionModel {
        TypingSessionModel(role: .practice, store: store, durationSeconds: duration, mode: mode, seed: 1)
    }

    @Test func printableKeysTypeAndStartTheSession() {
        let model = practice()
        #expect(model.phase == .idle)
        typeCorrectly(5, into: model)
        #expect(model.phase == .running)
        #expect(model.engine.position == 5)
        #expect(model.metrics.accuracy == 1)
        model.restart()
    }

    @Test func commandShortcutsAndNonPrintingKeysPassThrough() {
        let model = practice()
        #expect(!model.handle(key("r", command: true, at: 1)))
        #expect(!model.handle(key("\u{F700}", code: 126, at: 1)))   // up arrow
        #expect(!model.handle(key("\r", code: KeyPress.return, at: 1)))
        #expect(model.phase == .idle)
        #expect(model.engine.position == 0)
    }

    @Test func deleteAndOptionDeleteEditTheBuffer() {
        let model = practice()
        _ = model.handle(key("z", at: 100))
        _ = model.handle(key("z", at: 100.1))
        _ = model.handle(key("z", at: 100.2))
        #expect(model.handle(key("\u{7F}", code: KeyPress.delete, at: 100.3)))
        #expect(model.engine.position == 2)
        #expect(model.handle(key("\u{7F}", code: KeyPress.delete, option: true, at: 100.4)))
        #expect(model.engine.position == 0)
        model.restart()
    }

    @Test func tabRestartsWithFreshText() {
        let model = practice()
        let firstText = model.engine.target
        typeCorrectly(8, into: model)
        #expect(model.handle(key("\t", code: KeyPress.tab, at: 105)))
        #expect(model.phase == .idle)
        #expect(model.engine.position == 0)
        #expect(model.engine.events.isEmpty)
        #expect(model.engine.target != firstText)
    }

    @Test func changingDurationResetsTheSession() {
        let model = practice()
        typeCorrectly(8, into: model)
        model.durationSeconds = 60
        #expect(model.phase == .idle)
        #expect(model.engine.configuration.timeLimit == 60)
    }

    @Test func textSupplyIsToppedUpAsTheUserTypes() {
        let model = practice(duration: 120)
        let initialLength = model.engine.target.count
        typeCorrectly(initialLength, into: model, from: 100)   // well inside 120 s
        #expect(model.engine.target.count > initialLength)
        #expect(model.engine.position == initialLength)
        #expect(model.phase == .running)
        model.restart()
    }

    @Test func keysAfterTheLimitEndTheSessionAndReturnRestarts() {
        let model = practice(duration: 15)
        typeCorrectly(10, into: model, from: 100)
        _ = model.handle(key("a", at: 116))
        #expect(model.phase == .finished)
        #expect(model.engine.position == 10)
        #expect(model.result?.metrics.elapsed == 15)
        #expect(model.result?.metrics.netWPM == 8)      // 10 chars / 5 / 0.25 min
        #expect(model.result?.wasSaved == false)        // no store attached

        // Typing is ignored on the results screen; Return starts a new session.
        _ = model.handle(key("a", at: 117))
        #expect(model.phase == .finished)
        #expect(model.handle(key("\r", code: KeyPress.return, at: 118)))
        #expect(model.phase == .idle)
        #expect(model.result == nil)
    }

    // MARK: Practice modes

    @Test func eachModeSuppliesItsOwnTextAndKind() {
        let model = practice()
        #expect(model.kind == .practice(.commonWords))
        let words = model.engine.target

        model.mode = .numbersSymbols
        #expect(model.kind == .practice(.numbersSymbols))
        #expect(model.engine.target != words)
        let hasDigits = model.engine.target.contains(where: \.isNumber)
        #expect(hasDigits)

        model.mode = .punctuation
        #expect(Corpus.punctuation.contains { String(model.engine.target).hasPrefix($0) })

        model.mode = .sentences
        #expect(Corpus.sentences.contains { String(model.engine.target).hasPrefix($0) })
        #expect(model.phase == .idle)
        #expect(!model.isEditingCustomText)
    }

    @Test func testRoleUsesSentencesAndItsOwnDurations() {
        let model = TypingSessionModel(role: .test, seed: 1)
        #expect(model.kind == .test)
        #expect(model.durationSeconds == 60)
        #expect(model.role.durations == [30, 60, 120])
        #expect(Corpus.sentences.contains { String(model.engine.target).hasPrefix($0) })
        #expect(model.engine.target.count >= 300)
    }

    // MARK: Custom text

    @Test func choosingCustomTextWithoutAPassageOpensTheEditor() {
        let model = practice()
        model.mode = .customText
        #expect(model.isEditingCustomText)
        #expect(!model.hasCustomText)
        // Keys belong to the editor, not the session.
        #expect(!model.handle(key("a", at: 100)))
        #expect(!model.handle(key("\t", code: KeyPress.tab, at: 100)))
        #expect(model.phase == .idle)
    }

    @Test func customPassageIsNormalisedAndEndsWhenFullyTyped() throws {
        let store = try StatisticsStore.inMemory()
        let model = practice(duration: 60, mode: .customText, store: store)
        model.setCustomText("  The \u{201C}quick\u{201D}\n brown fox.  ")
        #expect(!model.isEditingCustomText)
        #expect(String(model.engine.target) == "The \"quick\" brown fox.")

        typeCorrectly(model.engine.target.count, into: model)
        #expect(model.phase == .finished)
        #expect(model.result?.metrics.accuracy == 1)
        #expect(model.result?.wasSaved == true)
        #expect(store.summaries.map(\.kind) == [.practice(.customText)])

        // Restarting offers the same passage again.
        model.restart()
        #expect(String(model.engine.target) == "The \"quick\" brown fox.")
    }

    @Test func customPassageAlsoStopsAtTheTimeLimit() {
        let model = practice(duration: 15, mode: .customText)
        model.setCustomText(String(repeating: "slow and steady ", count: 40))
        typeCorrectly(20, into: model, from: 100)
        _ = model.handle(key("s", at: 120))
        #expect(model.phase == .finished)
        #expect(model.result?.metrics.elapsed == 15)
    }

    // MARK: Saving

    @Test func finishedTestIsAnalysedAndSavedExactlyOnce() throws {
        let store = try StatisticsStore.inMemory()
        let model = TypingSessionModel(role: .test, store: store, durationSeconds: 30, seed: 1)
        typeCorrectly(120, into: model, from: 100, every: 0.2)      // 24 s of typing
        #expect(store.summaries.isEmpty)                            // nothing saved mid-session

        _ = model.handle(key("x", at: 131))
        _ = model.handle(key("x", at: 132))
        let result = try #require(model.result)
        #expect(result.wasSaved)
        #expect(!result.isPersonalBest)                             // a first test has nothing to beat
        #expect(result.metrics.netWPM == 48)                        // 120 chars / 5 / 0.5 min
        #expect(result.analysis.consistency != nil)
        #expect(result.analysis.wpmTimeline.count == 30)
        #expect(model.saveError == nil)

        #expect(store.summaries.count == 1)
        let summary = try #require(store.summaries.first)
        #expect(summary.kind == .test)
        #expect(summary.timeLimit == 30)
        #expect(summary.metrics == result.metrics)
        #expect(try store.session(for: summary.id)?.events.count == 120)
    }

    @Test func personalBestIsFlaggedOnlyWhenBeaten() throws {
        let store = try StatisticsStore.inMemory()
        let model = TypingSessionModel(role: .test, store: store, durationSeconds: 30, seed: 1)

        func run(characters: Int) -> TypingSessionModel.Result? {
            model.restart()
            typeCorrectly(characters, into: model, from: 100, every: 0.1)
            _ = model.handle(key("x", at: 400))      // past any limit
            return model.result
        }

        #expect(run(characters: 100)?.isPersonalBest == false)
        #expect(run(characters: 150)?.isPersonalBest == true)
        #expect(run(characters: 150)?.isPersonalBest == false)      // a tie is not a new best
        #expect(run(characters: 90)?.isPersonalBest == false)
        #expect(store.summaries.count == 4)

        // Bests are tracked per duration.
        model.durationSeconds = 60
        #expect(run(characters: 50)?.isPersonalBest == false)
    }

    @Test func practiceSessionsAreSavedUnderTheirMode() throws {
        let store = try StatisticsStore.inMemory()
        let model = practice(duration: 15, mode: .punctuation, store: store)
        typeCorrectly(30, into: model)
        _ = model.handle(key("x", at: 120))
        #expect(store.summaries.map(\.kind) == [.practice(.punctuation)])
        #expect(model.result?.isPersonalBest == false)
    }

    // MARK: Remembered settings

    @Test func modeDurationAndPassageAreRemembered() throws {
        let suite = "keyflow-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = TypingSessionModel(role: .practice, defaults: defaults, seed: 1)
        #expect(first.mode == .commonWords)
        #expect(first.durationSeconds == 30)
        first.durationSeconds = 120
        first.mode = .customText
        first.setCustomText("remember me")

        let second = TypingSessionModel(role: .practice, defaults: defaults, seed: 2)
        #expect(second.mode == .customText)
        #expect(second.durationSeconds == 120)
        #expect(second.customText == "remember me")
        #expect(!second.isEditingCustomText)
        #expect(String(second.engine.target) == "remember me")

        // The test screen keeps its own duration and ignores practice settings.
        let test = TypingSessionModel(role: .test, defaults: defaults, seed: 3)
        #expect(test.durationSeconds == 60)
        #expect(test.kind == .test)
    }
}
