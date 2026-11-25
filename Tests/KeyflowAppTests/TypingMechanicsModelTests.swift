import Foundation
import Testing
@testable import Keyflow
import KeyflowCore

@MainActor
@Suite struct TypingMechanicsModelTests {
    private func press(_ c: Character, at time: Double, _ modifiers: ModifierSnapshot = ModifierSnapshot(),
                       repeat isRepeat: Bool = false) -> KeyPress {
        KeyPress(keyCode: 0, characters: String(c), hasCommandOrControl: false, hasOption: false,
                 timestamp: time, modifiers: modifiers, isRepeat: isRepeat)
    }

    /// Types the rest of the round, capitals with the recommended (opposite) Shift or with Caps Lock.
    private func typeRound(_ model: TypingMechanicsModel, capsLock: Bool = false) {
        var time = 100.0
        var capsOn = model.capsLockOn
        while model.phase != .finished, let next = model.nextKey {
            let upper = CaseRequirement.of(next) == .uppercaseLetter
            let symbol = CaseRequirement.of(next) == .shiftedSymbol
            if capsLock {
                // As the drills instruct: on for a word in capitals, off right after it.
                if upper != capsOn, next.isLetter || next == " " {
                    capsOn = upper
                    model.handleModifier(.capsLock(on: capsOn, at: time - 0.05))
                }
            }
            if (upper && !capsLock) || symbol {
                let side: ShiftSide = FingerMap.hand(for: next) == .left ? .right : .left
                model.handleModifier(.shiftDown(side, at: time - 0.08))
                _ = model.handle(press(next, at: time, ModifierSnapshot(leftShift: side == .left, rightShift: side == .right,
                                                                          capsLock: capsOn)))
                model.handleModifier(.shiftUp(side, at: time + 0.02))
            } else {
                _ = model.handle(press(next, at: time, ModifierSnapshot(capsLock: capsOn)))
            }
            time += 0.15
        }
    }

    @Test func startsOnShiftControlWithGuidance() {
        let model = TypingMechanicsModel(seed: 1)
        #expect(model.area == .shiftControl)
        #expect(model.drill == .singleCapitals)
        let first = model.nextKey!
        #expect(first.isUppercase)
        #expect(model.nextRule == .shift)
        #expect(model.recommendedShift == (FingerMap.hand(for: first) == .left ? .right : .left))
        #expect(!model.capsLockNeedsToggle)
    }

    @Test func aCleanShiftRoundIsSavedWithItsTiming() throws {
        let store = try TrainingStore.inMemory()
        let model = TypingMechanicsModel(store: store, seed: 2)
        model.select(.capitalisedWords)
        typeRound(model)
        let summary = try #require(model.summary)
        #expect(summary.result.characterAccuracy == 1)
        #expect(summary.result.techniqueAccuracy == 1)
        #expect(summary.result.oppositeHandShift == summary.result.techniqueChecked)
        #expect(summary.result.shiftLead.median == 80)
        #expect(store.mechanicsEvents.count == 1)
        #expect(store.mechanicsEvents.first?.drill == .capitalisedWords)
        #expect(store.events.isEmpty && store.fingerFocusEvents.isEmpty)
        #expect(model.drillProgress.qualifyingRounds == 1)
    }

    @Test func capsLockInAShiftDrillKeepsTheCharacterButFlagsTheTechnique() {
        let model = TypingMechanicsModel(seed: 3)
        model.select(.capitalisedWords)
        let capital = model.nextKey!
        model.handleModifier(.capsLock(on: true, at: 1))
        #expect(model.capsLockOn)
        #expect(model.capsLockNeedsToggle, "Caps Lock is on in a Shift drill")
        _ = model.handle(press(capital, at: 1.2, ModifierSnapshot(capsLock: true)))
        #expect(model.lastMiss == nil, "the character is right")
        #expect(model.engine.position == 1)
        #expect(model.lastTechniqueMiss == .capsLock)
        #expect(model.liveTechniqueChecked == 1 && model.liveTechniqueCorrect == 0)
    }

    @Test func capsLockDrillGuidesBothSwitches() throws {
        let model = TypingMechanicsModel(seed: 4)
        model.select(.capsMixedCase)
        #expect(model.nextRule == .capsLock)
        #expect(model.capsLockNeedsToggle && model.recommendedShift == nil)
        model.handleModifier(.capsLock(on: true, at: 1))
        #expect(!model.capsLockNeedsToggle)
        var time = 1.2
        while let next = model.nextKey, next.isUppercase {
            _ = model.handle(press(next, at: time, ModifierSnapshot(capsLock: true)))
            time += 0.15
        }
        // After the word in capitals: a space, then lower case needs Caps Lock off.
        _ = model.handle(press(" ", at: time, ModifierSnapshot(capsLock: true)))
        #expect(model.nextKey?.isLowercase == true)
        #expect(model.capsLockNeedsToggle)
        model.handleModifier(.capsLock(on: false, at: time + 0.1))
        #expect(!model.capsLockNeedsToggle && !model.capsLockOn)
    }

