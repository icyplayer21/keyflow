import Foundation

/// The estimated extra time capitalising costs, per method.
///
/// **What is measured.** Each run of capitals ("NASA", "B") is timed from
/// the key before it to the key after it, so Shift presses, or switching Caps
/// Lock on and off, fall inside the span. That is the *observed* time.
///
/// **Baseline.** The same number of ordinary key changes, of the same kinds,
/// in the same round: one change in, one per letter pair inside the run, one
/// change out, each priced at the round's median for a lower-case letter →
/// letter change or a letter ↔ space change. Runs next to punctuation, or in
/// rounds with fewer than `MechanicsFeedback.minimumSamples` ordinary
/// changes of a needed kind, have no baseline and are left out.
///
/// **Overhead** = observed − baseline, per run. Runs are pooled over the
/// most recent `recentRounds` rounds of Typing Mechanics; the estimate is
/// the median, with a 95% confidence range for that median from order
/// statistics. A negative estimate is reported as it is: it means the
/// capitals went no slower than ordinary typing, within the noise.
///
/// This is an estimate from timing patterns, not a physiological
/// measurement. Fewer than `minimumRuns` runs give no estimate.
public enum CapitalisationOverhead {
    public static let minimumRuns = 8
    public static let recentRounds = 40

    public enum Method: String, Sendable, CaseIterable {
        case shift, capsLock

        public var title: String { self == .shift ? "Shift" : "Caps Lock" }
    }

    /// One run of capitals that can be compared with its baseline.
    public struct Observation: Sendable, Equatable {
        public let method: Method
        public let length: Int
        public let observedMs: Double
        public let baselineMs: Double

        public var overheadMs: Double { observedMs - baselineMs }
        public var group: SegmentLength { SegmentLength(length) }
    }

    public struct Estimate: Sendable, Equatable {
        public let method: Method
        public let runs: Int
        /// Medians, in milliseconds; `nil` without enough runs.
        public let observedMs: Double?
        public let baselineMs: Double?
        public let overheadMs: Double?
        /// 95% confidence range of the median overhead.
        public let range: ClosedRange<Double>?

        public var isSufficient: Bool { overheadMs != nil }
    }

    /// Comparable runs from rounds, newest rounds last; only the last `recentRounds` count.
    public static func observations(from results: [MechanicsRoundResult]) -> [Observation] {
        results.suffix(recentRounds).flatMap { result in
            (result.segments ?? []).compactMap { segment -> Observation? in
                guard segment.clean, let observed = segment.spanMs, let baseline = segment.baselineMs else { return nil }
                let method: Method
                switch segment.method {
                case .shift: method = .shift
                case .capsLock: method = .capsLock
                case .mixed, .unknown: return nil
                }
                return Observation(method: method, length: segment.length, observedMs: observed, baselineMs: baseline)
            }
        }
    }

    /// The estimate for one method, optionally for one length group only.
    public static func estimate(_ observations: [Observation], method: Method, group: SegmentLength? = nil) -> Estimate {
        let runs = observations.filter { $0.method == method && (group == nil || $0.group == group) }
        guard runs.count >= minimumRuns else {
            return Estimate(method: method, runs: runs.count, observedMs: nil, baselineMs: nil, overheadMs: nil, range: nil)
        }
        let overheads = runs.map(\.overheadMs)
        return Estimate(method: method, runs: runs.count,
                        observedMs: median(runs.map(\.observedMs)),
                        baselineMs: median(runs.map(\.baselineMs)),
                        overheadMs: median(overheads),
                        range: medianRange(overheads))
    }

    public static func estimates(from results: [MechanicsRoundResult]) -> [Method: Estimate] {
        let observations = observations(from: results)
        return Dictionary(uniqueKeysWithValues: Method.allCases.map { ($0, estimate(observations, method: $0)) })
    }

    // MARK: Statistics

    static func median(_ values: [Double]) -> Double? { TimingSamples(values).median }

    /// Distribution-free 95% confidence interval for a median: the order
    /// statistics k and n − k + 1, with k = ⌊n/2 − 0.98√n⌋ (normal
    /// approximation to the binomial). `nil` when n is too small for it.
    public static func medianRange(_ values: [Double]) -> ClosedRange<Double>? {
        let sorted = values.sorted()
        let n = Double(sorted.count)
        let k = Int((n / 2 - 0.98 * n.squareRoot()).rounded(.down))
        guard k >= 1 else { return nil }
        return sorted[k - 1]...sorted[sorted.count - k]
    }
}
