import Foundation
import Testing
@testable import KeyflowCore

/// How a simulated typist produces capitals.
enum Technique { case oppositeShift, sameShift, capsLock, none }

/// Types `text` through a real TypingEngine and ModifierTracker, with
/// modifier events placed the way a person would press them.
/// - `gap`: seconds between key presses; `extra` adds time before index i.
/// - `typo`: index → wrong character typed (left uncorrected).
func simulate(_ text: String, technique: Technique, gap: Double = 0.15, extra: [Int: Double] = [:],
              typo: [Int: Character] = [:], repeatAt: Set<Int> = [], shiftLead: Double = 0.08)
    -> (session: TypingSession, strokes: [ObservedKeystroke]) {
    var engine = TypingEngine(target: text, configuration: .init(timeLimit: nil, finishesAtEndOfText: true))
    var tracker = ModifierTracker()
    tracker.apply(.sync(ModifierSnapshot(), at: 0))
    var strokes: [ObservedKeystroke] = []
    var time = 1.0
    var capsOn = false
    let characters = Array(text)

    for (i, expected) in characters.enumerated() {
        time += (i == 0 ? 0 : gap) + (extra[i] ?? 0)
        let typed = typo[i] ?? expected
        let needsUpper = CaseRequirement.of(expected) == .uppercaseLetter
        let needsShiftSymbol = CaseRequirement.of(expected) == .shiftedSymbol
        var modifiers = ModifierSnapshot(capsLock: capsOn)

        if technique == .capsLock {
            if needsUpper, !capsOn {
                tracker.apply(.capsLock(on: true, at: time - 0.06))
                capsOn = true
            } else if !needsUpper, capsOn, expected.isLetter {
                tracker.apply(.capsLock(on: false, at: time - 0.06))
                capsOn = false
            }
            modifiers.capsLock = capsOn
        }
        if (needsUpper && (technique == .oppositeShift || technique == .sameShift)) || needsShiftSymbol {
            let hand = FingerMap.hand(for: expected)
            let side: ShiftSide = (technique == .sameShift) == (hand == .left) ? .left : .right
            tracker.apply(.shiftDown(side, at: time - shiftLead))
            modifiers = ModifierSnapshot(leftShift: side == .left, rightShift: side == .right, capsLock: capsOn)
            let accepted = engine.insert(typed, at: time)
            if accepted {
                strokes.append(tracker.keystroke(typed, at: time, isRepeat: repeatAt.contains(i), modifiers: modifiers))
            }
            tracker.apply(.shiftUp(side, at: time + 0.03))
            continue
        }
        if technique == .none, needsUpper { modifiers = ModifierSnapshot() }
        if engine.insert(typed, at: time) {
            strokes.append(tracker.keystroke(typed, at: time, isRepeat: repeatAt.contains(i), modifiers: modifiers))
        }
    }
    return (engine.session(at: time + 0.01), strokes)
}

@Suite struct MechanicsCatalogTests {
    @Test func everyDrillHasVariedDeterministicText() {
        for drill in MechanicsDrill.allCases {
            let a = MechanicsCatalog.text(for: drill, seed: 1)
            #expect(!a.isEmpty)
            #expect(a == MechanicsCatalog.text(for: drill, seed: 1))
            #expect(a != MechanicsCatalog.text(for: drill, seed: 2) || drill == .singleCapitals, "\(drill)")
            if drill.area != .numbersSymbols {
                #expect(a.contains(where: { CaseRequirement.of($0) == .uppercaseLetter }), "\(drill) has no capitals")
            }
            #expect(!a.contains("  ") && a.first != " " && a.last != " ")
            #expect(a.allSatisfy { CaseRequirement.of($0) != .unsupported }, "\(drill): \(a)")
        }
    }

    @Test func stagesAreOrderedPerArea() {
        #expect(MechanicsArea.shiftControl.drills.map(\.stage) == [1, 2, 3, 4])
        #expect(MechanicsArea.capsLockControl.drills.count == 3)
        #expect(MechanicsArea.caseTransitions.drills.count == 4)
        #expect(MechanicsDrill.capitalisedSentences.stage == 4)
    }

    @Test func singleCapitalsWorkBothHands() {
        for seed in UInt64(1)...5 {
            let letters = Set(MechanicsCatalog.text(for: .singleCapitals, seed: seed).filter(\.isLetter))
            let hands = Set(letters.compactMap(FingerMap.hand(for:)))
            #expect(hands == [.left, .right])
        }
    }

    @Test func capsLockDrillsContainWordsInCapitals() {
        for drill in MechanicsArea.capsLockControl.drills {
            let text = Array(MechanicsCatalog.text(for: drill, seed: 3))
            let runs = text.indices.filter { MechanicsDrill.uppercaseRun(around: $0, in: text).count >= 2 }
            #expect(!runs.isEmpty, "\(drill)")
        }
    }

    @Test func mixedPatternsHaveCapitalsInsideWords() {
        let words = MechanicsCatalog.text(for: .mixedPatterns, seed: 4).split(separator: " ")
        #expect(words.contains { word in word.dropFirst().contains(where: \.isUppercase) })
    }
}

@Suite struct TechniqueRuleTests {
    @Test func rulesPerArea() {
        let shift = Array("Apple 2!")
        #expect(MechanicsDrill.capitalisedWords.rule(at: 0, in: shift) == .shift)
        #expect(MechanicsDrill.capitalisedWords.rule(at: 1, in: shift) == .none)
        #expect(MechanicsDrill.capitalisedWords.rule(at: 7, in: shift) == .shift)

        let caps = Array("WELCOME to Keyflow.")
        #expect(MechanicsDrill.capsMixedCase.rule(at: 0, in: caps) == .capsLock)
        #expect(MechanicsDrill.capsMixedCase.rule(at: 6, in: caps) == .capsLock)
        #expect(MechanicsDrill.capsMixedCase.rule(at: 11, in: caps) == .any, "a single capital may use either")
        #expect(MechanicsDrill.capsRepeatedTransitions.rule(at: 9, in: Array("IMPORTANT: Read")) == .shift)

        let mixed = Array("iPhone")
        #expect(MechanicsDrill.mixedPatterns.rule(at: 1, in: mixed) == .any)
        #expect(MechanicsDrill.mixedPatterns.rule(at: 0, in: mixed) == .none)
    }

    @Test func acceptance() {
        #expect(TechniqueRule.shift.accepts(.leftShift) && TechniqueRule.shift.accepts(.shift))
        #expect(!TechniqueRule.shift.accepts(.capsLock) && !TechniqueRule.shift.accepts(.capsLockWithShift))
        #expect(TechniqueRule.capsLock.accepts(.capsLock) && TechniqueRule.capsLock.accepts(.capsLockWithShift))
        #expect(!TechniqueRule.capsLock.accepts(.rightShift))
        #expect(TechniqueRule.any.accepts(.capsLock) && TechniqueRule.any.accepts(.leftShift))
        #expect(!TechniqueRule.any.accepts(.unknown))
    }

