import Foundation

/// The four states shown on the finger heatmap.
public enum FingerStatus: String, Sendable, CaseIterable {
    case strong, developing, needsPractice, insufficientData

    public var title: String {
        switch self {
        case .strong: "Strong"
        case .developing: "Developing"
        case .needsPractice: "Needs Practice"
        case .insufficientData: "Not enough data yet"
        }
    }
}

/// How much the estimate can be trusted, from how much was observed.
public enum DataConfidence: Int, Sendable, Comparable, CaseIterable {
    case none, low, medium, high

    public var title: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The estimated performance of one finger. Every number is an estimate
/// from the keys standard touch typing assigns to the finger; Keyflow cannot
/// see which finger actually pressed them.
public struct FingerEstimate: Sendable, Equatable {
    public struct KeyIssue: Sendable, Equatable {
        public let key: Character
        public let count: ErrorCount
    }

    public struct SlowTransition: Sendable, Equatable {
        /// "ed": e, then the finger's key d.
        public let transition: String
        public let kind: TransitionKind
        /// Mean latency ÷ your mean for the same kind of transition.
        public let ratio: Double
        public let samples: Int
    }

    public let finger: Finger
    public let observation: FingerObservation
    public let status: FingerStatus
    public let confidence: DataConfidence
    /// Successful ÷ presses; `nil` without enough presses.
    public let accuracy: Double?
    /// 95% Wilson interval for accuracy.
    public let accuracyRange: ClosedRange<Double>?
    /// Latency ÷ your own mean for comparable transitions (1 = your
    /// average, 1.2 = 20% slower); `nil` without enough timing samples.
    public let relativeLatency: Double?
    /// 95% interval for `relativeLatency`.
    public let latencyRange: ClosedRange<Double>?
    /// Coefficient of variation of the relative latency samples.
    public let timingVariation: Double?
    public let problemKey: KeyIssue?
    public let slowTransition: SlowTransition?
    /// Plain-language reasons for the status, for the detail panel.
    public let reasons: [String]
}

/// All fingers' estimates, plus the personal baselines they were judged against.
public struct FingerReport: Sendable, Equatable {
    public let estimates: [Finger: FingerEstimate]
    /// Your error rate over all non-thumb fingers; `nil` until there is enough typing.
    public let baselineErrorRate: Double?
    public let sessions: Int

    public subscript(finger: Finger) -> FingerEstimate { estimates[finger]! }
}

/// A transparent, rule-based classification of each finger. It is a
/// practice aid, not a validated or medical measure of finger dexterity.
///
/// **Baselines are personal.** Error rate is compared with your own error
/// rate across all fingers. Speed is compared only within the same kind of
/// transition (`TransitionKind`): each latency sample is divided by your mean
/// for its kind, and a finger's relative latency is the sum of its latencies
/// over the sum of the matching baselines. A kind with fewer than
/// `baselineSamplesPerKind` samples has no baseline and is left out.
///
/// **Classification**, using 95% intervals (`z`):
/// 1. *Not enough data yet* — fewer than `minimumPresses` presses, or no
///    personal error baseline yet.
/// 2. *Needs Practice* — any of:
///    - the lower bound of the error rate is above `needsPracticeErrorRatio` ×
///      your baseline (reliably worse than your own average);
///    - the lower bound of the error rate is above `absoluteErrorRate`;
///    - with enough timing samples, the lower bound of relative latency is
///      above `slowRatio` (reliably slower on comparable transitions).
/// 3. *Strong* — all of: confidence at least medium; error rate at or below
///    your baseline and its upper bound below `strongErrorCeilingRatio` ×
///    baseline; enough timing samples, with the upper bound of relative
///    latency below `strongLatencyCeiling` and timing variation below
///    `strongMaxVariation`.
/// 4. *Developing* — everything else, including fingers that are probably
///    fine but not yet proven.
///
/// **Confidence** — none below `minimumPresses`; low below
/// `mediumConfidencePresses` presses or `minimumTimingSamples` timing
/// samples; high from `highConfidencePresses` presses and
/// `highConfidenceTimingSamples` timing samples; otherwise medium.
public enum FingerEstimator {
    public struct Thresholds: Sendable, Equatable {
        public var minimumPresses = 60
        public var minimumTimingSamples = 30
        public var baselineSamplesPerKind = 20
        public var mediumConfidencePresses = 200
        public var highConfidencePresses = 600
        public var highConfidenceTimingSamples = 200

