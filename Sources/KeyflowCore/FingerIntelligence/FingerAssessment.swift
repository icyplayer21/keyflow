import Foundation

/// The measured outcome of one finger check (baseline or retest).
public struct FingerAssessmentResult: Codable, Sendable, Equatable {
    public var text: String
    public var duration: TimeInterval
    /// Presses of the target fingers' keys.
    public var target: ErrorCount
    public var correctedErrors: Int
    public var uncorrectedErrors: Int
    /// Presses of every other non-thumb key: the within-check reference.
    public var other: ErrorCount
    /// Target-key latency ÷ the other keys' latency for the same kind of
    /// transition in this same check, one sample per timed press.
    public var relativeLatency: LatencySums

    public init(text: String, duration: TimeInterval, target: ErrorCount, correctedErrors: Int, uncorrectedErrors: Int,
                other: ErrorCount, relativeLatency: LatencySums) {
        self.text = text
        self.duration = duration
        self.target = target
        self.correctedErrors = correctedErrors
        self.uncorrectedErrors = uncorrectedErrors
        self.other = other
        self.relativeLatency = relativeLatency
    }

    public var accuracy: Double? { target.attempts > 0 ? 1 - target.rate : nil }
}

public struct FingerAssessmentEvent: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let target: FingerFocusTarget
    public let result: FingerAssessmentResult

    public init(id: UUID = UUID(), date: Date = .now, target: FingerFocusTarget, result: FingerAssessmentResult) {
        self.id = id
        self.date = date
        self.target = target
        self.result = result
    }
}

/// A retest compared with the check before it.
public struct FingerAssessmentComparison: Sendable, Equatable {
    public let baseline: FingerAssessmentEvent
    public let retest: FingerAssessmentEvent
    /// Finger Focus rounds for this target between the two checks.
    public let trainingRounds: Int
    public let accuracy: ChangeVerdict
    public let latency: ChangeVerdict

    /// Improved on at least one measure and declined on none.
    public var isImprovement: Bool {
        (accuracy == .improved || latency == .improved) && accuracy != .declined && latency != .declined
    }
}

/// Finger checks: short, comparable but never identical passages, scored on
/// the target fingers' keys only.
///
/// Every check has the same make-up: real words dense in the target letters,
/// added until they hold `targetPresses` target keystrokes, plus
/// `commonWords` everyday words without target letters, shuffled together,
/// with the same punctuation rule as Finger Focus words. A new seed gives new
/// words in the same proportions, so two checks are comparable without
/// being memorised.
///
/// Speed is measured inside each check against the user's own other keys in
/// that check, per transition kind, so a slow day overall does not look like
/// a slower finger.
public enum FingerAssessment {
    /// Target keystrokes in every check: comfortably above `minimumPresses`,
    /// so any two checks can be compared.
    public static let targetPresses = 50
    public static let commonWords = 10
    public static let minimumPresses = 40
    public static let minimumTimingSamples = 20
    public static let minimumLatencyDifference = 0.05
    /// Kinds with fewer reference samples than this fall back to all reference samples.
    public static let referenceSamplesPerKind = 5

    public static func text(for target: FingerFocusTarget, seed: UInt64) -> String {
        var rng = SeededGenerator(seed: seed)
        let rich = FingerFocusGenerator.wordPool(for: target)
        let targets = Set(target.keys.filter(\.isLetter))
        let common = WordList.common.filter { word in
            (3...7).contains(word.count) && word.allSatisfy { ("a"..."z").contains($0) } && !word.contains(where: targets.contains)
        }

        let marks = target.fingers.compactMap { finger -> Character? in
            switch finger {
            case .rightRing: "."
            case .rightPinky: ";"
            default: nil
            }
        }
        // Punctuation marks are added after every `punctuationEvery`-th word and count too.
        let targetKeys = Set(target.keys)
        var words: [String] = []
        var presses = 0
        while presses < targetPresses, let word = rich.randomElement(using: &rng) {
            words.append(word)
            presses += word.filter(targetKeys.contains).count
            if !marks.isEmpty, (words.count + commonWords / 2).isMultiple(of: FingerFocusGenerator.punctuationEvery) { presses += 1 }
        }
        for _ in 0..<commonWords { if let word = common.randomElement(using: &rng) { words.append(word) } }
        words.shuffle(using: &rng)
        for index in words.indices.dropFirst() where words[index] == words[index - 1] {
            words.swapAt(index, (index + 2) % words.count)
        }

        if !marks.isEmpty {
            for (count, index) in words.indices.filter({ ($0 + 1).isMultiple(of: FingerFocusGenerator.punctuationEvery) }).enumerated() {
                words[index].append(marks[count % marks.count])
            }
        }
        return words.joined(separator: " ")
    }

    public static func result(for session: TypingSession, target: FingerFocusTarget) -> FingerAssessmentResult {
        let observations = FingerAnalyzer.observe(session)
        let targetFingers = Set(target.fingers)

        var targetObservation = FingerObservation()
        var reference = FingerObservation()
        for (finger, observation) in observations.fingers where finger != .thumb {
            if targetFingers.contains(finger) { targetObservation.merge(observation) } else { reference.merge(observation) }
        }

        // Reference latency per kind from the other keys; thin kinds use the overall reference mean.
        let overall = reference.timing.values.reduce(LatencySums(), +).mean
        var baselines: [TransitionKind: TimeInterval] = [:]
        for kind in TransitionKind.allCases {
            if let sums = reference.timing[kind], sums.count >= referenceSamplesPerKind, let mean = sums.mean {
                baselines[kind] = mean
            } else if let overall {
                baselines[kind] = overall
            }
        }
        let relative = FingerEstimator.relativeSums(targetObservation.timing, baselines: baselines)?.sums ?? LatencySums()

        return FingerAssessmentResult(
            text: String(session.target),
            duration: session.elapsed,
            target: ErrorCount(attempts: targetObservation.presses, errors: targetObservation.incorrect),
            correctedErrors: targetObservation.correctedErrors,
            uncorrectedErrors: targetObservation.uncorrectedErrors,
            other: ErrorCount(attempts: reference.presses, errors: reference.incorrect),
            relativeLatency: relative
        )
    }

    public static func compare(baseline: FingerAssessmentResult, retest: FingerAssessmentResult) -> (accuracy: ChangeVerdict, latency: ChangeVerdict) {
        (ChangeTest.errorRates(before: baseline.target, after: retest.target, minimumAttempts: minimumPresses),
         ChangeTest.means(before: baseline.relativeLatency, after: retest.relativeLatency,
                          minimumSamples: minimumTimingSamples, minimumDifference: minimumLatencyDifference))
    }

    /// The latest check for a target compared with the one before it, or
    /// `nil` with fewer than two checks.
    public static func latestComparison(for target: FingerFocusTarget, assessments: [FingerAssessmentEvent],
                                        training: [FingerFocusEvent]) -> FingerAssessmentComparison? {
        let checks = assessments.filter { $0.target == target }.sorted { $0.date < $1.date }
        guard checks.count >= 2 else { return nil }
        let baseline = checks[checks.count - 2], retest = checks[checks.count - 1]
        let rounds = training.filter { $0.target == target && $0.date > baseline.date && $0.date < retest.date }.count
        let verdicts = compare(baseline: baseline.result, retest: retest.result)
        return FingerAssessmentComparison(baseline: baseline, retest: retest, trainingRounds: rounds,
                                          accuracy: verdicts.accuracy, latency: verdicts.latency)
    }
}