    @Test func caseErrorsAreTheRightKeyInTheWrongState() {
        #expect(MechanicsAnalyzer.isCaseError(expected: "A", typed: "a"))
        #expect(MechanicsAnalyzer.isCaseError(expected: "n", typed: "N"))
        #expect(MechanicsAnalyzer.isCaseError(expected: "!", typed: "1"))
        #expect(!MechanicsAnalyzer.isCaseError(expected: "A", typed: "s"))
        #expect(!MechanicsAnalyzer.isCaseError(expected: "a", typed: "a"))
    }
}

@Suite struct MechanicsAnalyzerTests {
    @Test func oppositeShiftIsCorrectAndTimed() {
        let (session, strokes) = simulate("Apple London Monday", technique: .oppositeShift, shiftLead: 0.09)
        let result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .capitalisedWords)
        #expect(result.characterAccuracy == 1)
        #expect(result.techniqueChecked == 3 && result.techniqueCorrect == 3)
        #expect(result.oppositeHandShift == 3 && result.sameHandShift == 0)
        #expect(result.shiftLead.count == 3)
        #expect(result.shiftLead.median == 90)
        #expect(result.techniques["rightShift"] == 1 && result.techniques["leftShift"] == 2)
    }

    @Test func capsLockInAShiftDrillIsARightCharacterWithTheWrongTechnique() {
        let (session, strokes) = simulate("Apple London", technique: .capsLock)
        let result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .capitalisedWords)
        #expect(result.characterAccuracy == 1, "the characters themselves are right")
        #expect(result.techniqueChecked == 2)
        #expect(result.techniqueAccuracy == 0)
        // And the same typing is correct technique in a Caps Lock drill... for a single capital, any is fine.
        let caps = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .capsMixedCase)
        #expect(caps.techniqueAccuracy == 1)
    }

    @Test func capsLockDrillRecordsTheSwitchAndBothTransitions() {
        let text = "NASA is hiring and ESA is too"
        // 120 ms extra before each word in capitals and before the word after it (the Caps Lock switches).
        let chars = Array(text)
        var extra: [Int: Double] = [:]
        for i in chars.indices {
            let upper = CaseRequirement.of(chars[i]) == .uppercaseLetter
            if upper, i == 0 || chars[i - 1] == " " { extra[i] = 0.12 }
            if chars[i].isLowercase, i >= 2, chars[i - 1] == " ", CaseRequirement.of(chars[i - 2]) == .uppercaseLetter { extra[i] = 0.12 }
        }
        let (session, strokes) = simulate(text, technique: .capsLock, gap: 0.15, extra: extra)
        let result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .capsMixedCase)
        #expect(result.characterAccuracy == 1)
        #expect(result.techniqueAccuracy == 1)
        #expect(result.capsLockLead.count == 2)
        #expect(result.capsLockLead.median == 60)

        // Into capitals across a space ("d ESA") and back out ("A is"), against lower-case "x y" spans.
        #expect(result.samples(.intoUpperAcrossSpace).values == [420])
        #expect(result.samples(.outOfUpperAcrossSpace).values == [420, 420])
        #expect(result.samples(.lowerAcrossSpace).median == 300)
        let out = MechanicsFeedback.comparison(.outOfUpperAcrossSpace, in: result)
        #expect(out == nil, "two samples are not enough")
        #expect(result.samples(.withinUpper).median == 150)
    }

    @Test func transitionsAreComparedWithTheSameShapeInLowerCase() {
        // Six "xY" changes, each 100 ms slower than the 150 ms rhythm.
        let text = "aB cD eF gH iJ kL"
        let chars = Array(text)
        var extra: [Int: Double] = [:]
        for i in chars.indices where chars[i].isUppercase { extra[i] = 0.1 }
        let (session, strokes) = simulate(text, technique: .oppositeShift, gap: 0.15, extra: extra)
        let result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .alternatingCase)
        #expect(result.samples(.intoUpperDirect).values == Array(repeating: 250, count: 6))
        #expect(result.samples(.lowerDirect).count == 0, "no lower-case pairs in this text")
        #expect(MechanicsFeedback.comparison(.intoUpperDirect, in: result) == nil, "no baseline, no comparison")

        let sentence = "the cat sat on the Mat and the Dog ran to the Car with Ben"
        let s = Array(sentence)
        var slow: [Int: Double] = [:]
        for i in s.indices where s[i].isUppercase { slow[i] = 0.1 }
        let (session2, strokes2) = simulate(sentence, technique: .oppositeShift, gap: 0.15, extra: slow)
        let result2 = MechanicsAnalyzer.analyze(session2, strokes: strokes2, drill: .capitalisedSentences)
        let into = MechanicsFeedback.comparison(.intoUpperAcrossSpace, in: result2)
        #expect(into?.observed == 400)
        #expect(into?.baseline == 300)
        #expect(into?.difference == 100)
    }

    @Test func spansWithCorrectionsRepeatsOrPausesAreLeftOut() {
        var engine = TypingEngine(target: "ab Cd", configuration: .init(timeLimit: nil, finishesAtEndOfText: true))
        var tracker = ModifierTracker()
        var strokes: [ObservedKeystroke] = []
        func type(_ c: Character, _ t: Double, _ m: ModifierSnapshot = ModifierSnapshot(), repeat r: Bool = false) {
            if engine.insert(c, at: t) { strokes.append(tracker.keystroke(c, at: t, isRepeat: r, modifiers: m)) }
        }
        type("a", 1.0)
        type("x", 1.1)            // wrong "b"
        engine.backspace(at: 1.2)
        type("b", 1.3)
        type(" ", 1.45)
        tracker.apply(.shiftDown(.right, at: 1.5))
        type("C", 4.0, ModifierSnapshot(rightShift: true))  // a long pause
        type("d", 4.15)
        let result = MechanicsAnalyzer.analyze(engine.session(at: 4.2), strokes: strokes, drill: .capitalisedWords)
        #expect(result.samples(.lowerDirect).count == 0, "a→b had a correction in between")
        #expect(result.samples(.intoUpperAcrossSpace).count == 0, "the pause is not a transition")
        #expect(result.samples(.outOfUpperDirect).values == [150])
        #expect(result.keystrokes == 6 && result.correctKeystrokes == 5)
        #expect(result.shiftLead.values == [2500], "Shift lead is reported as observed")
    }

    @Test func caseMistakesAndCapsLockLeftOn() {
        let (session, strokes) = simulate("NASA is", technique: .capsLock, typo: [5: "I"])
        let result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .capsMixedCase)
        #expect(result.caseErrors == 1)
        // The simulated typist switched Caps Lock off before "i", so the wrong "I" is not blamed on it.
        #expect(result.capsLockLeftOn == 0)

        var engine = TypingEngine(target: "Ab", configuration: .init(timeLimit: nil, finishesAtEndOfText: true))
        var tracker = ModifierTracker()
        var strokes2: [ObservedKeystroke] = []
        tracker.apply(.capsLock(on: true, at: 0.9))
        for (c, t) in [("A", 1.0), ("B", 1.2)] as [(Character, Double)] where engine.insert(c, at: t) {
            strokes2.append(tracker.keystroke(c, at: t, modifiers: ModifierSnapshot(capsLock: true)))
        }
        let left = MechanicsAnalyzer.analyze(engine.session(at: 1.3), strokes: strokes2, drill: .capsMixedCase)
        #expect(left.capsLockLeftOn == 1 && left.caseErrors == 1)
    }

    @Test func unobservableTechniqueIsNotJudged() {
        let (session, strokes) = simulate("Apple Paris", technique: .none)
        let result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .capitalisedWords)
        #expect(result.characterAccuracy == 1)
        #expect(result.techniqueUnknown == 2)
        #expect(result.techniqueChecked == 0)
        #expect(result.techniqueAccuracy == nil)
    }

    @Test func repeatsAreNeverTimed() {
        let (session, strokes) = simulate("Abc Def", technique: .oppositeShift, repeatAt: [4])
        let result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .capitalisedWords)
        #expect(result.shiftLead.count == 1, "the repeated D is not timed")
        #expect(result.samples(.outOfUpperDirect).count == 1)
    }

    @Test func resultsRoundTripAsJSON() throws {
        let (session, strokes) = simulate("I visited London yesterday.", technique: .oppositeShift)
        let result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .capitalisedSentences)
        let decoded = try JSONDecoder().decode(MechanicsRoundResult.self, from: JSONEncoder().encode(result))
        #expect(decoded == result)
    }
}

