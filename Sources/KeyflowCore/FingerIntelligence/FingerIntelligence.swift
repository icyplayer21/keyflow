import Foundation

/// Everything the Finger Performance section shows, in one value: current
/// estimates, per-finger history, training done and retest comparisons.
public struct FingerIntelligenceReport: Sendable {
    public let report: FingerReport
    /// Personal latency baselines per transition kind, from the window.
    public let baselines: [TransitionKind: TimeInterval]
    /// Every session's observations, oldest first.
    public let history: [(date: Date, observations: FingerObservations)]
    public let training: [FingerFocusEvent]
    public let assessments: [FingerAssessmentEvent]

    public func estimate(_ finger: Finger) -> FingerEstimate { report[finger] }

    public func trend(_ finger: Finger) -> FingerTrend {
        FingerTrends.trend(for: finger, sessions: history, baselines: baselines)
    }

    /// Finger Focus rounds that trained this finger, alone or with its pair.
    public func trainingRounds(_ finger: Finger) -> Int {
        training.filter { $0.target.fingers.contains(finger) }.count
    }

    /// Finger checks for this finger's own target, oldest first.
    public func checks(_ finger: Finger) -> [FingerAssessmentEvent] {
        guard let target = FingerFocusTarget.single(finger) else { return [] }
        return assessments.filter { $0.target == target }
    }

    public func comparison(_ finger: Finger) -> FingerAssessmentComparison? {
        guard let target = FingerFocusTarget.single(finger) else { return nil }
        return FingerAssessment.latestComparison(for: target, assessments: assessments, training: training)
    }

    /// Finger Focus levels that are steady for this finger's own target.
    public func steadyLevels(_ finger: Finger) -> Int {
        guard let target = FingerFocusTarget.single(finger) else { return 0 }
        let tracker = FingerFocusTracker(events: training)
        return FingerFocusLevel.allCases.filter { tracker.progress(target, $0).isSteady }.count
    }
}

public enum FingerIntelligence {
    /// Estimates use the same window of recent sessions as Weakness Analysis.
    public static let window = ProgressAnalyzer.window

    /// - Parameter sessions: Practice and Test sessions, oldest first. Finger
    ///   Focus drills are not included: their text is built around one finger
    ///   and would skew the comparison with other fingers.
    public static func build(sessions: [(date: Date, observations: FingerObservations)],
                             training: [FingerFocusEvent] = [], assessments: [FingerAssessmentEvent] = [],
                             thresholds: FingerEstimator.Thresholds = .init()) -> FingerIntelligenceReport {
        let recent = sessions.suffix(window).reduce(into: FingerObservations()) { $0.merge($1.observations) }
        return FingerIntelligenceReport(
            report: FingerEstimator.report(recent, thresholds: thresholds),
            baselines: FingerEstimator.latencyBaselines(recent, thresholds: thresholds),
            history: sessions,
            training: training,
            assessments: assessments
        )
    }
}
