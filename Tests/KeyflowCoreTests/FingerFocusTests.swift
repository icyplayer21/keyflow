import Foundation
import Testing
@testable import KeyflowCore

@Suite struct FingerKeyMappingTests {
    @Test func trainedKeysMatchUSQwertyTouchTyping() {
        #expect(FingerFocusTarget.leftPinky.keys == ["a", "q", "z"])
        #expect(FingerFocusTarget.leftRing.keys == ["s", "w", "x"])
        #expect(FingerFocusTarget.rightRing.keys == ["l", "o", "."])
        #expect(FingerFocusTarget.rightPinky.keys == [";", "p", "/"])
        #expect(FingerFocusTarget.bothPinkies.keys == ["a", "q", "z", ";", "p", "/"])
        #expect(FingerFocusTarget.bothRings.keys == ["s", "w", "x", "l", "o", "."])
    }

    @Test(arguments: Finger.allCases)
    func everyKeyBelongsToItsFingerInTheSharedMap(finger: Finger) {
        for key in FingerKeys.keys(for: finger) {
            #expect(FingerMap.finger(for: key) == finger, "\(key) should be the \(finger.title)")
        }
    }

    @Test(arguments: Finger.allCases)
    func keysAreListedHomeTopBottom(finger: Finger) {
        let keys = FingerKeys.keys(for: finger)
        guard keys.count >= 3 else { return }
        #expect(KeyboardLayout.position(of: keys[0])?.row == 2)
        #expect(KeyboardLayout.position(of: keys[1])?.row == 1)
        #expect(KeyboardLayout.position(of: keys[2])?.row == 3)
        #expect(keys[0] == finger.homeKey)
    }

    @Test(arguments: Finger.allCases)
    func neighboursAreMutualAndOnTheSameHand(finger: Finger) {
        for neighbour in FingerKeys.neighbours(of: finger) {
            #expect(neighbour.hand == finger.hand)
            #expect(FingerKeys.neighbours(of: neighbour).contains(finger))
        }
    }

    @Test func primaryTargetsAreRingFingersAndPinkies() {
        let allowed: Set<Finger> = [.leftPinky, .leftRing, .rightRing, .rightPinky]
        for target in FingerFocusTarget.primary {
            #expect(Set(target.fingers).isSubset(of: allowed))
        }
        // Every finger but the thumb has a single-finger target.
        for finger in Finger.allCases where finger != .thumb {
            #expect(FingerFocusTarget.single(finger)?.fingers == [finger])
        }
        #expect(FingerFocusTarget.single(.thumb) == nil)
        #expect(FingerFocusTarget.bothPinkies.fingers == [.leftPinky, .rightPinky])
        #expect(FingerFocusTarget.bothRings.fingers == [.leftRing, .rightRing])
    }
}

@Suite struct FingerFocusGeneratorTests {
    private func units(_ exercise: FingerFocusExercise) -> [String] {
        exercise.text.split(separator: " ").map(String.init)
    }

    private static let all: [(FingerFocusTarget, FingerFocusLevel)] =
        FingerFocusTarget.allCases.flatMap { target in FingerFocusLevel.allCases.map { (target, $0) } }

    @Test func isDeterministicForASeed() {
        for (target, level) in Self.all {
            let a = FingerFocusGenerator.exercise(target: target, level: level, seed: 42)
            let b = FingerFocusGenerator.exercise(target: target, level: level, seed: 42)
            #expect(a == b)
        }
    }

    @Test func roundsAreShortButNotTrivial() {
        for (target, level) in Self.all {
            for complexity in 0...FingerFocusGenerator.maxComplexity {
                for seed in UInt64(1)...5 {
                    let text = FingerFocusGenerator.exercise(target: target, level: level, complexity: complexity, seed: seed).text
                    #expect((24...160).contains(text.count), "\(target) \(level) c\(complexity): \(text.count) characters")
                    #expect(!text.contains("  ") && text.first != " " && text.last != " ")
                }
            }
        }
    }