        public var needsPracticeErrorRatio = 1.25
        public var absoluteErrorRate = 0.10
        public var slowRatio = 1.20

        public var strongErrorCeilingRatio = 1.5
        public var strongLatencyCeiling = 1.10
        public var strongMaxVariation = 0.6

        /// Problem key: at least this many presses and errors.
        public var problemKeyPresses = 15
        public var problemKeyErrors = 2
        /// Slow transition: at least this many samples and this ratio.
        public var transitionSamples = 5
        public var slowTransitionRatio = 1.15

        public var z = 1.96

        public init() {}
    }

    public static func report(_ observations: FingerObservations, thresholds: Thresholds = Thresholds()) -> FingerReport {
        let baselines = latencyBaselines(observations, thresholds: thresholds)
        let typed = observations.fingers.filter { $0.key != .thumb }.values
        let presses = typed.reduce(0) { $0 + $1.presses }
        let baselineError = presses >= thresholds.minimumPresses * 3
            ? Double(typed.reduce(0) { $0 + $1.incorrect }) / Double(presses)
            : nil

        var estimates: [Finger: FingerEstimate] = [:]
        for finger in Finger.allCases {
            estimates[finger] = estimate(finger, observations[finger], errorBaseline: baselineError,
                                         latencyBaselines: baselines, thresholds: thresholds)
        }
        return FingerReport(estimates: estimates, baselineErrorRate: baselineError, sessions: observations.sessions)
    }

    /// Your mean latency per transition kind, for kinds with enough samples.
    public static func latencyBaselines(_ observations: FingerObservations,
                                        thresholds: Thresholds = Thresholds()) -> [TransitionKind: TimeInterval] {
        observations.timingByKind.compactMapValues { sums in
            sums.count >= thresholds.baselineSamplesPerKind ? sums.mean : nil
        }
    }

    /// Relative latency sums: Σ latency/baseline and its square, over kinds
    /// that have a baseline.
    public static func relativeSums(_ timing: [TransitionKind: LatencySums],
                                    baselines: [TransitionKind: TimeInterval]) -> (ratio: Double, sums: LatencySums)? {
        var latency: TimeInterval = 0
        var expected: TimeInterval = 0
        var ratios = LatencySums()
        for (kind, sums) in timing {
            guard let baseline = baselines[kind], baseline > 0, sums.count > 0 else { continue }
            latency += sums.sum
            expected += Double(sums.count) * baseline
            ratios = ratios + LatencySums(count: sums.count, sum: sums.sum / baseline, squares: sums.squares / (baseline * baseline))
        }
        guard expected > 0 else { return nil }
        return (latency / expected, ratios)
    }