    @Test func aFullCapsLockRoundMeasuresTheSwitches() throws {
        let model = TypingMechanicsModel(seed: 5)
        model.select(.uppercaseBlocks)
        typeRound(model, capsLock: true)
        let result = try #require(model.summary?.result)
        #expect(result.characterAccuracy == 1)
        #expect(result.techniqueAccuracy == 1)
        #expect(result.capsLockLead.count == 7, "one switch per word")
        #expect(result.capsLockLead.median == 50)
    }

    @Test func heldShiftAndFocusLossAreReflected() {
        let model = TypingMechanicsModel(seed: 6)
        model.handleModifier(.shiftDown(.right, at: 1))
        #expect(model.heldShift == .right)
        model.handleModifier(.capsLock(on: true, at: 2))
        model.handleModifier(.focusLost(at: 3))
        #expect(model.heldShift == nil)
        #expect(!model.capsLockOn)
        model.handleModifier(.sync(ModifierSnapshot(capsLock: true), at: 4))
        #expect(model.capsLockOn)
    }

    @Test func repeatAndNextExercise() throws {
        let model = TypingMechanicsModel(seed: 7)
        model.select(.alternatingCase)
        let text = model.text
        typeRound(model)
        #expect(model.phase == .finished)
        _ = model.handle(KeyPress(keyCode: KeyPress.tab, characters: "\t", hasCommandOrControl: false, hasOption: false, timestamp: 500))
        #expect(model.text == text && model.phase == .idle && model.summary == nil)
        typeRound(model)
        _ = model.handle(KeyPress(keyCode: KeyPress.return, characters: "\r", hasCommandOrControl: false, hasOption: false, timestamp: 600))
        #expect(model.phase == .idle)
        #expect(model.liveTechniqueChecked == 0)
    }

    @Test func choosingAnAreaGoesToItsRecommendedStage() {
        let model = TypingMechanicsModel(seed: 8)
        model.select(.caseTransitions)
        #expect(model.drill == .lowerToUpper)
        model.select(.mixedPatterns)
        #expect(model.area == .caseTransitions)
        #expect(model.nextRule == .none || model.nextRule == .any)
    }

    @Test func learnRoutesTheSessionMenuToTypingMechanics() throws {
        let app = AppModel(store: try StatisticsStore.inMemory(), trainingStore: try TrainingStore.inMemory(), defaults: nil)
        app.section = .muscleMemory
        app.learnMode = .mechanics
        let first = app.mechanics.text
        app.nextLearnExercise()
        #expect(app.mechanics.text != first || app.mechanics.drill == .singleCapitals)
        app.learnShowsKeyboard = false
        #expect(!app.mechanics.showsKeyboard)
        _ = app.mechanics.handle(press(app.mechanics.nextKey!, at: 1, ModifierSnapshot(rightShift: true)))
        app.restartCurrent()
        #expect(app.mechanics.phase == .idle)
    }
}

@MainActor
@Suite struct CapitalisationLabModelTests {
    private func typeRound(_ model: TypingMechanicsModel, capsLock: Bool) {
        var time = 100.0
        var capsOn = false
        while model.phase != .finished, let next = model.nextKey {
            let upper = CaseRequirement.of(next) == .uppercaseLetter
            if capsLock, upper != capsOn, next.isLetter || next == " " {
                capsOn = upper
                model.handleModifier(.capsLock(on: capsOn, at: time - 0.05))
            }
            var modifiers = ModifierSnapshot(capsLock: capsOn)
            if !capsLock, upper || CaseRequirement.of(next) == .shiftedSymbol {
                model.handleModifier(.shiftDown(.left, at: time - 0.08))
                modifiers = ModifierSnapshot(leftShift: true)
            }
            _ = model.handle(KeyPress(keyCode: 0, characters: String(next), hasCommandOrControl: false, hasOption: false,
                                      timestamp: time, modifiers: modifiers))
            if modifiers.shift { model.handleModifier(.shiftUp(.left, at: time + 0.02)) }
            time += 0.15
        }
        if capsOn { model.handleModifier(.capsLock(on: false, at: time)) }
    }