@Suite struct MechanicsFeedbackTests {
    @Test func wrongTechniqueGetsATip() {
        let (session, strokes) = simulate("Apple London Monday Paris", technique: .capsLock)
        let result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .capitalisedWords)
        let tips = MechanicsFeedback.tips(for: result, drill: .capitalisedWords)
        #expect(tips.first?.title == "Use Shift")
    }

    @Test func sameHandShiftGetsATipInShiftDrillsOnly() {
        let (session, strokes) = simulate("Apple London Monday Paris", technique: .sameShift)
        let result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .capitalisedWords)
        #expect(result.sameHandShift == 4)
        #expect(MechanicsFeedback.tips(for: result, drill: .capitalisedWords).contains { $0.title == "Try the other Shift" })
        #expect(!MechanicsFeedback.tips(for: result, drill: .multipleTransitions).contains { $0.title == "Try the other Shift" })
    }

    @Test func slowCapitalsGetATipOnlyWithEnoughSamples() {
        let sentence = "the cat sat on the Mat and the Dog ran to the Car with Ben"
        let s = Array(sentence)
        var slow: [Int: Double] = [:]
        for i in s.indices where s[i].isUppercase { slow[i] = 0.2 }
        let (session, strokes) = simulate(sentence, technique: .oppositeShift, extra: slow)
        let result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .capitalisedSentences)
        #expect(MechanicsFeedback.tips(for: result, drill: .capitalisedSentences).contains { $0.title == "Starting capitals is slow" })

        let (few, fewStrokes) = simulate("the cat sat on the Mat", technique: .oppositeShift, extra: [19: 0.2])
        let thin = MechanicsAnalyzer.analyze(few, strokes: fewStrokes, drill: .capitalisedSentences)
        #expect(MechanicsFeedback.tips(for: thin, drill: .capitalisedSentences).isEmpty)
    }

    @Test func cleanRoundsHaveNoTips() {
        let (session, strokes) = simulate("I visited London yesterday.", technique: .oppositeShift)
        let result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .capitalisedSentences)
        #expect(MechanicsFeedback.tips(for: result, drill: .capitalisedSentences).isEmpty)
    }
}

@Suite struct MechanicsProgressTests {
    private func event(_ drill: MechanicsDrill, technique: Technique, minute: Int) -> MechanicsEvent {
        let (session, strokes) = simulate(MechanicsCatalog.text(for: drill, seed: UInt64(minute + 1)), technique: technique)
        return MechanicsEvent(date: Date(timeIntervalSince1970: Double(minute) * 60), drill: drill,
                              result: MechanicsAnalyzer.analyze(session, strokes: strokes, drill: drill))
    }

    @Test func threeCleanRoundsMakeADrillSteady() {
        var events = [event(.singleCapitals, technique: .oppositeShift, minute: 0),
                      event(.singleCapitals, technique: .oppositeShift, minute: 1)]
        #expect(MechanicsProgress(events: events).recommended(in: .shiftControl) == .singleCapitals)
        events.append(event(.singleCapitals, technique: .oppositeShift, minute: 2))
        let progress = MechanicsProgress(events: events)
        #expect(progress.progress(.singleCapitals).isSteady)
        #expect(progress.recommended(in: .shiftControl) == .alternatingCase)
        #expect(progress.recommended(in: .capsLockControl) == .uppercaseBlocks)
    }

    @Test func wrongTechniqueRoundsDoNotCount() {
        let events = (0..<3).map { event(.singleCapitals, technique: .capsLock, minute: $0) }
        let progress = MechanicsProgress(events: events)
        #expect(progress.progress(.singleCapitals).rounds == 3)
        #expect(progress.progress(.singleCapitals).qualifyingRounds == 0)
    }
}

@MainActor
@Suite struct MechanicsStoreTests {
    @Test func roundsRoundTripBesideOtherTraining() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "keyflow-mech-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "MuscleMemory.store")
        let (session, strokes) = simulate("NASA is hiring.", technique: .capsLock)
        let event = MechanicsEvent(date: Date(timeIntervalSince1970: 100), drill: .capsMixedCase,
                                   result: MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .capsMixedCase))
        let lesson = TrainingEvent(date: Date(timeIntervalSince1970: 50), category: .homeRow, stage: .singleKeys, kind: .skip)
        do {
            let store = try TrainingStore.onDisk(at: url)
            try store.record(lesson)
            try store.record(event)
        }
        let reopened = try TrainingStore.onDisk(at: url)
        #expect(reopened.mechanicsEvents == [event])
        #expect(reopened.events == [lesson])
        #expect(reopened.fingerFocusEvents.isEmpty && reopened.assessmentEvents.isEmpty)
    }
}

