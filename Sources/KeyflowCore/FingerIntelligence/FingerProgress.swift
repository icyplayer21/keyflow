import Foundation

/// Whether a change between two sets of observations is real.
public enum ChangeVerdict: String, Sendable, Equatable {
    /// Better, and unlikely to be chance.
    case improved
    /// Worse, and unlikely to be chance.
    case declined
    /// Enough data on both sides, but the difference could be chance.
    case noClearChange
    /// Too few observations on one side to say anything.
    case insufficientData

    public var title: String {
        switch self {
        case .improved: "Improved"
        case .declined: "Declined"
        case .noClearChange: "No clear change"
        case .insufficientData: "Not enough data yet"
        }
    }
}

/// Two-sided tests at the 95% level, used for trends and retests.
public enum ChangeTest {
    public static let z = 1.96

    /// Compares error rates. Lower is better.
    public static func errorRates(before: ErrorCount, after: ErrorCount, minimumAttempts: Int) -> ChangeVerdict {
        guard before.attempts >= minimumAttempts, after.attempts >= minimumAttempts else { return .insufficientData }
        let pooled = Double(before.errors + after.errors) / Double(before.attempts + after.attempts)
        let standardError = (pooled * (1 - pooled) * (1 / Double(before.attempts) + 1 / Double(after.attempts))).squareRoot()
        guard standardError > 0 else { return .noClearChange }
        let score = (after.rate - before.rate) / standardError
        if score <= -z { return .improved }
        if score >= z { return .declined }
        return .noClearChange
    }

    /// Compares means (Welch). Lower is better. A difference smaller than
    /// `minimumDifference` is never called a change, however many samples.
    public static func means(before: LatencySums, after: LatencySums, minimumSamples: Int,
                             minimumDifference: Double) -> ChangeVerdict {
        guard before.count >= minimumSamples, after.count >= minimumSamples,
              let a = before.mean, let b = after.mean,
              let va = before.variance, let vb = after.variance else { return .insufficientData }
        let standardError = (va / Double(before.count) + vb / Double(after.count)).squareRoot()
        let difference = b - a
        guard abs(difference) >= minimumDifference, standardError > 0 else { return .noClearChange }
        let score = difference / standardError
        if score <= -z { return .improved }
        if score >= z { return .declined }
        return .noClearChange
    }
}

/// One session's estimate for one finger, for trend charts. Values are
/// `nil` when that session had too few observations of the finger.
public struct FingerTrendPoint: Sendable, Equatable, Identifiable {
    public let index: Int
    public let date: Date
    public let presses: Int
    public let accuracy: Double?
    public let relativeLatency: Double?
    public var id: Int { index }
}

public struct FingerTrend: Sendable, Equatable {
    public let points: [FingerTrendPoint]
    /// Recent sessions against the ones before them.
    public let accuracy: ChangeVerdict
    public let latency: ChangeVerdict
}

/// Per-session history of each finger, derived from saved sessions.
///
/// A trend compares the most recent `recentSessions` sessions that used the
/// finger with up to `earlierSessions` sessions before them. Accuracy uses a
/// two-proportion test, relative latency a Welch test, both at 95%; anything
/// short of that is "No clear change", and too few observations on either
/// side is "Not enough data yet".
public enum FingerTrends {
    public static let recentSessions = 5
    public static let earlierSessions = 10
    public static let minimumPresses = 60
    public static let minimumTimingSamples = 30
    public static let minimumLatencyDifference = 0.05
    /// A chart point needs at least this many presses / timing samples.
    public static let pointPresses = 15
    public static let pointTimingSamples = 10