    @Test func aComparisonIsTheSamePassageInBothTechniquesThenFlipsOrder() throws {
        let store = try TrainingStore.inMemory()
        let model = TypingMechanicsModel(store: store, seed: 11)
        model.select(.capitalisationLab)
        #expect(model.drill == .labShiftOnly, "first comparison: Shift first")
        let passage = model.text
        #expect(model.currentComparison?.order == 1)

        typeRound(model, capsLock: false)
        #expect(model.pending?.awaiting == .labCapsLockOnly)
        #expect(model.primaryActionTitle == "Continue: Caps Lock Only, same passage")
        model.performPrimaryAction()
        #expect(model.drill == .labCapsLockOnly)
        #expect(model.text == passage)
        #expect(model.currentComparison?.order == 2)
        #expect(model.capsLockNeedsToggle == model.nextKey!.isUppercase || !(model.nextKey!.isUppercase))

        typeRound(model, capsLock: true)
        let comparison = try #require(model.summary?.comparison)
        #expect(comparison.shift.text == passage && comparison.capsLock.text == passage)
        #expect(comparison.shift.techniqueAccuracy == 1 && comparison.capsLock.techniqueAccuracy == 1)
        #expect(comparison.first == .labShiftOnly)
        #expect(store.mechanicsEvents.count == 2)
        #expect(model.primaryActionTitle == "New Comparison")

        model.performPrimaryAction()
        #expect(model.drill == .labCapsLockOnly, "second comparison: Caps Lock first")
        #expect(model.text != passage)
        #expect(model.currentComparison?.order == 1)
    }

    @Test func capsLockOnlyAsksForCapsLockEvenForOneLetter() {
        let model = TypingMechanicsModel(seed: 12)
        model.select(.labCapsLockOnly)
        var time = 1.0
        // Type up to the first capital.
        while let next = model.nextKey, !next.isUppercase {
            _ = model.handle(KeyPress(keyCode: 0, characters: String(next), hasCommandOrControl: false, hasOption: false,
                                      timestamp: time, modifiers: ModifierSnapshot()))
            time += 0.15
        }
        #expect(model.nextRule == .capsLock)
        #expect(model.capsLockNeedsToggle)
        #expect(model.recommendedShift == nil)
    }

    @Test func repeatingAFinishedHalfStartsAFreshComparison() {
        let model = TypingMechanicsModel(seed: 13)
        model.select(.labShiftOnly)
        typeRound(model, capsLock: false)
        let first = model.currentComparison?.id
        #expect(model.pending != nil)
        model.restart()
        #expect(model.pending == nil)
        #expect(model.currentComparison?.order == 1)
        #expect(model.currentComparison?.id != first)
    }

    @Test func leavingTheLabMidComparisonComesBackToTheOtherHalf() {
        let model = TypingMechanicsModel(seed: 14)
        model.select(.capitalisationLab)
        let passage = model.text
        typeRound(model, capsLock: false)
        model.select(.shiftControl)
        model.select(.capitalisationLab)
        #expect(model.drill == .labCapsLockOnly)
        #expect(model.text == passage)
        #expect(model.currentComparison?.order == 2)
    }

    @Test func freeChoiceNeverMarksATechniqueWrong() throws {
        let model = TypingMechanicsModel(seed: 15)
        model.select(.labFreeChoice)
        #expect(model.recommendedShift == nil, "no method is suggested in Free Choice")
        typeRound(model, capsLock: true)
        let result = try #require(model.summary?.result)
        #expect(result.techniqueAccuracy == 1)
        #expect(model.lastTechniqueMiss == nil)
        #expect((result.segments ?? []).allSatisfy { $0.method == .capsLock })
        #expect(model.currentComparison == nil && model.pending == nil)
    }
}

@MainActor
@Suite struct OverheadModelTests {
    @Test func overheadBuildsUpAcrossRounds() throws {
        let store = try TrainingStore.inMemory()
        let model = TypingMechanicsModel(store: store, seed: 21)
        #expect(model.overhead[.shift]?.isSufficient == false)
        model.select(.labShiftOnly)
        var time = 100.0
        while model.phase != .finished, let next = model.nextKey {
            let upper = next.isUppercase
            let runStart = upper && (model.engine.position == 0 || !model.engine.target[model.engine.position - 1].isUppercase)
            time += runStart ? 0.25 : 0.15
            if upper { model.handleModifier(.shiftDown(.left, at: time - 0.08)) }
            _ = model.handle(KeyPress(keyCode: 0, characters: String(next), hasCommandOrControl: false, hasOption: false,
                                      timestamp: time, modifiers: upper ? ModifierSnapshot(leftShift: true) : ModifierSnapshot()))
            if upper { model.handleModifier(.shiftUp(.left, at: time + 0.01)) }
        }
        let shift = try #require(model.overhead[.shift])
        #expect(shift.runs == 10)
        #expect(shift.overheadMs == 100)
        #expect(model.overhead[.capsLock]?.isSufficient == false)

        // A fresh model reads the same history back from the store.
        let reopened = TypingMechanicsModel(store: store, seed: 22)
        #expect(reopened.overhead[.shift]?.overheadMs == 100)
    }
}