@Suite struct CapitalisationLabTests {
    @Test func labPassagesAreFairAndRepeatable() {
        for seed in UInt64(1)...10 {
            let text = MechanicsCatalog.labPassage(seed: seed)
            #expect(text == MechanicsCatalog.labPassage(seed: seed))
            #expect(MechanicsCatalog.text(for: .labShiftOnly, seed: seed) == MechanicsCatalog.text(for: .labCapsLockOnly, seed: seed))
            let chars = Array(text)
            var runs: [ClosedRange<Int>] = []
            var i = 0
            while i < chars.count {
                if CaseRequirement.of(chars[i]) == .uppercaseLetter {
                    let run = MechanicsDrill.uppercaseRun(around: i, in: chars)
                    runs.append(run)
                    i = run.upperBound + 1
                } else { i += 1 }
            }
            // Two runs in every length group…
            let groups = Dictionary(grouping: runs) { SegmentLength($0.count) }.mapValues(\.count)
            #expect(SegmentLength.allCases.allSatisfy { groups[$0] == 2 }, "\(text)")
            // …each with a space and a lower-case word either side, so every run is timed the same way.
            for run in runs {
                #expect(run.lowerBound >= 2 && chars[run.lowerBound - 1] == " " && chars[run.lowerBound - 2].isLowercase)
                #expect(run.upperBound + 2 < chars.count && chars[run.upperBound + 1] == " " && chars[run.upperBound + 2].isLowercase)
            }
            #expect(text.allSatisfy { CaseRequirement.of($0) != .unsupported })

            // Ordinary word-to-word changes to compare against, in both shapes used.
            let (session, strokes) = simulate(text, technique: .oppositeShift)
            let result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .labShiftOnly)
            #expect(result.samples(.lowerAcrossSpace).count >= MechanicsFeedback.minimumSamples)
            #expect(result.samples(.intoUpperAcrossSpace).count == 10 && result.samples(.outOfUpperAcrossSpace).count == 10)
            #expect(MechanicsFeedback.comparison(.intoUpperAcrossSpace, in: result) != nil)
        }
    }

    @Test func modeRules() {
        let text = Array("the B and NASA ok!")
        #expect(MechanicsDrill.labShiftOnly.rule(at: 4, in: text) == .shift)
        #expect(MechanicsDrill.labShiftOnly.rule(at: 10, in: text) == .shift, "whole words with Shift too")
        #expect(MechanicsDrill.labCapsLockOnly.rule(at: 4, in: text) == .capsLock, "single letters with Caps Lock too")
        #expect(MechanicsDrill.labCapsLockOnly.rule(at: 17, in: text) == .shift, "symbols always need Shift")
        #expect(MechanicsDrill.labFreeChoice.rule(at: 4, in: text) == .any)
        #expect(MechanicsDrill.labFreeChoice.rule(at: 17, in: text) == .any)
        #expect(MechanicsDrill.labShiftOnly.labCounterpart == .labCapsLockOnly)
        #expect(MechanicsDrill.labFreeChoice.labCounterpart == nil)
        #expect(MechanicsArea.capitalisationLab.drills == [.labShiftOnly, .labCapsLockOnly, .labFreeChoice])
    }

    @Test func lengthGroups() {
        #expect([1, 2, 3, 4, 5, 7, 8, 12].map(SegmentLength.init) == [.one, .two, .threeFour, .threeFour, .fiveSeven, .fiveSeven, .eightPlus, .eightPlus])
    }

    @Test func segmentsRecordMethodCleanlinessAndTheFullSpan() {
        // "the NASA and B ok": Caps Lock for both runs. 150 ms rhythm; the
        // simulated typist presses Caps Lock inside the gap before a run.
        let (session, strokes) = simulate("the NASA and B ok", technique: .capsLock, gap: 0.15, extra: [4: 0.1, 13: 0.1])
        let result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .labCapsLockOnly)
        let segments = result.segments ?? []
        #expect(segments.map(\.length) == [4, 1])
        #expect(segments.allSatisfy { $0.method == .capsLock && $0.clean })
        // NASA: space → N (250, with the switch) + 3 × 150 + A → space (150) = 850.
        #expect(segments[0].spanMs == 850)
        #expect(segments[0].entryMs == 250 && segments[0].exitMs == 150)
        #expect(segments[0].before == .space && segments[0].after == .space)
        #expect(segments[1].spanMs == 400)

        let (shiftSession, shiftStrokes) = simulate("the NASA and B ok", technique: .oppositeShift)
        let shift = MechanicsAnalyzer.analyze(shiftSession, strokes: shiftStrokes, drill: .labShiftOnly)
        #expect((shift.segments ?? []).allSatisfy { $0.method == .shift })
    }

    @Test func mixedUnknownAndUncleanSegments() {
        var engine = TypingEngine(target: "a NASA b", configuration: .init(timeLimit: nil, finishesAtEndOfText: true))
        var tracker = ModifierTracker()
        var strokes: [ObservedKeystroke] = []
        func type(_ c: Character, _ t: Double, _ m: ModifierSnapshot = ModifierSnapshot()) {
            if engine.insert(c, at: t) { strokes.append(tracker.keystroke(c, at: t, modifiers: m)) }
        }
        type("a", 1.0); type(" ", 1.15)
        type("N", 1.3, ModifierSnapshot(leftShift: true))
        type("A", 1.45, ModifierSnapshot(capsLock: true))
        type("X", 1.6, ModifierSnapshot(capsLock: true))      // wrong, fixed
        engine.backspace(at: 1.7)
        type("S", 1.8, ModifierSnapshot(capsLock: true))
        type("A", 1.95, ModifierSnapshot(capsLock: true))
        type(" ", 2.1); type("b", 2.25)
        let segment = MechanicsAnalyzer.analyze(engine.session(at: 2.3), strokes: strokes, drill: .labFreeChoice).segments?.first
        #expect(segment?.method == .mixed)
        #expect(segment?.clean == false)
        #expect(segment?.spanMs == nil, "a correction inside the run")
        #expect(segment?.entryMs == 150)

        let (unknownSession, unknownStrokes) = simulate("a B c", technique: .none)
        let unknown = MechanicsAnalyzer.analyze(unknownSession, strokes: unknownStrokes, drill: .labFreeChoice)
        #expect(unknown.segments?.first?.method == .unknown)
    }

    @Test func roundsSavedBeforeSegmentsStillLoad() throws {
        let (session, strokes) = simulate("Apple Paris", technique: .oppositeShift)
        let result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .capitalisedWords)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as! [String: Any]
        json["segments"] = nil
        json["comparisonID"] = nil
        json["comparisonOrder"] = nil
        let old = try JSONDecoder().decode(MechanicsRoundResult.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.segments == nil && old.comparisonID == nil)
        #expect(old.characterAccuracy == result.characterAccuracy)
    }

    @Test func comparisonsPairHalvesAndAlternateWhichComesFirst() {
        func half(_ drill: MechanicsDrill, _ id: UUID, order: Int, minute: Int) -> MechanicsEvent {
            let (session, strokes) = simulate(MechanicsCatalog.labPassage(seed: 1), technique: drill == .labShiftOnly ? .oppositeShift : .capsLock)
            var result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: drill)
            result.comparisonID = id
            result.comparisonOrder = order
            return MechanicsEvent(date: Date(timeIntervalSince1970: Double(minute) * 60), drill: drill, result: result)
        }
        let a = UUID(), b = UUID(), c = UUID()
        #expect(MechanicsProgress(events: []).nextLabFirst == .labShiftOnly)
        var events = [half(.labShiftOnly, a, order: 1, minute: 0), half(.labCapsLockOnly, a, order: 2, minute: 1)]
        var progress = MechanicsProgress(events: events)
        #expect(progress.comparisons.count == 1)
        #expect(progress.comparisons[0].first == .labShiftOnly)
        #expect(progress.comparisons[0].capsLock.techniqueAccuracy == 1)
        #expect(progress.nextLabFirst == .labCapsLockOnly)
        #expect(progress.recommended(in: .capitalisationLab) == .labCapsLockOnly)

        events += [half(.labCapsLockOnly, b, order: 1, minute: 2), half(.labShiftOnly, b, order: 2, minute: 3)]
        events.append(half(.labShiftOnly, c, order: 1, minute: 4))   // a half on its own
        progress = MechanicsProgress(events: events)
        #expect(progress.comparisons.map(\.id) == [a, b])
        #expect(progress.comparisons[1].first == .labCapsLockOnly)
        #expect(progress.nextLabFirst == .labShiftOnly)
    }
}

