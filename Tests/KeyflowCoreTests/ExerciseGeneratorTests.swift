import Foundation
import Testing
@testable import KeyflowCore

private let allCategories = TrainingCategory.allCases
private let allStages = TrainingStage.allCases

/// Splits text into runs of identical consecutive tokens: "fj fj dk" → [("fj", 2), ("dk", 1)].
private func runs(_ text: String) -> [(token: String, count: Int)] {
    var result: [(token: String, count: Int)] = []
    for token in text.split(separator: " ").map(String.init) {
        if let last = result.last, last.token == token {
            result[result.count - 1].count += 1
        } else {
            result.append((token, 1))
        }
    }
    return result
}

private func isClean(_ text: String) -> Bool {
    !text.isEmpty && !text.hasPrefix(" ") && !text.hasSuffix(" ") && !text.contains("  ")
}

@Suite struct AllowedKeyTests {
    @Test(arguments: allCategories)
    func everyExerciseUsesOnlyTheCategorysKeys(category: TrainingCategory) {
        let allowed = category.allowedKeys.union([" "])
        for stage in allStages {
            for qualifying in 0...3 {
                for seed in UInt64(0)..<15 {
                    let text = ExerciseGenerator.exercise(category: category, stage: stage, qualifyingRounds: qualifying, seed: seed).text
                    let outside = text.filter { !allowed.contains($0) }
                    #expect(outside.isEmpty, "\(category) \(stage) seed \(seed): \(outside)")
                    #expect(isClean(text))
                }
            }
        }
    }

    @Test(arguments: allCategories)
    func drillsUseOnlyKeysIntroducedSoFar(category: TrainingCategory) {
        for stage in [TrainingStage.singleKeys, .transitions, .patterns] {
            for qualifying in 0...3 {
                let count = ExerciseGenerator.activeGroupCount(groups: category.keyGroups.count, qualifyingRounds: qualifying)
                let permitted = ExerciseGenerator.permittedKeys(groups: Array(category.keyGroups.prefix(count)),
                                                                allowed: category.allowedKeys)
                for seed in UInt64(0)..<15 {
                    let exercise = ExerciseGenerator.exercise(category: category, stage: stage, qualifyingRounds: qualifying, seed: seed)
                    let unexpected = exercise.keys.subtracting(permitted)
                    #expect(unexpected.isEmpty, "\(category) \(stage) q\(qualifying): \(unexpected)")
                }
            }
        }
    }

    @Test func homeRowStartsWithoutItsLastTwoGroups() {
        for seed in UInt64(0)..<20 {
            for stage in [TrainingStage.singleKeys, .transitions, .patterns] {
                let keys = ExerciseGenerator.exercise(category: .homeRow, stage: stage, qualifyingRounds: 0, seed: seed).keys
                #expect(keys.isDisjoint(with: ["a", ";", "g", "h"]))
            }
        }
    }

    @Test func groupsAreAddedOnePerQualifyingRound() {
        #expect(ExerciseGenerator.activeGroupCount(groups: 5, qualifyingRounds: 0) == 3)
        #expect(ExerciseGenerator.activeGroupCount(groups: 5, qualifyingRounds: 1) == 4)
        #expect(ExerciseGenerator.activeGroupCount(groups: 5, qualifyingRounds: 2) == 5)
        #expect(ExerciseGenerator.activeGroupCount(groups: 5, qualifyingRounds: 9) == 5)
        #expect(ExerciseGenerator.activeGroupCount(groups: 4, qualifyingRounds: 0) == 2)
        #expect(ExerciseGenerator.activeGroupCount(groups: 1, qualifyingRounds: 0) == 1)
        #expect(ExerciseGenerator.activeGroupCount(groups: 0, qualifyingRounds: 3) == 0)

        // The newest group is always practised.
        for seed in UInt64(0)..<10 {
            let first = ExerciseGenerator.exercise(category: .homeRow, stage: .singleKeys, qualifyingRounds: 0, seed: seed)
            #expect(first.newKeys == ["s", "l"])
            #expect(first.keys.isSuperset(of: ["s", "l"]))
            let later = ExerciseGenerator.exercise(category: .homeRow, stage: .singleKeys, qualifyingRounds: 2, seed: seed)
            #expect(later.newKeys == ["g", "h"])
            #expect(later.keys.isSuperset(of: ["g", "h"]))
        }
    }

