import Foundation
import Testing
@testable import KeyflowCore

/// Types `target` with a fixed gap, applying `mistakes` (position → wrong
/// character, fixed with Backspace when `fix` is true).
private func typed(_ target: String, gap: Double = 0.2, gapFor: ((Character, Character) -> Double)? = nil,
                   mistakes: [Int: Character] = [:], fix: Bool = true) -> TypingSession {
    var engine = TypingEngine(target: target, configuration: .init(timeLimit: nil, finishesAtEndOfText: true))
    var time = 0.0
    var previous: Character?
    for (index, character) in Array(target).enumerated() {
        time += previous.map { gapFor?($0, character) ?? gap } ?? 0
        if let wrong = mistakes[index] {
            engine.insert(wrong, at: time)
            time += gap
            if !fix { previous = character; continue }
            engine.backspace(at: time)
            time += gap
        }
        engine.insert(character, at: time)
        previous = character
    }
    return engine.session(at: time + 0.01)
}

@Suite struct FingerMappingTests {
    @Test func tenFingersWithBothThumbsOnSpace() {
        #expect(HandFinger.allCases.count == 10)
        #expect(HandFinger.leftThumb.finger == .thumb && HandFinger.rightThumb.finger == .thumb)
        #expect(HandFinger.leftThumb.assignedKeys == [" "])
        #expect(Set(HandFinger.allCases.map(\.finger)) == Set(Finger.allCases))
        #expect(HandFinger.allCases.filter { $0.hand == .left }.count == 5)
    }

    @Test func assignedKeysFollowUSQwerty() {
        #expect(HandFinger.leftPinky.assignedKeys == ["`", "1", "q", "a", "z"])
        #expect(HandFinger.leftRing.assignedKeys == ["2", "w", "s", "x"])
        #expect(HandFinger.rightRing.assignedKeys == ["9", "o", "l", "."])
        #expect(Set(HandFinger.rightPinky.assignedKeys).isSuperset(of: ["0", "-", "=", "p", "[", "]", "\\", ";", "'", "/"]))
        #expect(Set(HandFinger.leftIndex.assignedKeys) == Set("45rtfgvb"))
    }