@Suite struct CapitalisationOverheadTests {
    /// A Lab passage typed at a steady 150 ms, with `entry` extra seconds
    /// before each run of capitals and `exit` extra after it.
    private func labRound(_ technique: Technique, seed: UInt64 = 1, entry: Double, exit: Double) -> MechanicsRoundResult {
        let text = MechanicsCatalog.labPassage(seed: seed)
        let chars = Array(text)
        var extra: [Int: Double] = [:]
        for i in chars.indices where CaseRequirement.of(chars[i]) == .uppercaseLetter {
            let run = MechanicsDrill.uppercaseRun(around: i, in: chars)
            if i == run.lowerBound { extra[i, default: 0] += entry }
            if i == run.upperBound { extra[i + 1, default: 0] += exit }
        }
        let (session, strokes) = simulate(text, technique: technique, gap: 0.15, extra: extra)
        return MechanicsAnalyzer.analyze(session, strokes: strokes, drill: technique == .capsLock ? .labCapsLockOnly : .labShiftOnly)
    }

    @Test func eachRunIsComparedWithTheSameNumberOfOrdinaryKeyChanges() {
        let result = labRound(.oppositeShift, entry: 0.08, exit: 0)
        let segments = result.segments ?? []
        #expect(segments.count == 10)
        for segment in segments {
            #expect(segment.baselineMs == Double(segment.length + 1) * 150, "\(segment.length) letters")
            #expect(segment.overheadMs == 80)
        }
    }

    @Test func capsLockPaysForSwitchingOnAndOff() {
        let result = labRound(.capsLock, entry: 0.08, exit: 0.08)
        #expect((result.segments ?? []).allSatisfy { $0.method == .capsLock && $0.overheadMs == 160 })
    }

    @Test func pooledEstimatesKeepObservedBaselineAndOverheadApart() {
        let shift = labRound(.oppositeShift, entry: 0.085, exit: 0)
        let caps = labRound(.capsLock, seed: 2, entry: 0.07, exit: 0.07)
        let estimates = CapitalisationOverhead.estimates(from: [shift, caps])
        let s = estimates[.shift]!, c = estimates[.capsLock]!
        #expect(s.runs == 10 && c.runs == 10)
        #expect(abs((s.overheadMs ?? 0) - 85) < 0.01)
        #expect(abs((c.overheadMs ?? 0) - 140) < 0.01)
        #expect(abs((s.observedMs ?? 0) - ((s.baselineMs ?? 0) + 85)) < 0.01)
        #expect(s.range == 85...85)
    }

    @Test func negativeOverheadIsReportedNotClamped() {
        let result = labRound(.oppositeShift, entry: -0.04, exit: 0)
        let estimate = CapitalisationOverhead.estimates(from: [result])[.shift]!
        #expect(estimate.overheadMs == -40)
    }

    @Test func tooFewRunsGiveNoEstimate() {
        let result = labRound(.oppositeShift, entry: 0.08, exit: 0)
        let observations = Array(CapitalisationOverhead.observations(from: [result]).prefix(7))
        let estimate = CapitalisationOverhead.estimate(observations, method: .shift)
        #expect(!estimate.isSufficient)
        #expect(estimate.runs == 7)
        #expect(estimate.observedMs == nil && estimate.baselineMs == nil && estimate.range == nil)
        #expect(CapitalisationOverhead.estimates(from: [])[.capsLock]?.runs == 0)
    }

    @Test func runsWithoutAComparableBaselineAreLeftOut() {
        // Next to punctuation: no ordinary change of that kind to compare with.
        let (s1, k1) = simulate("we went to the old NASA. then we left the old place", technique: .oppositeShift)
        let punct = MechanicsAnalyzer.analyze(s1, strokes: k1, drill: .labFreeChoice)
        #expect(punct.segments?.first?.baselineMs == nil)
        #expect(CapitalisationOverhead.observations(from: [punct]).isEmpty)

        // Too little ordinary typing in the round to know its rhythm.
        let (s2, k2) = simulate("a B c", technique: .oppositeShift)
        #expect(MechanicsAnalyzer.analyze(s2, strokes: k2, drill: .labFreeChoice).segments?.first?.baselineMs == nil)

        // Mixed method, or a run with a correction: excluded.
        var mixed = labRound(.oppositeShift, entry: 0.08, exit: 0)
        mixed.segments = mixed.segments?.map { var s = $0; s.method = .mixed; return s }
        var unclean = labRound(.oppositeShift, entry: 0.08, exit: 0)
        unclean.segments = unclean.segments?.map { var s = $0; s.clean = false; return s }
        #expect(CapitalisationOverhead.observations(from: [mixed, unclean]).isEmpty)

        // Rounds saved before baselines were recorded.
        var old = labRound(.oppositeShift, entry: 0.08, exit: 0)
        old.segments = old.segments?.map { var s = $0; s.baselineMs = nil; return s }
        #expect(CapitalisationOverhead.observations(from: [old]).isEmpty)
    }

    @Test func onlyRecentRoundsCount() {
        let early = labRound(.oppositeShift, entry: 0.5, exit: 0)
        let later = (0..<CapitalisationOverhead.recentRounds).map { _ in labRound(.oppositeShift, entry: 0.08, exit: 0) }
        let estimate = CapitalisationOverhead.estimates(from: [early] + later)[.shift]!
        #expect(estimate.runs == 10 * CapitalisationOverhead.recentRounds)
        #expect(estimate.range == 80...80)
    }

    @Test func lengthGroupsCanBeEstimatedSeparately() {
        let rounds = (UInt64(1)...4).map { labRound(.capsLock, seed: $0, entry: 0.06, exit: 0.06) }
        let observations = CapitalisationOverhead.observations(from: rounds)
        let ones = CapitalisationOverhead.estimate(observations, method: .capsLock, group: .one)
        #expect(ones.runs == 8 && ones.overheadMs == 120)
        #expect(!CapitalisationOverhead.estimate(observations, method: .shift, group: .one).isSufficient)
    }

    @Test func medianConfidenceRange() {
        #expect(CapitalisationOverhead.medianRange([1, 2, 3]) == nil)
        #expect(CapitalisationOverhead.medianRange((1...8).map(Double.init)) == 1...8)
        #expect(CapitalisationOverhead.medianRange((1...100).map(Double.init)) == 40...61)
        // Order does not matter.
        #expect(CapitalisationOverhead.medianRange((1...100).map(Double.init).reversed()) == 40...61)
    }

    @Test func spaceChangesFormTheirOwnBaseline() {
        let (session, strokes) = simulate("one two three four", technique: .none, gap: 0.15, extra: [3: 0.05, 7: 0.05, 13: 0.05])
        let result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .labFreeChoice)
        // Each space is entered 50 ms late and left on time.
        #expect(result.samples(.spaceAdjacent).values.sorted() == [150, 150, 150, 200, 200, 200])
        #expect(result.samples(.lowerDirect).median == 150)
    }
}