    @Test func reachDrillsStartFromTheHomeRow() {
        for seed in UInt64(0)..<10 {
            let text = ExerciseGenerator.exercise(category: .topRow, stage: .patterns, seed: seed).text
            let tokens = Set(text.split(separator: " ").map(String.init))
            let reaches: Set<String> = ["frf", "juj", "ded", "kik", "sws", "lol"]
            #expect(!tokens.isDisjoint(with: reaches))
        }
    }

    @Test func permittedKeysAddEachKeysHomeRowAnchor() {
        let permitted = ExerciseGenerator.permittedKeys(groups: [["r", "u"]], allowed: TrainingCategory.topRow.allowedKeys)
        #expect(permitted == ["r", "u", "f", "j"])
        // An anchor outside the allowed set is not added.
        #expect(ExerciseGenerator.permittedKeys(groups: [["r", "u"]], allowed: ["r", "u"]) == ["r", "u"])
    }
}

@Suite struct ExerciseFormatTests {
    @Test(arguments: allCategories)
    func singleKeysRepeatEachKeyFourTimes(category: TrainingCategory) {
        for seed in UInt64(0)..<10 {
            let text = ExerciseGenerator.exercise(category: category, stage: .singleKeys, seed: seed).text
            for token in text.split(separator: " ") {
                #expect(token.count == 4 && Set(token).count == 1, "\(token)")
            }
        }
    }

    @Test func singleKeysMatchTheExampleLayout() {
        let text = ExerciseGenerator.exercise(category: .homeRow, stage: .singleKeys, seed: 1).text
        #expect(text.contains("ssss llll ssss llll"))
    }

    @Test(arguments: allCategories)
    func transitionsAlternateTwoKeysInRunsOfFour(category: TrainingCategory) {
        for seed in UInt64(0)..<10 {
            let text = ExerciseGenerator.exercise(category: category, stage: .transitions, seed: seed).text
            for run in runs(text) {
                #expect(run.token.count == 2, "\(run.token)")
                #expect(run.count.isMultiple(of: 4), "\(run.token) ×\(run.count)")
            }
            #expect(runs(text).count <= ExerciseGenerator.maxPairsPerRound + 1)
        }
    }

    @Test func homeRowTransitionsIncludeTheMirrorPairs() {
        let text = ExerciseGenerator.exercise(category: .homeRow, stage: .transitions, seed: 4).text
        #expect(text.contains("fj fj fj fj"))
        #expect(text.contains("dk dk dk dk"))
        #expect(text.contains("sl sl sl sl"))
    }

    @Test(arguments: allCategories)
    func patternsRepeatThreeTimes(category: TrainingCategory) {
        for seed in UInt64(0)..<10 {
            let text = ExerciseGenerator.exercise(category: category, stage: .patterns, seed: seed).text
            for run in runs(text) {
                #expect((2...4).contains(run.token.count), "\(run.token)")
                #expect(run.count.isMultiple(of: 3), "\(run.token) ×\(run.count)")
            }
        }
    }

    @Test func homeRowPatternsRollAcrossTheFingers() {
        let tokens = Set((0..<10).flatMap { seed in
            ExerciseGenerator.exercise(category: .homeRow, stage: .patterns, qualifyingRounds: 1, seed: UInt64(seed))
                .text.split(separator: " ").map(String.init)
        })
        #expect(tokens.contains("asdf") || tokens.contains("fdsa"))
        #expect(tokens.contains("jkl;") || tokens.contains(";lkj"))
    }

    @Test(arguments: allCategories)
    func drillsCoverEveryKeyTheyIntroduce(category: TrainingCategory) {
        for stage in [TrainingStage.singleKeys, .transitions, .patterns] {
            for seed in UInt64(0)..<10 {
                let exercise = ExerciseGenerator.exercise(category: category, stage: stage, seed: seed)
                #expect(exercise.keys.isSuperset(of: exercise.newKeys), "\(category) \(stage)")
            }
        }
    }

    @Test(arguments: allCategories)
    func exercisesAreAReasonableLength(category: TrainingCategory) {
        for stage in allStages {
            for seed in UInt64(0)..<10 {
                let count = ExerciseGenerator.exercise(category: category, stage: stage, seed: seed).text.count
                #expect((20...140).contains(count), "\(category) \(stage): \(count)")
            }
        }
    }

    @Test func sameSeedSameExerciseDifferentSeedDifferent() {
        for category in allCategories {
            for stage in allStages {
                let a = ExerciseGenerator.exercise(category: category, stage: stage, seed: 77)
                let b = ExerciseGenerator.exercise(category: category, stage: stage, seed: 77)
                #expect(a == b)
            }
        }
        let texts = Set((0..<10).map { ExerciseGenerator.exercise(category: .homeRow, stage: .words, seed: UInt64($0)).text })
        #expect(texts.count > 1)
    }
}