    @Test func everyKeyBelongsToExactlyOneFinger() {
        var seen: [Character: Finger] = [:]
        for finger in Finger.allCases {
            for key in FingerAssignment.keys(for: finger) {
                #expect(seen[key] == nil, "\(key) assigned twice")
                seen[key] = finger
                #expect(FingerMap.finger(for: key) == finger)
            }
        }
        for row in KeyboardLayout.rows { for key in row { #expect(seen[key.base] != nil, "\(key.base) unassigned") } }
    }

    @Test func trainingTargetsExistForEveryFingerButThumbs() {
        for finger in HandFinger.allCases {
            #expect((finger.trainingTarget == nil) == finger.isThumb)
            if let target = finger.trainingTarget { #expect(target.fingers == [finger.finger]) }
        }
    }

    @Test func transitionKinds() {
        #expect(FingerAnalyzer.kind(from: ("a", .leftPinky), to: ("a", .leftPinky)) == .repeatKey)
        #expect(FingerAnalyzer.kind(from: ("e", .leftMiddle), to: ("d", .leftMiddle)) == .sameFinger)
        #expect(FingerAnalyzer.kind(from: ("a", .leftPinky), to: ("s", .leftRing)) == .sameHand)
        #expect(FingerAnalyzer.kind(from: ("a", .leftPinky), to: ("l", .rightRing)) == .alternateHand)
        #expect(FingerAnalyzer.kind(from: ("a", .leftPinky), to: (" ", .thumb)) == .space)
    }
}

@Suite struct FingerAccountingTests {
    @Test func correctedAndUncorrectedMistakesAreCountedOnce() {
        // "aq": 'a' typed as x then fixed; 'q' typed as w and left.
        var engine = TypingEngine(target: "aq", configuration: .init(timeLimit: nil, finishesAtEndOfText: false))
        engine.insert("x", at: 0)
        engine.backspace(at: 0.2)
        engine.insert("a", at: 0.4)
        engine.insert("w", at: 0.6)
        let observation = FingerAnalyzer.observe(engine.session(at: 1))[.leftPinky]

        #expect(observation.presses == 3)
        #expect(observation.successful == 1)
        #expect(observation.incorrect == 2)
        #expect(observation.correctedErrors == 1)
        #expect(observation.uncorrectedErrors == 1)
        #expect(observation.keys["a"] == ErrorCount(attempts: 2, errors: 1))
        #expect(observation.keys["q"] == ErrorCount(attempts: 1, errors: 1))
    }

    @Test func twoWrongPressesAtOneSpotAreTwoPressesButOneMistypedSpot() {
        var engine = TypingEngine(target: "s", configuration: .init(timeLimit: nil, finishesAtEndOfText: false))
        engine.insert("x", at: 0)
        engine.backspace(at: 0.1)
        engine.insert("d", at: 0.2)
        engine.backspace(at: 0.3)
        engine.insert("s", at: 0.4)
        let observation = FingerAnalyzer.observe(engine.session(at: 0.5))[.leftRing]
        #expect(observation.incorrect == 2)
        #expect(observation.correctedErrors + observation.uncorrectedErrors == 1)
        #expect(observation.correctedErrors == 1)
        #expect(Double(observation.successful) / Double(observation.presses) == 1.0 / 3.0)
    }

    @Test func accuracyMatchesKeyflowsDefinition() {
        let session = typed("as as as", mistakes: [0: "x", 3: "x"])
        let observations = FingerAnalyzer.observe(session)
        let presses = observations.fingers.values.reduce(0) { $0 + $1.presses }
        let successful = observations.fingers.values.reduce(0) { $0 + $1.successful }
        let metrics = PerformanceCalculator.metrics(for: session)
        #expect(presses == metrics.totalKeystrokes)
        #expect(successful == metrics.correctKeystrokes)
    }

    @Test func timingSkipsShiftCorrectionsAndPauses() {
        // "aA a": the capital needs Shift; there is a 3 s pause before the last a.
        let session = typed("aaA a", gapFor: { _, next in next == "a" ? 0.2 : 0.2 })
        let pinky = FingerAnalyzer.observe(session)[.leftPinky]
        // Timed: a→a (repeat) only; a→A and A→space excluded for Shift.
        #expect(pinky.timing[.repeatKey]?.count == 1)
        #expect(pinky.presses == 4)

        var engine = TypingEngine(target: "as", configuration: .init(timeLimit: nil, finishesAtEndOfText: true))
        engine.insert("a", at: 0)
        engine.insert("s", at: 3.5)
        #expect(FingerAnalyzer.observe(engine.session(at: 4))[.leftRing].timingSamples == 0)

        engine = TypingEngine(target: "as", configuration: .init(timeLimit: nil, finishesAtEndOfText: true))
        engine.insert("x", at: 0)
        engine.backspace(at: 0.1)
        engine.insert("a", at: 0.2)
        engine.insert("s", at: 0.4)
        #expect(FingerAnalyzer.observe(engine.session(at: 0.5))[.leftRing].timing[.sameHand]?.count == 1)
    }

    @Test func spaceIsCreditedToTheThumbs() {
        let observations = FingerAnalyzer.observe(typed("a s"))
        #expect(observations[.thumb].presses == 1)
        #expect(observations[.leftRing].timing[.space]?.count == 1)
    }
}

/// Builds observations directly, for classification tests.
private func observation(presses: Int, errors: Int, timing: [TransitionKind: (count: Int, mean: Double, spread: Double)] = [:],
                         keys: [Character: ErrorCount] = [:]) -> FingerObservation {
    var result = FingerObservation()
    result.presses = presses
    result.incorrect = errors
    result.successful = presses - errors
    result.keys = keys
    for (kind, spec) in timing {
        var sums = LatencySums()
        for index in 0..<spec.count {
            sums.add(spec.mean + (index.isMultiple(of: 2) ? spec.spread : -spec.spread))
        }
        result.timing[kind] = sums
    }
    return result
}

private func everyone(presses: Int = 400, errors: Int = 8, timing: Int = 120) -> FingerObservations {
    var observations = FingerObservations()
    observations.sessions = 10
    for finger in Finger.allCases where finger != .thumb {
        observations.fingers[finger] = observation(presses: presses, errors: errors,
                                                   timing: [.sameHand: (timing, 0.15, 0.02), .alternateHand: (timing, 0.12, 0.02)])
    }
    return observations
}

@Suite struct FingerClassificationTests {
    @Test func tooFewPressesIsNotEnoughDataAndHasNoNumbers() {
        var observations = everyone()
        observations.fingers[.leftPinky] = observation(presses: 59, errors: 0)
        let estimate = FingerEstimator.report(observations)[.leftPinky]
        #expect(estimate.status == .insufficientData)
        #expect(estimate.confidence == .none)
        #expect(estimate.accuracy == nil && estimate.relativeLatency == nil)
        #expect(FingerStatus.insufficientData.title == "Not enough data yet")
    }

    @Test func noPersonalBaselineMeansNoEstimate() {
        var observations = FingerObservations()
        observations.fingers[.leftPinky] = observation(presses: 100, errors: 1)
        let report = FingerEstimator.report(observations)
        #expect(report.baselineErrorRate == nil)
        #expect(report[.leftPinky].status == .insufficientData)
    }

    @Test func reliablyErrorProneFingerNeedsPractice() {
        var observations = everyone()
        observations.fingers[.rightPinky] = observation(presses: 400, errors: 48,
                                                        timing: [.sameHand: (120, 0.15, 0.02), .alternateHand: (120, 0.12, 0.02)])
        let report = FingerEstimator.report(observations)
        #expect(report[.rightPinky].status == .needsPractice)
        #expect(report[.leftIndex].status != .needsPractice)
    }

    @Test func reliablySlowFingerNeedsPracticeEvenWhenAccurate() {
        var observations = everyone()
        observations.fingers[.leftRing] = observation(presses: 400, errors: 4,
                                                      timing: [.sameHand: (120, 0.24, 0.02), .alternateHand: (120, 0.19, 0.02)])
        let estimate = FingerEstimator.report(observations)[.leftRing]
        #expect(estimate.status == .needsPractice)
        #expect((estimate.relativeLatency ?? 0) > 1.3)
    }

    @Test func comparesSpeedOnlyWithinTheSameKindOfTransition() {
        // The pinky only makes slow same-finger reaches, at exactly everyone's
        // same-finger pace: it is not slow, however slow those reaches are.
        var observations = everyone()
        for finger in [Finger.leftMiddle, .rightMiddle] {
            observations.fingers[finger]!.timing[.sameFinger] = observation(presses: 0, errors: 0, timing: [.sameFinger: (60, 0.40, 0.02)]).timing[.sameFinger]
        }
        observations.fingers[.leftPinky] = observation(presses: 400, errors: 4, timing: [.sameFinger: (60, 0.40, 0.02)])
        let estimate = FingerEstimator.report(observations)[.leftPinky]
        let ratio = try? #require(estimate.relativeLatency)
        #expect(abs((ratio ?? 0) - 1) < 0.01)
        #expect(estimate.status != .needsPractice)
    }

    @Test func accurateEvenFingerWithEnoughDataIsStrong() {
        var observations = everyone()
        observations.fingers[.leftIndex] = observation(presses: 400, errors: 2,
                                                       timing: [.sameHand: (120, 0.145, 0.02), .alternateHand: (120, 0.115, 0.02)])
        let estimate = FingerEstimator.report(observations)[.leftIndex]
        #expect(estimate.status == .strong)
        #expect(estimate.confidence >= .medium)
    }

    @Test func probablyFineButUnprovenIsDeveloping() {
        var observations = everyone()
        // Accurate, but only 20 timing samples: speed cannot be judged.
        observations.fingers[.rightRing] = observation(presses: 300, errors: 2, timing: [.sameHand: (20, 0.15, 0.02)])
        let estimate = FingerEstimator.report(observations)[.rightRing]
        #expect(estimate.status == .developing)
        #expect(estimate.relativeLatency == nil)
        #expect(estimate.confidence == .low)
    }

    @Test func erraticTimingIsNotStrong() {
        var observations = everyone()
        observations.fingers[.leftIndex] = observation(presses: 400, errors: 2,
                                                       timing: [.sameHand: (200, 0.15, 0.13), .alternateHand: (200, 0.12, 0.10)])
        let estimate = FingerEstimator.report(observations)[.leftIndex]
        #expect((estimate.timingVariation ?? 0) > FingerEstimator.Thresholds().strongMaxVariation)
        #expect(estimate.status == .developing)
    }

    @Test func confidenceFollowsTheThresholds() {
        let base = everyone()
        func confidence(_ presses: Int, timing: Int) -> DataConfidence {
            var observations = base
            observations.fingers[.leftPinky] = observation(presses: presses, errors: 1,
                                                           timing: [.sameHand: (timing, 0.15, 0.02)])
            return FingerEstimator.report(observations)[.leftPinky].confidence
        }
        #expect(confidence(59, timing: 40) == .none)
        #expect(confidence(100, timing: 40) == .low)
        #expect(confidence(300, timing: 10) == .low)
        #expect(confidence(300, timing: 40) == .medium)
        #expect(confidence(700, timing: 250) == .high)
    }

    @Test func thresholdsAreConfigurable() {
        var observations = everyone()
        observations.fingers[.leftPinky] = observation(presses: 80, errors: 1)
        var strict = FingerEstimator.Thresholds()
        strict.minimumPresses = 100
        #expect(FingerEstimator.report(observations)[.leftPinky].status != .insufficientData)
        #expect(FingerEstimator.report(observations, thresholds: strict)[.leftPinky].status == .insufficientData)
    }

    @Test func problemKeyAndSlowTransitionNeedEvidence() {
        var observations = everyone()
        var pinky = observation(presses: 200, errors: 10, keys: ["q": ErrorCount(attempts: 40, errors: 8),
                                                                  "a": ErrorCount(attempts: 140, errors: 2),
                                                                  "z": ErrorCount(attempts: 5, errors: 3)])
        var slow = TransitionTiming(kind: .sameHand)
        for _ in 0..<6 { slow.latency.add(0.25) }
        var once = TransitionTiming(kind: .sameHand)
        once.latency.add(0.9)
        pinky.transitions = ["sa": slow, "da": once]
        observations.fingers[.leftPinky] = pinky
        let estimate = FingerEstimator.report(observations)[.leftPinky]
        #expect(estimate.problemKey?.key == "q", "z has too few presses to count")
        #expect(estimate.slowTransition?.transition == "sa", "da was seen once")
    }
}

@Suite struct FingerRecommendationTests {
    private func weakness(_ category: Weakness.Category, _ item: String, _ dimension: Weakness.Dimension = .accuracy) -> Weakness {
        Weakness(category: category, dimension: dimension, item: item, samples: 60, errors: 9, value: 0.15, baseline: 0.04)
    }

    @Test func weaknessesMapToTheFingerOfTheirLastKey() {
        #expect(FingerRecommender.finger(for: weakness(.key, "q")) == .leftPinky)
        #expect(FingerRecommender.finger(for: weakness(.combination, "lo")) == .rightRing)
        #expect(FingerRecommender.finger(for: weakness(.transition, "e "))  == .thumb)
        #expect(FingerRecommender.finger(for: weakness(.word, "their")) == nil)
    }

    @Test func recommendsFingersWithConfirmedWeaknesses() {
        let report = FingerEstimator.report(everyone())
        let weaknesses = WeaknessReport(accuracy: [weakness(.key, "q"), weakness(.combination, "aq"), weakness(.word, "quiz")],
                                        speed: [weakness(.combination, "lo", .speed)],
                                        sessions: 10, keystrokes: 5_000, keystrokesNeeded: 600)
        let recommendations = FingerRecommender.recommendations(report: report, weaknesses: weaknesses)
        #expect(recommendations.map(\.finger) == [.leftPinky, .rightRing])
        #expect(recommendations[0].weaknesses.count == 2)
        #expect(recommendations[0].target == .leftPinky)
    }

    @Test func nothingWithoutEnoughData() {
        var observations = everyone(presses: 30, errors: 10)
        observations.sessions = 1
        let weaknesses = WeaknessReport(accuracy: [], speed: [], sessions: 1, keystrokes: 200, keystrokesNeeded: 600)
        #expect(FingerRecommender.recommendations(report: FingerEstimator.report(observations), weaknesses: weaknesses).isEmpty)
    }

    @Test func aNeedsPracticeFingerIsRecommendedEvenWithoutAConfirmedWeakness() {
        var observations = everyone()
        observations.fingers[.rightPinky] = observation(presses: 400, errors: 48)
        let weaknesses = WeaknessReport(accuracy: [], speed: [], sessions: 10, keystrokes: 5_000, keystrokesNeeded: 600)
        let recommendations = FingerRecommender.recommendations(report: FingerEstimator.report(observations), weaknesses: weaknesses)
        #expect(recommendations.map(\.finger) == [.rightPinky])
        #expect(recommendations[0].status == .needsPractice)
    }
}

@Suite struct FingerRetestTests {
    @Test func errorRateChangesNeedEvidence() {
        let before = ErrorCount(attempts: 200, errors: 30)
        #expect(ChangeTest.errorRates(before: before, after: ErrorCount(attempts: 200, errors: 8), minimumAttempts: 40) == .improved)
        #expect(ChangeTest.errorRates(before: ErrorCount(attempts: 200, errors: 8), after: before, minimumAttempts: 40) == .declined)
        #expect(ChangeTest.errorRates(before: before, after: ErrorCount(attempts: 200, errors: 25), minimumAttempts: 40) == .noClearChange)
        #expect(ChangeTest.errorRates(before: before, after: ErrorCount(attempts: 20, errors: 0), minimumAttempts: 40) == .insufficientData)
    }

    @Test func latencyChangesNeedEvidenceAndSize() {
        func sums(_ mean: Double, _ count: Int, spread: Double = 0.1) -> LatencySums {
            var sums = LatencySums()
            for index in 0..<count { sums.add(mean + (index.isMultiple(of: 2) ? spread : -spread)) }
            return sums
        }
        #expect(ChangeTest.means(before: sums(1.3, 60), after: sums(1.0, 60), minimumSamples: 20, minimumDifference: 0.05) == .improved)
        #expect(ChangeTest.means(before: sums(1.0, 60), after: sums(1.3, 60), minimumSamples: 20, minimumDifference: 0.05) == .declined)
        // Tiny but "significant" difference is still not a change.
        #expect(ChangeTest.means(before: sums(1.03, 500, spread: 0.01), after: sums(1.0, 500, spread: 0.01),
                                 minimumSamples: 20, minimumDifference: 0.05) == .noClearChange)
        #expect(ChangeTest.means(before: sums(1.3, 10), after: sums(1.0, 60), minimumSamples: 20, minimumDifference: 0.05) == .insufficientData)
    }

    @Test func checksAreComparableButNotIdentical() {
        for target in FingerFocusTarget.allCases {
            let a = FingerAssessment.text(for: target, seed: 1)
            let b = FingerAssessment.text(for: target, seed: 2)
            #expect(a != b)
            // Letters only: "." and ";" may be appended to any word.
            let targets = Set(target.keys.filter(\.isLetter))
            let rich = { (text: String) in text.split(separator: " ").filter { $0.contains(where: targets.contains) }.count }
            let common = { (text: String) in text.split(separator: " ").count - rich(text) }
            #expect(common(a) == FingerAssessment.commonWords && common(b) == FingerAssessment.commonWords)
            #expect(FingerAssessment.text(for: target, seed: 1) == a)
            // Every check must be long enough to be compared at all.
            for seed in UInt64(1)...20 {
                let text = FingerAssessment.text(for: target, seed: seed)
                let presses = text.filter { target.keys.contains($0) }.count
                #expect(presses >= FingerAssessment.minimumPresses, "\(target) seed \(seed): \(presses) target presses")
            }
        }
    }

    @Test func checkResultScoresOnlyTargetKeysAgainstTheOthers() {
        // Pinky keys are typed slowly and with one fixed mistake; the rest evenly.
        let session = typed("aqua sales zap quiz", gapFor: { _, next in "aqz".contains(next) ? 0.3 : 0.15 },
                            mistakes: [1: "w"])
        let result = FingerAssessment.result(for: session, target: .leftPinky)
        #expect(result.target.attempts == 9)
        #expect(result.target.errors == 1)
        #expect(result.correctedErrors == 1 && result.uncorrectedErrors == 0)
        #expect(result.other.attempts > 0 && result.other.errors == 0)
        #expect((result.relativeLatency.mean ?? 0) > 1.5)
    }

    @Test func latestComparisonUsesThePreviousCheckAndCountsTrainingBetween() {
        func check(_ minute: Int, errors: Int) -> FingerAssessmentEvent {
            FingerAssessmentEvent(date: Date(timeIntervalSince1970: Double(minute) * 60), target: .leftPinky,
                                  result: FingerAssessmentResult(text: "", duration: 30, target: ErrorCount(attempts: 120, errors: errors),
                                                                 correctedErrors: errors, uncorrectedErrors: 0,
                                                                 other: ErrorCount(attempts: 100, errors: 2), relativeLatency: LatencySums()))
        }
        func round(_ minute: Int, _ target: FingerFocusTarget = .leftPinky) -> FingerFocusEvent {
            FingerFocusEvent(date: Date(timeIntervalSince1970: Double(minute) * 60), target: target, level: .activation,
                             result: RoundResult(text: "aaa", accuracy: 1, keystrokes: 10, correctKeystrokes: 10, backspaces: 0, duration: 5))
        }
        let checks = [check(0, errors: 30), check(10, errors: 24), check(20, errors: 4)]
        let training = [round(5), round(12), round(13), round(14, .rightRing), round(25)]
        #expect(FingerAssessment.latestComparison(for: .leftPinky, assessments: Array(checks.prefix(1)), training: training) == nil)

        let comparison = try? #require(FingerAssessment.latestComparison(for: .leftPinky, assessments: checks, training: training))
        #expect(comparison?.baseline.id == checks[1].id)
        #expect(comparison?.retest.id == checks[2].id)
        #expect(comparison?.trainingRounds == 2)
        #expect(comparison?.accuracy == .improved)
        #expect(comparison?.latency == .insufficientData)
        #expect(comparison?.isImprovement == true)
    }
}

@Suite struct FingerTrendTests {
    @Test func improvementNeedsEnoughSessionsAndEvidence() {
        func session(_ errors: Int) -> (date: Date, observations: FingerObservations) {
            var observations = FingerObservations()
            observations.sessions = 1
            observations.fingers[.leftPinky] = observation(presses: 40, errors: errors)
            return (Date(), observations)
        }
        let few = FingerTrends.trend(for: .leftPinky, sessions: [session(10), session(1)], baselines: [:])
        #expect(few.accuracy == .insufficientData)

        let better = (0..<5).map { _ in session(8) } + (0..<5).map { _ in session(1) }
        #expect(FingerTrends.trend(for: .leftPinky, sessions: better, baselines: [:]).accuracy == .improved)

        let same = (0..<10).map { _ in session(3) }
        let trend = FingerTrends.trend(for: .leftPinky, sessions: same, baselines: [:])
        #expect(trend.accuracy == .noClearChange)
        #expect(trend.points.count == 10)
        #expect(trend.points.allSatisfy { $0.accuracy != nil && $0.relativeLatency == nil })
    }
}

@MainActor
@Suite struct FingerCheckStoreTests {
    @Test func checksRoundTripAlongsideEverythingElse() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "keyflow-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "MuscleMemory.store")
        let result = FingerAssessmentResult(text: "aqua", duration: 20, target: ErrorCount(attempts: 50, errors: 2),
                                            correctedErrors: 2, uncorrectedErrors: 0, other: ErrorCount(attempts: 80, errors: 1),
                                            relativeLatency: LatencySums(count: 3, sum: 3.3, squares: 3.7))
        let check = FingerAssessmentEvent(date: Date(timeIntervalSince1970: 100), target: .leftPinky, result: result)
        let lesson = TrainingEvent(date: Date(timeIntervalSince1970: 50), category: .homeRow, stage: .singleKeys, kind: .skip)
        do {
            let store = try TrainingStore.onDisk(at: url)
            try store.record(lesson)
            try store.record(check)
        }
        let reopened = try TrainingStore.onDisk(at: url)
        #expect(reopened.assessmentEvents == [check])
        #expect(reopened.events == [lesson])
        #expect(reopened.fingerFocusEvents.isEmpty)
    }

    @Test func statisticsStoreProvidesFingerObservationsFromSavedLogs() throws {
        let store = try StatisticsStore.inMemory()
        let session = typed("as df jk", mistakes: [0: "x"])
        try store.record(session, kind: .test, timeLimit: 30)
        let saved = store.fingerObservations()
        #expect(saved.count == 1)
        #expect(saved[0].observations == FingerAnalyzer.observe(session))
        #expect(saved[0].observations[.leftPinky].correctedErrors == 1)
    }
}