@Suite struct NumbersAndSymbolsTests {
    @Test func exerciseTextFitsEachStage() {
        for seed in UInt64(1)...8 {
            let numbers = MechanicsCatalog.text(for: .numberRow, seed: seed)
            #expect(numbers.allSatisfy { $0 == " " || $0.isNumber })
            #expect(Set(numbers.filter(\.isNumber)).count >= 9, "\(numbers)")

            let symbols = MechanicsCatalog.text(for: .shiftedSymbols, seed: seed)
            #expect(symbols.allSatisfy { $0 == " " || CaseRequirement.of($0) == .shiftedSymbol })
            #expect(Set("!@#$%^&*()").isSubset(of: Set(symbols)))

            let mixed = MechanicsCatalog.text(for: .mixedText, seed: seed)
            #expect(mixed.contains { $0.isNumber })
            for drill in MechanicsArea.numbersSymbols.drills {
                #expect(MechanicsCatalog.text(for: drill, seed: seed).allSatisfy { CaseRequirement.of($0) != .unsupported },
                        "\(drill) must be typeable on US QWERTY")
            }
        }
        #expect(MechanicsArea.numbersSymbols.drills == [.numberRow, .shiftedSymbols, .punctuation, .mixedText])
    }

    @Test func symbolsNeedShiftCapitalsAreFree() {
        let text = Array("Pay 25% now!")
        #expect(MechanicsDrill.mixedText.rule(at: 6, in: text) == .shift)
        #expect(MechanicsDrill.mixedText.rule(at: 11, in: text) == .shift)
        #expect(MechanicsDrill.mixedText.rule(at: 0, in: text) == .any)
        #expect(MechanicsDrill.mixedText.rule(at: 4, in: text) == .none)
        #expect(MechanicsDrill.numberRow.wantedTechnique == nil)
    }

    @Test func numberTransitionsAreComparedWithLetters() {
        // 150 ms rhythm; reaching each number 200 ms late (past the 1.4× "slow" line), leaving it 60 ms late.
        let text = "we had 25 cats and 30 dogs and 41 hens and some more birds"
        let chars = Array(text)
        var extra: [Int: Double] = [:]
        for i in chars.indices where chars[i].isNumber {
            if !chars[i - 1].isNumber { extra[i] = 0.2 }
            if i + 1 < chars.count, chars[i + 1] == " " { extra[i + 1] = 0.06 }
        }
        let (session, strokes) = simulate(text, technique: .oppositeShift, gap: 0.15, extra: extra)
        let result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .mixedText)
        #expect(result.samples(.intoDigitAcrossSpace).values == [500, 500, 500])
        #expect(result.samples(.outOfDigitAcrossSpace).values == [360, 360, 360])
        #expect(result.samples(.withinDigits).values == [150, 150, 150])
        #expect(MechanicsFeedback.comparison(.intoDigitAcrossSpace, in: result)?.difference == 200)
        #expect(MechanicsFeedback.tips(for: result, drill: .mixedText).contains { $0.title == "Reaching for numbers is slow" })
    }

    @Test func shiftedSymbolsAreTimedAndJudged() {
        let (session, strokes) = simulate("up 25% then 30% now and 9% more", technique: .oppositeShift, shiftLead: 0.07)
        let result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .mixedText)
        #expect(result.samples(.intoShiftedSymbol).count == 3)
        #expect(result.techniqueChecked == 3 && result.techniqueCorrect == 3)
        #expect(result.shiftLead.values == [70, 70, 70])
        // "%" is on the left hand: the recommended Shift is the right one.
        #expect(result.oppositeHandShift == 3)
        #expect(result.characters?["%"]?.attempts == 3)
        #expect(result.characters?["%"]?.reach.count == 3)

        let unjudged = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .mixedText, judgeSymbols: false)
        #expect(unjudged.techniqueChecked == 0)
        #expect(unjudged.characterAccuracy == result.characterAccuracy)
    }

    @Test func charactersToWatch() {
        // "7" is missed twice; "0" is reached slowly.
        let text = "a7 b7 c7 d7 e0 f0 g0 h0 ij kl mn op qr st"
        let chars = Array(text)
        var extra: [Int: Double] = [:]
        for i in chars.indices where chars[i] == "0" { extra[i] = 0.2 }
        let sevens = chars.indices.filter { chars[$0] == "7" }
        let (session, strokes) = simulate(text, technique: .oppositeShift, gap: 0.15, extra: extra,
                                          typo: [sevens[0]: "8", sevens[2]: "6"])
        let result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .numberRow)
        #expect(result.characters?["7"]?.errors == 2)
        let watch = MechanicsFeedback.charactersToWatch(in: result)
        #expect(watch.map(\.character) == ["7", "0"])
        #expect(watch[0].reason == .errors && watch[1].reason == .slow)
        #expect(MechanicsFeedback.tips(for: result, drill: .numberRow).first?.title == "Watch \u{201C}7\u{201D}")

        let (clean, cleanStrokes) = simulate(text, technique: .oppositeShift)
        #expect(MechanicsFeedback.charactersToWatch(in: MechanicsAnalyzer.analyze(clean, strokes: cleanStrokes, drill: .numberRow)).isEmpty)
    }

    @Test func shiftMistakesOnSymbols() {
        let (session, strokes) = simulate("save 50% today", technique: .oppositeShift, typo: [7: "5"])
        let result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: .mixedText)
        #expect(result.caseErrors == 1, "5 for % is the right key without Shift")
    }
}

@Suite struct MechanicsRecommenderTests {
    private var minute = 0

    private func event(_ drill: MechanicsDrill, _ text: String, _ technique: Technique, extra: [Int: Double] = [:],
                       typo: [Int: Character] = [:], shiftLead: Double = 0.08, at minute: Int) -> MechanicsEvent {
        let (session, strokes) = simulate(text, technique: technique, gap: 0.15, extra: extra, typo: typo, shiftLead: shiftLead)
        return MechanicsEvent(date: Date(timeIntervalSince1970: Double(minute) * 60), drill: drill,
                              result: MechanicsAnalyzer.analyze(session, strokes: strokes, drill: drill))
    }

    /// Extra time before each run of capitals (entry) and after it (exit).
    private func runDelays(_ text: String, entry: Double, exit: Double) -> [Int: Double] {
        let chars = Array(text)
        var extra: [Int: Double] = [:]
        for i in chars.indices where CaseRequirement.of(chars[i]) == .uppercaseLetter {
            let run = MechanicsDrill.uppercaseRun(around: i, in: chars)
            if i == run.lowerBound { extra[i, default: 0] += entry }
            if i == run.upperBound, i + 1 < chars.count { extra[i + 1, default: 0] += exit }
        }
        return extra
    }

    private func kinds(_ events: [MechanicsEvent]) -> [MechanicsRecommendation.Kind] {
        MechanicsRecommender.recommendations(from: events).map(\.kind)
    }

    @Test func cleanTypingAndTooLittleDataSuggestNothing() {
        #expect(kinds([]).isEmpty)
        let clean = (0..<4).map { event(.labShiftOnly, MechanicsCatalog.labPassage(seed: UInt64($0 + 1)), .oppositeShift, at: $0) }
        #expect(kinds(clean).isEmpty)
    }