@Suite struct WordStageTests {
    @Test(arguments: allCategories)
    func everyCategoryHasEnoughRealWords(category: TrainingCategory) {
        let pool = ExerciseGenerator.wordPool(allowed: category.allowedKeys, targets: Set(category.keyGroups.joined()))
        #expect(pool.count >= 20, "\(category): \(pool.count)")

        for seed in UInt64(0)..<10 {
            let exercise = ExerciseGenerator.exercise(category: category, stage: .words, seed: seed)
            #expect(!exercise.isPracticePattern)
            let words = exercise.text.split(separator: " ").map(String.init)
            #expect(words.count == ExerciseGenerator.wordsPerRound)
            for word in words {
                #expect(TrainingWords.all.contains(word), "\(word)")
            }
            for (first, second) in zip(words, words.dropFirst()) {
                #expect(first != second)
            }
        }
    }

    @Test func homeRowWordsUseOnlyHomeRowLetters() {
        let category = TrainingCategory.homeRow
        let pool = ExerciseGenerator.wordPool(allowed: category.allowedKeys, targets: Set(category.keyGroups.joined()))
        let allowed = Set("asdfghjkl")
        #expect(pool.allSatisfy { word in word.allSatisfy { allowed.contains($0) } })
        #expect(pool.contains("salad") && pool.contains("flask"))
    }

    @Test func bottomRowPrefersWordsThatUseBottomRowKeys() {
        let targets = Set(TrainingCategory.bottomRow.keyGroups.joined())
        let pool = ExerciseGenerator.wordPool(allowed: TrainingCategory.bottomRow.allowedKeys, targets: targets)
        #expect(pool.allSatisfy { word in word.contains { targets.contains($0) } })
    }

    @Test func tooFewWordsFallsBackToLabelledPatterns() {
        var rng = SeededGenerator(seed: 1)
        let none = ExerciseGenerator.words(allowed: ["q", "z", "x"], targets: ["q"], focus: [], using: &rng)
        #expect(none == nil)

        // The pool needs at least eight distinct words.
        let small = ["ab", "ba", "aa", "bab", "abba", "baba", "abab"]
        #expect(ExerciseGenerator.words(allowed: ["a", "b"], targets: ["a"], focus: [], from: small, using: &rng) == nil)
        let enough = small + ["bb"]
        #expect(ExerciseGenerator.words(allowed: ["a", "b"], targets: ["a"], focus: [], from: enough, using: &rng) != nil)
    }

    @Test func wordListIsCleanAndUnique() {
        let words = TrainingWords.all
        #expect(Set(words).count == words.count)
        #expect(words.allSatisfy { word in (word == "a" || word.count >= 2) && word.allSatisfy { ("a"..."z").contains($0) } })
        #expect(!words.contains("i") && !words.contains("dont"))
        #expect(words.count > 500)
    }

    @Test func focusMakesWordsWithWeakKeysMoreLikely() {
        let focus = [FocusItem(item: "g", level: 3)]
        var plain = 0, focused = 0
        for seed in UInt64(0)..<30 {
            plain += ExerciseGenerator.exercise(category: .homeRow, stage: .words, seed: seed).text.filter { $0 == "g" }.count
            let exercise = ExerciseGenerator.exercise(category: .homeRow, stage: .words, focus: focus, seed: seed)
            focused += exercise.text.filter { $0 == "g" }.count
        }
        #expect(focused > plain * 2)
    }
}

@Suite struct FocusInjectionTests {
    @Test func aFocusKeyGetsExtraBlocksMatchingTheStage() {
        let focus = [FocusItem(item: "k", level: 2)]
        let base = ExerciseGenerator.exercise(category: .homeRow, stage: .singleKeys, seed: 3)
        let boosted = ExerciseGenerator.exercise(category: .homeRow, stage: .singleKeys, focus: focus, seed: 3)
        #expect(boosted.focus == focus)
        let extra = boosted.text.components(separatedBy: "kkkk").count - base.text.components(separatedBy: "kkkk").count
        #expect(extra == 4)        // two blocks of "kkkk kkkk"

        let transitions = ExerciseGenerator.exercise(category: .homeRow, stage: .transitions, focus: [FocusItem(item: "dk", level: 1)], seed: 3)
        #expect(transitions.text.components(separatedBy: "dk").count - 1 >= 8)
    }