    public static func trend(for finger: Finger, sessions: [(date: Date, observations: FingerObservations)],
                             baselines: [TransitionKind: TimeInterval]) -> FingerTrend {
        let used = sessions.enumerated().compactMap { offset, session -> (Int, Date, FingerObservation)? in
            let observation = session.observations[finger]
            return observation.presses > 0 ? (offset + 1, session.date, observation) : nil
        }

        let points = used.map { index, date, observation in
            let relative = FingerEstimator.relativeSums(observation.timing, baselines: baselines)
            return FingerTrendPoint(
                index: index, date: date, presses: observation.presses,
                accuracy: observation.presses >= pointPresses ? Double(observation.successful) / Double(observation.presses) : nil,
                relativeLatency: (relative?.sums.count ?? 0) >= pointTimingSamples ? relative?.ratio : nil
            )
        }

        let recent = used.suffix(recentSessions).map(\.2)
        let earlier = used.dropLast(recentSessions).suffix(earlierSessions).map(\.2)
        func merged(_ list: [FingerObservation]) -> FingerObservation {
            list.reduce(into: FingerObservation()) { $0.merge($1) }
        }
        let before = merged(earlier), after = merged(recent)

        let accuracy = ChangeTest.errorRates(before: ErrorCount(attempts: before.presses, errors: before.incorrect),
                                             after: ErrorCount(attempts: after.presses, errors: after.incorrect),
                                             minimumAttempts: minimumPresses)
        let latency: ChangeVerdict
        if let a = FingerEstimator.relativeSums(before.timing, baselines: baselines),
           let b = FingerEstimator.relativeSums(after.timing, baselines: baselines) {
            latency = ChangeTest.means(before: a.sums, after: b.sums, minimumSamples: minimumTimingSamples,
                                       minimumDifference: minimumLatencyDifference)
        } else {
            latency = .insufficientData
        }
        return FingerTrend(points: points, accuracy: accuracy, latency: latency)
    }
}

// MARK: - Recommendations

/// A finger worth training, and the evidence for it.
public struct FingerRecommendation: Sendable, Equatable, Identifiable {
    public let finger: Finger
    public let status: FingerStatus
    /// Confirmed weaknesses whose key belongs to this finger.
    public let weaknesses: [Weakness]
    public var id: Finger { finger }

    /// The Finger Focus target that trains it; `nil` for the thumbs.
    public var target: FingerFocusTarget? { FingerFocusTarget.single(finger) }
}

/// Connects Weakness Analysis to fingers.
///
/// A weakness belongs to the finger recommended for its key: for a letter
/// pair or transition, the finger of the second key, the one that was typed
/// wrong or late. Word weaknesses have no single key and are left out.
/// Recommendations come only from confirmed weaknesses (which already need
/// enough evidence) and from fingers classified as Needs Practice; nothing is
/// recommended while there is not enough data.
public enum FingerRecommender {
    public static func finger(for weakness: Weakness) -> Finger? {
        switch weakness.category {
        case .word: nil
        case .key, .combination, .transition: weakness.item.last.flatMap(FingerMap.finger(for:))
        }
    }

    public static func recommendations(report: FingerReport, weaknesses: WeaknessReport,
                                       limit: Int = 3) -> [FingerRecommendation] {
        var byFinger: [Finger: [Weakness]] = [:]
        if weaknesses.hasEnoughData {
            for weakness in weaknesses.all {
                if let finger = finger(for: weakness) { byFinger[finger, default: []].append(weakness) }
            }
        }
        for (finger, estimate) in report.estimates where estimate.status == .needsPractice {
            byFinger[finger, default: []] += []
        }
        return byFinger
            .map { finger, list in
                FingerRecommendation(finger: finger, status: report.estimates[finger]?.status ?? .insufficientData,
                                     weaknesses: list.sorted { ($0.severity, $1.id) > ($1.severity, $0.id) })
            }
            .sorted { a, b in
                let rank = { (r: FingerRecommendation) in r.status == .needsPractice ? 1 : 0 }
                return (rank(a), a.weaknesses.count, b.finger.rawValue) > (rank(b), b.weaknesses.count, a.finger.rawValue)
            }
            .prefix(limit)
            .map { $0 }
    }
}