    @Test func slowShiftNeedsTwoRounds() {
        let text = MechanicsCatalog.labPassage(seed: 1)
        let slow = event(.labShiftOnly, text, .oppositeShift, extra: runDelays(text, entry: 0.15, exit: 0), at: 0)
        #expect(!kinds([slow]).contains(.slowShift), "one round is never enough")
        let again = event(.labShiftOnly, MechanicsCatalog.labPassage(seed: 2), .oppositeShift,
                          extra: runDelays(MechanicsCatalog.labPassage(seed: 2), entry: 0.15, exit: 0), at: 1)
        let recommendation = MechanicsRecommender.recommendations(from: [slow, again]).first { $0.kind == .slowShift }
        #expect(recommendation?.area == .shiftControl)
        #expect(recommendation?.evidence.contains("150 ms") == true)
        #expect(recommendation?.rounds == 2)
    }

    @Test func shiftHeldLongBeforeTheLetter() {
        let text = "I visited London on Monday with Sarah and Emma before July in Paris"
        let events = (0..<2).map { event(.capitalisedSentences, text, .oppositeShift, shiftLead: 0.3, at: $0) }
        let recommendation = MechanicsRecommender.recommendations(from: events).first { $0.kind == .slowShift }
        #expect(recommendation?.drill == .singleCapitals)
        #expect(recommendation?.evidence.contains("300 ms") == true)
    }

    @Test func capsLockLeftOnAndWrongTechnique() {
        var a = event(.capsMixedCase, "NASA is hiring.", .capsLock, at: 0)
        var b = event(.capsMixedCase, "WELCOME to Keyflow.", .capsLock, at: 1)
        a = MechanicsEvent(id: a.id, date: a.date, drill: a.drill, result: { var r = a.result; r.capsLockLeftOn = 2; return r }())
        #expect(!kinds([a]).contains(.capsLockState), "one round")
        b = MechanicsEvent(id: b.id, date: b.date, drill: b.drill, result: { var r = b.result; r.capsLockLeftOn = 1; return r }())
        #expect(kinds([a, b]).contains(.capsLockState))

        let shiftInCapsDrills = (0..<2).map {
            event(.uppercaseBlocks, "NASA UNESCO IMPORTANT AUSTRALIA", .oppositeShift, at: $0)
        }
        let recommendation = MechanicsRecommender.recommendations(from: shiftInCapsDrills).first { $0.kind == .capsLockState }
        #expect(recommendation?.drill == .uppercaseBlocks)
        #expect(recommendation?.evidence.contains("0%") == true)
    }

    @Test func priorityReordersButNeverAddsOrRemoves() {
        var a = event(.capsMixedCase, "NASA is hiring.", .capsLock, at: 0)
        var b = event(.capsMixedCase, "WELCOME to Keyflow.", .capsLock, at: 1)
        a = MechanicsEvent(id: a.id, date: a.date, drill: a.drill, result: { var r = a.result; r.capsLockLeftOn = 2; return r }())
        b = MechanicsEvent(id: b.id, date: b.date, drill: b.drill, result: { var r = b.result; r.capsLockLeftOn = 1; return r }())
        let slow = (UInt64(1)...2).map { seed -> MechanicsEvent in
            let text = MechanicsCatalog.labPassage(seed: seed)
            return event(.labShiftOnly, text, .oppositeShift, extra: runDelays(text, entry: 0.15, exit: 0), at: Int(seed) + 1)
        }
        let events = [a, b] + slow
        func order(_ priority: MechanicsRecommender.Priority) -> [MechanicsRecommendation.Kind] {
            MechanicsRecommender.recommendations(from: events, priority: priority).map(\.kind)
        }
        let accuracy = order(.accuracy), speed = order(.speed), balanced = order(.balanced)
        #expect(Set(accuracy) == Set(balanced) && Set(speed) == Set(balanced))
        let caps = accuracy.firstIndex(of: .capsLockState), shift = accuracy.firstIndex(of: .slowShift)
        let speedCaps = speed.firstIndex(of: .capsLockState), speedShift = speed.firstIndex(of: .slowShift)
        #expect(caps != nil && shift != nil, "fixture: both kinds are found (\(balanced))")
        if let caps, let shift, let speedCaps, let speedShift {
            #expect(caps < shift, "Accuracy First: \(accuracy)")
            #expect(speedShift < speedCaps, "Speed First: \(speed)")
        }
    }

    @Test func slowReturnToLowerCase() {
        let events = (UInt64(1)...2).map { seed -> MechanicsEvent in
            let text = MechanicsCatalog.labPassage(seed: seed)
            return event(.labFreeChoice, text, .oppositeShift, extra: runDelays(text, entry: 0, exit: 0.2), at: Int(seed))
        }
        let recommendations = MechanicsRecommender.recommendations(from: events)
        let back = recommendations.first { $0.kind == .slowReturnToLower }
        #expect(back?.drill == .upperToLower)
        #expect(back?.evidence.contains("65%") == true, "(300 + 200) / 300 ≈ 1.67, shown to the nearest 5%")
        #expect(!recommendations.contains { $0.kind == .slowIntoCapitals })
    }

    @Test func slowNumbersNamesTheSlowPart() {
        let text = "we had 25 cats and 30 dogs and 41 hens and 12 cows and 88 ducks and some more birds"
        let chars = Array(text)
        var extra: [Int: Double] = [:]
        for i in chars.indices where chars[i].isNumber && !chars[i - 1].isNumber { extra[i] = 0.2 }
        let events = (0..<2).map { event(.mixedText, text, .oppositeShift, extra: extra, at: $0) }
        let numbers = MechanicsRecommender.recommendations(from: events).first { $0.kind == .slowNumbers }
        #expect(numbers?.drill == .mixedText)
        #expect(numbers?.evidence.hasPrefix("Reaching from letters to numbers") == true)
    }

    @Test func charactersMissedInSeveralRounds() {
        let text = "a7 b7 c7 d7 e1 f2 g3 h4 ij kl mn op qr st"
        let sevens = Array(text).indices.filter { Array(text)[$0] == "7" }
        let one = event(.numberRow, text, .oppositeShift, typo: [sevens[0]: "8", sevens[2]: "6"], at: 0)
        #expect(!kinds([one]).contains(.missedCharacters))
        let two = event(.numberRow, text, .oppositeShift, typo: [sevens[1]: "8", sevens[3]: "6"], at: 1)
        let missed = MechanicsRecommender.recommendations(from: [one, two]).first { $0.kind == .missedCharacters }
        #expect(missed?.title == "Practise \u{201C}7\u{201D}")
        #expect(missed?.drill == .numberRow)
    }

    @Test func switchingMethodsForTheSameLengthSuggestsTheLab() {
        let events = (UInt64(1)...4).map { seed -> MechanicsEvent in
            let base = event(.labFreeChoice, MechanicsCatalog.labPassage(seed: seed), .oppositeShift, at: Int(seed))
            var result = base.result
            // Single capitals: one with Shift, one with Caps Lock in every round.
            var seenSingle = false
            result.segments = result.segments?.map { segment in
                var s = segment
                if s.length == 1 { if seenSingle { s.method = .capsLock }; seenSingle = true }
                return s
            }
            return MechanicsEvent(id: base.id, date: base.date, drill: base.drill, result: result)
        }
        let lab = MechanicsRecommender.recommendations(from: events).first { $0.kind == .inconsistentStrategy }
        #expect(lab?.area == .capitalisationLab)
        #expect(lab?.title.contains("1-letter") == true)
        // Methods that the drill required do not count as a choice.
        let required = events.map { MechanicsEvent(id: $0.id, date: $0.date, drill: .labShiftOnly, result: $0.result) }
        #expect(!kinds(required).contains(.inconsistentStrategy))
    }