    @Test(arguments: FingerFocusTarget.allCases)
    func activationRepeatsOnlyTargetKeys(target: FingerFocusTarget) {
        let exercise = FingerFocusGenerator.exercise(target: target, level: .activation, seed: 3)
        #expect(exercise.keys == Set(target.keys))
        for unit in units(exercise) {
            #expect(unit.count == FingerFocusGenerator.runLength)
            #expect(Set(unit).count == 1)
        }
    }

    @Test func activationWithComplexityAlternatesKeysWithHome() {
        let exercise = FingerFocusGenerator.exercise(target: .leftPinky, level: .activation, complexity: 1, seed: 3)
        #expect(exercise.text.contains("aaa qqq aaa qqq"))
        #expect(exercise.text.contains("aaa zzz aaa zzz"))
    }

    @Test(arguments: FingerFocusTarget.allCases)
    func coordinationPairsATargetKeyWithANeighbour(target: FingerFocusTarget) {
        let targets = Set(target.keys)
        let neighbours = Set(target.neighbourKeys)
        for complexity in 0...FingerFocusGenerator.maxComplexity {
            let exercise = FingerFocusGenerator.exercise(target: target, level: .coordination, complexity: complexity, seed: 9)
            #expect(exercise.keys.isSubset(of: target.drillKeys))
            for unit in units(exercise) {
                #expect(unit.contains(where: targets.contains), "\(unit) has no target key")
                #expect(unit.contains(where: neighbours.contains), "\(unit) has no neighbouring key")
                if complexity == 0 { #expect(unit.count == 2) }
            }
        }
    }

    @Test func coordinationMatchesTheExamples() {
        let left = FingerFocusGenerator.coordinationPairs(.leftPinky)
        #expect(left == ["as", "qw", "zx"])
        let right = FingerFocusGenerator.coordinationPairs(.rightPinky)
        #expect(right == [";l", "po", "/."])
        let text = FingerFocusGenerator.exercise(target: .leftPinky, level: .coordination, seed: 1).text
        #expect(text.contains("as sa as sa"))
        // Home-row pairs are always included.
        for target in FingerFocusTarget.allCases {
            let homePairs = FingerFocusGenerator.coordinationPairs(target).filter { pair in
                pair.allSatisfy { KeyboardLayout.position(of: $0)?.row == 2 }
            }
            let units = Set(units(FingerFocusGenerator.exercise(target: target, level: .coordination, seed: 5)))
            for pair in homePairs { #expect(units.contains(pair)) }
        }
    }

    @Test func coordinationGetsMoreComplexGradually() {
        let basic = FingerFocusGenerator.exercise(target: .leftRing, level: .coordination, complexity: 0, seed: 4)
        let rolls = FingerFocusGenerator.exercise(target: .leftRing, level: .coordination, complexity: 1, seed: 4)
        let diagonals = FingerFocusGenerator.exercise(target: .leftRing, level: .coordination, complexity: 2, seed: 4)
        #expect(units(basic).allSatisfy { $0.count == 2 })
        #expect(units(rolls).contains { $0.count == 3 })
        // Diagonal reaches cross rows: a key and a neighbour's key on different rows.
        let crossesRows = units(diagonals).contains { unit in
            unit.count == 2 && KeyboardLayout.position(of: unit.first!)?.row != KeyboardLayout.position(of: unit.last!)?.row
        }
        #expect(crossesRows)
    }

    @Test(arguments: FingerFocusTarget.allCases)
    func movementStaysWithinOneFingersKeys(target: FingerFocusTarget) {
        for complexity in 0...FingerFocusGenerator.maxComplexity {
            let exercise = FingerFocusGenerator.exercise(target: target, level: .movement, complexity: complexity, seed: 11)
            for unit in units(exercise) {
                let fingers = Set(unit.compactMap(FingerMap.finger(for:)))
                #expect(fingers.count == 1, "\(unit) mixes fingers")
                #expect(fingers.isSubset(of: Set(target.fingers)))
                #expect(Set(unit).count >= 2, "\(unit) does not move")
            }
        }
    }

    @Test func movementMatchesTheExamples() {
        #expect(FingerFocusGenerator.movementPairs(.leftPinky) == ["aq", "az", "qz"])
        #expect(FingerFocusGenerator.movementPairs(.rightRing) == ["lo", "l.", "o."])
        #expect(FingerFocusGenerator.movementPairs(.rightPinky) == [";p", ";/", "p/"])
        let units = Set(units(FingerFocusGenerator.exercise(target: .leftPinky, level: .movement, seed: 2)))
        #expect(units.isSuperset(of: ["aq", "qa", "az", "za"]))
        let complex = Set(self.units(FingerFocusGenerator.exercise(target: .leftPinky, level: .movement, complexity: 2, seed: 2)))
        #expect(complex.isSuperset(of: ["qaz", "zaq", "aqa", "aza"]))
    }

    @Test(arguments: FingerFocusTarget.allCases)
    func wordsAreRealAndRichInTargetLetters(target: FingerFocusTarget) {
        let letters = Set(target.keys.filter(\.isLetter))
        let dictionary = Set(TrainingWords.all)
        // How often the target letters appear across the whole word list.
        let all = TrainingWords.all.joined()
        let baseline = Double(all.filter(letters.contains).count) / Double(all.count)

        for seed in UInt64(1)...5 {
            let exercise = FingerFocusGenerator.exercise(target: target, level: .words, seed: seed)
            let words = units(exercise)
            #expect(words.count == FingerFocusGenerator.wordsPerRound)
            for word in words {
                let bare = word.filter(\.isLetter)
                #expect(dictionary.contains(bare), "\(bare) is not a known word")
                #expect(bare.contains(where: letters.contains), "\(bare) has no target letter")
            }
            let typed = exercise.text.filter(\.isLetter)
            let share = Double(typed.filter(letters.contains).count) / Double(typed.count)
            #expect(share > baseline * 2, "\(target): \(share) vs \(baseline)")
        }
    }

    @Test func wordsUseTheRightHandPunctuationKeys() {
        let ring = FingerFocusGenerator.exercise(target: .rightRing, level: .words, seed: 1).text
        #expect(ring.contains("."))
        #expect(!ring.contains(";"))
        let pinky = FingerFocusGenerator.exercise(target: .rightPinky, level: .words, seed: 1).text
        #expect(pinky.contains(";"))
        let left = FingerFocusGenerator.exercise(target: .leftPinky, level: .words, seed: 1).text
        #expect(left.allSatisfy { $0.isLetter || $0 == " " })
    }

    @Test func focusAddsPracticeForAMissedKey() {
        let plain = FingerFocusGenerator.exercise(target: .leftPinky, level: .activation, seed: 8)
        let focused = FingerFocusGenerator.exercise(target: .leftPinky, level: .activation,
                                                    focus: [FocusItem(item: "z", level: 2)], seed: 8)
        let count = { (exercise: FingerFocusExercise) in exercise.text.split(separator: " ").filter { $0 == "zzz" }.count }
        #expect(count(focused) == count(plain) + 2 * FingerFocusGenerator.unitsPerBlock)
        #expect(focused.focus == [FocusItem(item: "z", level: 2)])
    }

    @Test func focusAtHigherLevelsIntroducesHarderTransitions() {
        let easy = FingerFocusGenerator.exercise(target: .leftPinky, level: .movement,
                                                 focus: [FocusItem(item: "z", level: 1)], seed: 8)
        let hard = FingerFocusGenerator.exercise(target: .leftPinky, level: .movement,
                                                 focus: [FocusItem(item: "z", level: 2)], seed: 8)
        #expect(!units(easy).contains("aza"))
        #expect(units(hard).contains("aza"))
    }

    @Test func focusIsCappedAndIgnoresOtherFingers() {
        let focus = [FocusItem(item: "a", level: 3), FocusItem(item: "q", level: 3), FocusItem(item: "z", level: 3),
                     FocusItem(item: "k", level: 3), FocusItem(item: "jk", level: 3)]
        let plain = FingerFocusGenerator.exercise(target: .leftPinky, level: .activation, seed: 8)
        let focused = FingerFocusGenerator.exercise(target: .leftPinky, level: .activation, focus: focus, seed: 8)
        let added = units(focused).count - units(plain).count
        #expect(added == FingerFocusGenerator.maxFocusBlocks * FingerFocusGenerator.unitsPerBlock)
        #expect(!focused.text.contains("k"))
        #expect(!focused.focus.contains { $0.item == "k" || $0.item == "jk" })
    }

    @Test func coordinationFocusOnATransitionAddsThatTransition() {
        let exercise = FingerFocusGenerator.exercise(target: .rightPinky, level: .coordination,
                                                     focus: [FocusItem(item: "po", level: 1)], seed: 3)
        #expect(exercise.focus.map(\.item) == ["po"])
        // Basic "op" alternation appears once; the focus adds a second block.
        #expect(exercise.text.components(separatedBy: "po op po op").count - 1 >= 2)
    }
}

@Suite struct FingerFocusTrackerTests {
    private func result(_ accuracy: Double, keys: [String: ErrorCount] = [:]) -> RoundResult {
        let keystrokes = 50
        return RoundResult(text: "aq", accuracy: accuracy, keystrokes: keystrokes,
                           correctKeystrokes: Int((accuracy * Double(keystrokes)).rounded()),
                           backspaces: 0, duration: 20, keys: keys)
    }

    private func event(_ target: FingerFocusTarget, _ level: FingerFocusLevel, _ accuracy: Double,
                       keys: [String: ErrorCount] = [:], minute: Int) -> FingerFocusEvent {
        FingerFocusEvent(date: Date(timeIntervalSince1970: TimeInterval(minute * 60)), target: target, level: level,
                         result: result(accuracy, keys: keys))
    }

    @Test func startsAtActivation() {
        let tracker = FingerFocusTracker(events: [])
        for target in FingerFocusTarget.allCases {
            #expect(tracker.recommendedLevel(target) == .activation)
            #expect(tracker.complexity(target, .activation) == 0)
        }
    }

    @Test func threeAccurateRoundsMakeALevelSteadyAndMoveTheRecommendationOn() {
        var events = [
            event(.leftPinky, .activation, 0.97, minute: 0),
            event(.leftPinky, .activation, 0.80, minute: 1),
            event(.leftPinky, .activation, 0.96, minute: 2),
        ]
        #expect(FingerFocusTracker(events: events).recommendedLevel(.leftPinky) == .activation)
        events.append(event(.leftPinky, .activation, 1.0, minute: 3))
        let tracker = FingerFocusTracker(events: events)
        #expect(tracker.progress(.leftPinky, .activation).isSteady)
        #expect(tracker.progress(.leftPinky, .activation).rounds == 4)
        #expect(tracker.recommendedLevel(.leftPinky) == .coordination)
        // Other fingers are unaffected.
        #expect(tracker.recommendedLevel(.leftRing) == .activation)
        #expect(tracker.rounds(.leftRing) == 0)
    }

    @Test func complexityGrowsWithQualifyingRounds() {
        let events = (0..<5).map { event(.rightRing, .movement, 0.98, minute: $0) }
        #expect(FingerFocusTracker(events: Array(events.prefix(1))).complexity(.rightRing, .movement) == 0)
        #expect(FingerFocusTracker(events: Array(events.prefix(2))).complexity(.rightRing, .movement) == 1)
        #expect(FingerFocusTracker(events: events).complexity(.rightRing, .movement) == FingerFocusGenerator.maxComplexity)
        #expect(FingerFocusTracker(events: events).complexity(.rightRing, .activation) == 0)
    }

    @Test func repeatedMissesBecomeARecommendationAtTheLevelTheyHappen() {
        let missedZ = ["z": ErrorCount(attempts: 12, errors: 3), "a": ErrorCount(attempts: 12, errors: 0)]
        let events = [
            event(.leftPinky, .activation, 0.99, keys: ["z": ErrorCount(attempts: 12, errors: 0)], minute: 0),
            event(.leftPinky, .movement, 0.9, keys: missedZ, minute: 1),
            event(.leftPinky, .movement, 0.9, keys: missedZ, minute: 2),
        ]
        let tracker = FingerFocusTracker(events: events)
        let recommendations = tracker.recommendations(.leftPinky)
        #expect(recommendations.map(\.key) == ["z"])
        #expect(recommendations.first?.level == .movement)
        #expect(recommendations.first?.count == ErrorCount(attempts: 36, errors: 6))
        // And adaptive repetition puts the key in focus.
        #expect(tracker.adaptive(for: .leftPinky).focusItems().contains { $0.item == "z" })
    }

    @Test func aSingleSlipIsNotARecommendation() {
        let events = [event(.leftPinky, .activation, 0.98, keys: ["q": ErrorCount(attempts: 20, errors: 1)], minute: 0)]
        #expect(FingerFocusTracker(events: events).recommendations(.leftPinky).isEmpty)
    }

    @Test func keyStatsCoverOnlyRecentRounds() {
        var events = (0..<FingerFocusTracker.recentRounds).map {
            event(.leftRing, .activation, 1, keys: ["w": ErrorCount(attempts: 10, errors: 0)], minute: $0 + 10)
        }
        events.insert(event(.leftRing, .activation, 0.5, keys: ["w": ErrorCount(attempts: 10, errors: 9)], minute: 0), at: 0)
        let stats = FingerFocusTracker(events: events).keyStats(.leftRing)
        #expect(stats.map(\.key) == ["s", "w", "x"])
        #expect(stats.allSatisfy { $0.recommendedFinger == .leftRing })
        #expect(stats[1].count == ErrorCount(attempts: 10 * FingerFocusTracker.recentRounds, errors: 0))
        #expect(stats[0].accuracy == nil)
    }

    @Test func focusIgnoresKeysOutsideTheTarget() {
        let keys = ["k": ErrorCount(attempts: 10, errors: 5), "a": ErrorCount(attempts: 10, errors: 5)]
        let tracker = FingerFocusTracker(events: [event(.leftPinky, .words, 0.8, keys: keys, minute: 0)])
        let items = tracker.adaptive(for: .leftPinky).focusItems().map(\.item)
        #expect(items == ["a"])
    }
}

@MainActor
@Suite struct FingerFocusStoreTests {
    private func sample() -> RoundResult {
        RoundResult(text: "aaa qqq", accuracy: 0.96, keystrokes: 25, correctKeystrokes: 24, backspaces: 1, duration: 8,
                    keys: ["a": ErrorCount(attempts: 12, errors: 0), "q": ErrorCount(attempts: 12, errors: 1)])
    }

    @Test func roundsRoundTripWithoutTouchingLessonHistory() throws {
        let store = try TrainingStore.inMemory()
        let lesson = TrainingEvent(category: .homeRow, stage: .singleKeys, kind: .skip)
        let finger = FingerFocusEvent(target: .bothPinkies, level: .movement, result: sample())
        try store.record(lesson)
        try store.record(finger)
        #expect(store.events == [lesson])
        #expect(store.fingerFocusEvents == [finger])
    }

    @Test func roundsSurviveReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "keyflow-finger-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "MuscleMemory.store")
        let event = FingerFocusEvent(date: Date(timeIntervalSince1970: 1_000), target: .rightPinky, level: .words, result: sample())
        let lesson = TrainingEvent(date: Date(timeIntervalSince1970: 500), category: .topRow, stage: .patterns, kind: .skip)
        do {
            let store = try TrainingStore.onDisk(at: url)
            try store.record(lesson)
            try store.record(event)
        }
        let reopened = try TrainingStore.onDisk(at: url)
        #expect(reopened.fingerFocusEvents == [event])
        #expect(reopened.events == [lesson])
    }
}