    static func estimate(_ finger: Finger, _ observation: FingerObservation, errorBaseline: Double?,
                         latencyBaselines: [TransitionKind: TimeInterval], thresholds t: Thresholds) -> FingerEstimate {
        let enough = observation.presses >= t.minimumPresses
        let relative = relativeSums(observation.timing, baselines: latencyBaselines)
        let timingSamples = relative?.sums.count ?? 0
        let timingUsable = enough && timingSamples >= t.minimumTimingSamples

        let confidence: DataConfidence = if !enough {
            .none
        } else if observation.presses < t.mediumConfidencePresses || timingSamples < t.minimumTimingSamples {
            .low
        } else if observation.presses >= t.highConfidencePresses && timingSamples >= t.highConfidenceTimingSamples {
            .high
        } else {
            .medium
        }

        var accuracy: Double?
        var accuracyRange: ClosedRange<Double>?
        var errorInterval: ClosedRange<Double>?
        if enough {
            accuracy = Double(observation.successful) / Double(observation.presses)
            let interval = wilson(errors: observation.incorrect, attempts: observation.presses, z: t.z)
            errorInterval = interval
            accuracyRange = (1 - interval.upperBound)...(1 - interval.lowerBound)
        }

        var relativeLatency: Double?
        var latencyRange: ClosedRange<Double>?
        var variation: Double?
        if timingUsable, let relative {
            relativeLatency = relative.ratio
            let mean = relative.sums.mean ?? relative.ratio
            let deviation = (relative.sums.variance ?? 0).squareRoot()
            let margin = t.z * deviation / Double(relative.sums.count).squareRoot()
            latencyRange = max(0, relative.ratio - margin)...(relative.ratio + margin)
            variation = mean > 0 ? deviation / mean : nil
        }

        // Status
        var reasons: [String] = []
        var status: FingerStatus
        if !enough || errorBaseline == nil {
            status = .insufficientData
            if !enough {
                reasons.append("\(observation.presses) of the \(t.minimumPresses) presses needed for an estimate.")
            } else {
                reasons.append("Not enough typing overall yet to know your own average.")
            }
        } else {
            let baseline = errorBaseline!
            let errors = errorInterval!
            let rate = Double(observation.incorrect) / Double(observation.presses)
            var weak = false
            if errors.lowerBound > baseline * t.needsPracticeErrorRatio {
                weak = true
                reasons.append("Error rate \(percent(rate)) is reliably above your average of \(percent(baseline)).")
            } else if errors.lowerBound > t.absoluteErrorRate {
                weak = true
                reasons.append("Error rate \(percent(rate)) is high even allowing for chance.")
            }
            if let latencyRange, latencyRange.lowerBound > t.slowRatio {
                weak = true
                reasons.append("Reliably slower than your average for comparable key changes.")
            }

            if weak {
                status = .needsPractice
            } else {
                var strong = confidence >= .medium
                if rate > baseline || errors.upperBound > baseline * t.strongErrorCeilingRatio {
                    strong = false
                    reasons.append("Error rate \(percent(rate)) compared with your average of \(percent(baseline)).")
                } else {
                    reasons.append("Error rate at or below your average of \(percent(baseline)).")
                }
                if let latencyRange, let variation {
                    if latencyRange.upperBound > t.strongLatencyCeiling {
                        strong = false
                        reasons.append("Speed not yet clearly at your average for comparable key changes.")
                    } else if variation > t.strongMaxVariation {
                        strong = false
                        reasons.append("Timing varies a lot from press to press.")
                    } else {
                        reasons.append("Speed at or near your average for comparable key changes.")
                    }
                } else {
                    strong = false
                    reasons.append("Not enough timing samples to judge speed (\(timingSamples) of \(t.minimumTimingSamples)).")
                }
                if confidence < .medium, !reasons.isEmpty {
                    reasons.append("More typing will firm this up.")
                }
                status = strong ? .strong : .developing
            }
        }

        // Most problematic key and slowest transition.
        let problemKey = observation.keys
            .filter { $0.value.attempts >= t.problemKeyPresses && $0.value.errors >= t.problemKeyErrors }
            .max { ($0.value.rate, $0.value.errors, String($1.key)) < ($1.value.rate, $1.value.errors, String($0.key)) }
            .map { FingerEstimate.KeyIssue(key: $0.key, count: $0.value) }

        let slowTransition = observation.transitions.compactMap { name, timing -> FingerEstimate.SlowTransition? in
            guard timing.latency.count >= t.transitionSamples, let baseline = latencyBaselines[timing.kind],
                  baseline > 0, let mean = timing.latency.mean else { return nil }
            let ratio = mean / baseline
            guard ratio >= t.slowTransitionRatio else { return nil }
            return FingerEstimate.SlowTransition(transition: name, kind: timing.kind, ratio: ratio, samples: timing.latency.count)
        }
        .max { ($0.ratio, $1.transition) < ($1.ratio, $0.transition) }

        return FingerEstimate(finger: finger, observation: observation, status: status, confidence: confidence,
                              accuracy: accuracy, accuracyRange: accuracyRange, relativeLatency: relativeLatency,
                              latencyRange: latencyRange, timingVariation: variation, problemKey: problemKey,
                              slowTransition: slowTransition, reasons: reasons)
    }

    /// 95% (for z = 1.96) Wilson score interval of an error rate.
    public static func wilson(errors: Int, attempts: Int, z: Double) -> ClosedRange<Double> {
        guard attempts > 0 else { return 0...1 }
        let lower = WeaknessAnalyzer.wilsonLowerBound(errors: errors, attempts: attempts, z: z)
        let upper = 1 - WeaknessAnalyzer.wilsonLowerBound(errors: attempts - errors, attempts: attempts, z: z)
        return lower...max(lower, upper)
    }

    private static func percent(_ value: Double) -> String {
        let scaled = value * 100
        return scaled < 10 ? String(format: "%.1f%%", scaled) : "\(Int(scaled.rounded()))%"
    }
}