    @Test func onlyRecentRoundsAndAtMostThree() {
        let text = MechanicsCatalog.labPassage(seed: 1)
        let old = (0..<2).map { event(.labShiftOnly, text, .oppositeShift, extra: runDelays(text, entry: 0.2, exit: 0.2), at: $0) }
        let fresh = (0..<MechanicsRecommender.window).map { event(.labShiftOnly, text, .oppositeShift, at: $0 + 10) }
        #expect(kinds(old + fresh).isEmpty, "slow rounds older than the window no longer count")

        let everything = (0..<2).map {
            event(.labFreeChoice, text, .oppositeShift, extra: runDelays(text, entry: 0.3, exit: 0.3), at: $0)
        }
        #expect(kinds(everything).count <= MechanicsRecommender.limit)
    }
}

@Suite struct MechanicsHistoryTests {
    /// One Lab comparison on passage `seed`: Shift costs `shiftPerCapital` before
    /// every capital; Caps Lock costs `capsSwitch` for each switch on and off.
    /// `jitter` adds deterministic noise to each run.
    private func comparison(seed: UInt64, minute: Int, shiftPerCapital: Double, capsSwitch: Double,
                            jitter: Double = 0) -> [MechanicsEvent] {
        let text = MechanicsCatalog.labPassage(seed: seed)
        let chars = Array(text)
        var shiftExtra: [Int: Double] = [:], capsExtra: [Int: Double] = [:]
        var n = 0
        for i in chars.indices where CaseRequirement.of(chars[i]) == .uppercaseLetter {
            let run = MechanicsDrill.uppercaseRun(around: i, in: chars)
            let noise = jitter * Double((n * 7 + Int(seed)) % 5 - 2) / 2
            shiftExtra[i] = shiftPerCapital + (i == run.lowerBound ? noise : 0)
            if i == run.lowerBound {
                capsExtra[i, default: 0] += capsSwitch + noise
                n += 1
            }
            if i == run.upperBound { capsExtra[i + 1, default: 0] += capsSwitch }
        }
        let id = UUID()
        let shiftFirst = seed.isMultiple(of: 2)
        func round(_ drill: MechanicsDrill, _ technique: Technique, _ extra: [Int: Double], order: Int, offset: Int) -> MechanicsEvent {
            let (session, strokes) = simulate(text, technique: technique, gap: 0.15, extra: extra)
            var result = MechanicsAnalyzer.analyze(session, strokes: strokes, drill: drill)
            result.comparisonID = id
            result.comparisonOrder = order
            return MechanicsEvent(date: Date(timeIntervalSince1970: Double(minute * 10 + offset) * 60), drill: drill, result: result)
        }
        return [round(.labShiftOnly, .oppositeShift, shiftExtra, order: shiftFirst ? 1 : 2, offset: shiftFirst ? 0 : 1),
                round(.labCapsLockOnly, .capsLock, capsExtra, order: shiftFirst ? 2 : 1, offset: shiftFirst ? 1 : 0)]
    }

    @Test func emptyHistory() {
        let history = MechanicsHistory(events: [])
        #expect(history.rounds == 0 && history.comparisonsDone == 0)
        #expect(history.recentCharacterAccuracy == nil)
        #expect(history.methodComparison.allSatisfy { $0.verdict == .insufficient })
        #expect(history.methodSummary.hasPrefix("No comparisons yet"))
    }

    @Test func summaryFiguresAreWeightedAndCountStages() {
        let events = (0..<3).flatMap { comparison(seed: UInt64($0 + 1), minute: $0, shiftPerCapital: 0.05, capsSwitch: 0.05) }
        let history = MechanicsHistory(events: events)
        #expect(history.rounds == 6)
        #expect(history.recentCharacterAccuracy == 1)
        #expect(history.recentTechniqueAccuracy == 1)
        #expect(history.stages == MechanicsDrill.allCases.count - 3, "the Lab has no steady stages")
        #expect(history.steadyStages == 0)
        #expect(history.points.count == 6)
        #expect(history.overheadPoints.count == 6, "every round has 10 timed runs")
    }

    @Test func theFasterMethodCanDependOnLength() {
        // Shift: +60 ms for every capital. Caps Lock: +80 ms on and +80 ms off, whatever the length.
        let events = (0..<4).flatMap { comparison(seed: UInt64($0 + 1), minute: $0, shiftPerCapital: 0.06, capsSwitch: 0.08) }
        let history = MechanicsHistory(events: events)
        #expect(history.comparisonsDone == 4)
        let verdicts = Dictionary(uniqueKeysWithValues: history.methodComparison.map { ($0.group, $0.verdict) })
        #expect(verdicts[.one] == .shiftFaster)        //  60 vs 160
        #expect(verdicts[.two] == .shiftFaster)        // 120 vs 160
        #expect(verdicts[.fiveSeven] == .capsLockFaster)
        #expect(verdicts[.eightPlus] == .capsLockFaster)
        #expect(history.methodSummary.contains("Caps Lock has been faster"))
        #expect(history.methodSummary.contains("Shift has been faster"))
        #expect(history.methodSummary.contains("8+-letter"))
    }

    @Test func overlappingResultsAreNoClearDifference() {
        let events = (0..<6).flatMap {
            comparison(seed: UInt64($0 + 1), minute: $0, shiftPerCapital: 0, capsSwitch: 0, jitter: 0.12)
        }
        let history = MechanicsHistory(events: events)
        #expect(history.methodComparison.contains { $0.verdict == .noClearDifference })
        #expect(!history.methodComparison.contains { $0.verdict == .shiftFaster || $0.verdict == .capsLockFaster })
        #expect(history.methodSummary == "Neither method is consistently faster yet.")
    }

    @Test func tooFewComparisonsSaySo() {
        let events = (0..<3).flatMap { comparison(seed: UInt64($0 + 1), minute: $0, shiftPerCapital: 0.06, capsSwitch: 0.08) }
        let history = MechanicsHistory(events: events)
        #expect(history.methodComparison.allSatisfy { $0.verdict == .insufficient })
        #expect(history.methodSummary.hasPrefix("Not enough comparisons yet: 3 done"))
    }

    @Test func onlyLabComparisonsFeedTheMethodComparison() {
        // Plenty of Shift and Caps Lock rounds, but none of them paired comparisons.
        let unpaired = (0..<6).flatMap { index -> [MechanicsEvent] in
            comparison(seed: UInt64(index + 1), minute: index, shiftPerCapital: 0.06, capsSwitch: 0.08).map { event in
                var result = event.result
                result.comparisonID = nil
                return MechanicsEvent(date: event.date, drill: event.drill == .labShiftOnly ? .capitalisedWords : .uppercaseBlocks,
                                      result: result)
            }
        }
        let history = MechanicsHistory(events: unpaired)
        #expect(history.comparisonsDone == 0)
        #expect(history.methodComparison.allSatisfy { $0.verdict == .insufficient })
        #expect(history.overhead[.shift]?.isSufficient == true, "overhead itself still pools every round")
    }
}