    @Test func focusNeverIntroducesUnfamiliarKeys() {
        // "g" and "h" are not introduced on the first Home Row round; "q" is not a home-row key at all.
        let focus = [FocusItem(item: "g", level: 3), FocusItem(item: "q", level: 3), FocusItem(item: "hj", level: 3)]
        for stage in [TrainingStage.singleKeys, .transitions, .patterns] {
            for seed in UInt64(0)..<10 {
                let exercise = ExerciseGenerator.exercise(category: .homeRow, stage: stage, qualifyingRounds: 0, focus: focus, seed: seed)
                #expect(exercise.focus.isEmpty)
                #expect(exercise.keys.isDisjoint(with: ["g", "h", "q"]))
            }
        }
    }

    @Test func extraPracticeIsCapped() {
        let focus = ["f", "j", "d", "k", "s"].map { FocusItem(item: $0, level: 3) }
        let base = ExerciseGenerator.exercise(category: .homeRow, stage: .singleKeys, seed: 9)
        let boosted = ExerciseGenerator.exercise(category: .homeRow, stage: .singleKeys, focus: focus, seed: 9)
        #expect(boosted.focus.count <= ExerciseGenerator.maxFocusItems)
        let added = boosted.text.split(separator: " ").count - base.text.split(separator: " ").count
        #expect(added <= ExerciseGenerator.maxFocusBlocks * 2)
        #expect(added > 0)
    }

    @Test func levelZeroAndMalformedItemsAreIgnored() {
        let focus = [FocusItem(item: "k", level: 0), FocusItem(item: "", level: 2), FocusItem(item: "fjd", level: 2)]
        let base = ExerciseGenerator.exercise(category: .homeRow, stage: .patterns, seed: 5)
        let boosted = ExerciseGenerator.exercise(category: .homeRow, stage: .patterns, focus: focus, seed: 5)
        #expect(boosted.focus.isEmpty)
        #expect(boosted.text.split(separator: " ").count == base.text.split(separator: " ").count)
    }
}

@Suite struct FingerMapTests {
    @Test func homeRowFingers() {
        #expect(FingerMap.finger(for: "a") == .leftPinky)
        #expect(FingerMap.finger(for: "f") == .leftIndex)
        #expect(FingerMap.finger(for: "g") == .leftIndex)
        #expect(FingerMap.finger(for: "h") == .rightIndex)
        #expect(FingerMap.finger(for: ";") == .rightPinky)
        #expect(FingerMap.finger(for: " ") == .thumb)
        #expect(FingerMap.finger(for: "\u{00E9}") == nil)
    }

    @Test func upperCaseAndShiftedSymbolsUseTheirKeysFinger() {
        #expect(FingerMap.finger(for: "F") == .leftIndex)
        #expect(FingerMap.finger(for: ":") == .rightPinky)
        #expect(FingerMap.finger(for: "<") == .rightMiddle)
        #expect(FingerMap.finger(for: "!") == .leftPinky)
        #expect(KeyboardLayout.baseKey(for: "Q") == "q")
        #expect(KeyboardLayout.baseKey(for: "?") == "/")
    }

    @Test func everyKeyHasAFingerAndEachFingerItsHomeKey() {
        for key in KeyboardLayout.rows.joined() {
            #expect(FingerMap.finger(for: key.base) != nil, "\(key.base)")
        }
        for finger in Finger.allCases {
            if let home = finger.homeKey {
                #expect(FingerMap.finger(for: home) == finger)
                #expect(KeyboardLayout.position(of: home)?.row == 2)
            } else {
                #expect(finger == .thumb)
            }
        }
    }

    @Test func handsSplitDownTheMiddle() {
        #expect(Set("qwertasdfgzxcvb").allSatisfy { FingerMap.hand(for: $0) == .left })
        #expect(Set("yuiophjkl;nm,./").allSatisfy { FingerMap.hand(for: $0) == .right })
        #expect(FingerMap.hand(for: " ") == nil)
        #expect(TrainingCategory.leftHand.allowedKeys.allSatisfy { FingerMap.hand(for: $0) == .left })
        #expect(TrainingCategory.rightHand.allowedKeys.allSatisfy { FingerMap.hand(for: $0) == .right })
    }

    @Test func categoryGroupsAreConsistent() {
        for category in allCategories {
            let keys = category.keyGroups.joined()
            #expect(Set(keys).count == keys.count, "\(category) repeats a key")
            #expect(Set(keys).isSubset(of: category.allowedKeys), "\(category)")
        }
        #expect(Set(TrainingCategory.fullKeyboard.keyGroups.joined()) == TrainingCategory.fullKeyboard.allowedKeys)
    }
}