@MainActor
@Suite struct NumbersAndSymbolsModelTests {
    private let us = KeyboardLayoutInfo(identifier: "com.apple.keylayout.US", name: "U.S.")
    private let german = KeyboardLayoutInfo(identifier: "com.apple.keylayout.German", name: "German")

    @Test func symbolsAreJudgedOnUSLayouts() throws {
        let model = TypingMechanicsModel(seed: 31, layout: { self.us })
        model.select(.shiftedSymbols)
        #expect(model.judgesSymbols)
        #expect(model.nextRule == .shift)
        #expect(model.recommendedShift != nil)
    }

    @Test func otherLayoutsDoNotJudgeSymbols() throws {
        let model = TypingMechanicsModel(seed: 32, layout: { self.german })
        model.select(.shiftedSymbols)
        #expect(!model.judgesSymbols)
        #expect(model.nextRule == .none)
        #expect(model.recommendedShift == nil)
        var time = 1.0
        while model.phase != .finished, let next = model.nextKey {
            _ = model.handle(KeyPress(keyCode: 0, characters: String(next), hasCommandOrControl: false, hasOption: false,
                                      timestamp: time, modifiers: ModifierSnapshot()))
            time += 0.15
        }
        let result = try #require(model.summary?.result)
        #expect(result.characterAccuracy == 1)
        #expect(result.techniqueChecked == 0, "nothing judged without a known layout")
    }

    @Test func layoutIsReadAgainEachRound() {
        var current = us
        let model = TypingMechanicsModel(seed: 33, layout: { current })
        #expect(model.judgesSymbols)
        current = german
        model.nextExercise()
        #expect(!model.judgesSymbols)
        #expect(model.layout?.name == "German")
    }
}

@MainActor
@Suite struct RecommendationModelTests {
    private func slowCapitalsRound(_ model: TypingMechanicsModel) {
        var time = 100.0
        while model.phase != .finished, let next = model.nextKey {
            let upper = next.isUppercase
            let position = model.engine.position
            let runStart = upper && (position == 0 || !model.engine.target[position - 1].isUppercase)
            time += runStart ? 0.35 : 0.15
            if upper { model.handleModifier(.shiftDown(.left, at: time - 0.08)) }
            _ = model.handle(KeyPress(keyCode: 0, characters: String(next), hasCommandOrControl: false, hasOption: false,
                                      timestamp: time, modifiers: upper ? ModifierSnapshot(leftShift: true) : ModifierSnapshot()))
            if upper { model.handleModifier(.shiftUp(.left, at: time + 0.01)) }
        }
    }

    @Test func recommendationsAppearAfterRepeatedEvidenceAndLeadSomewhere() throws {
        let store = try TrainingStore.inMemory()
        let model = TypingMechanicsModel(store: store, seed: 51)
        model.select(.labFreeChoice)
        #expect(model.recommendations.isEmpty)
        model.select(.labShiftOnly)
        slowCapitalsRound(model)
        #expect(model.recommendations.isEmpty, "one round is not enough")
        model.restart()
        slowCapitalsRound(model)
        let shift = try #require(model.recommendations.first { $0.kind == .slowShift })
        #expect(model.suggestion != nil)

        model.follow(shift)
        #expect(model.area == .shiftControl && model.drill == shift.drill)
        #expect(model.phase == .idle)

        // A fresh model reads the same advice from the store.
        #expect(TypingMechanicsModel(store: store, seed: 52).recommendations.contains { $0.kind == .slowShift })
    }

    @Test func followingALabSuggestionKeepsTheCounterbalancing() {
        let model = TypingMechanicsModel(seed: 53)
        let lab = MechanicsRecommendation(kind: .inconsistentStrategy, area: .capitalisationLab, drill: .labShiftOnly,
                                          title: "t", evidence: "e", rounds: 2)
        model.follow(lab)
        #expect(model.area == .capitalisationLab)
        #expect(model.drill == model.progress.nextLabFirst)
        #expect(model.currentComparison?.order == 1)
    }
}

@MainActor
@Suite struct MechanicsProgressNavigationTests {
    @Test func aRecommendationInProgressOpensThatStageInLearn() throws {
        let app = AppModel(store: try StatisticsStore.inMemory(), trainingStore: try TrainingStore.inMemory(), defaults: nil)
        app.section = .progress
        let recommendation = MechanicsRecommendation(kind: .slowNumbers, area: .numbersSymbols, drill: .mixedText,
                                                     title: "t", evidence: "e", rounds: 2)
        app.openMechanics(recommendation)
        #expect(app.section == .muscleMemory)
        #expect(app.learnMode == .mechanics)
        #expect(app.mechanics.drill == .mixedText)
        #expect(app.mechanics.phase == .idle)
    }
}
