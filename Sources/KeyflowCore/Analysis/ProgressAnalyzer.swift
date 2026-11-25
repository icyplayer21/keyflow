import Foundation

/// A saved session together with its keystroke analysis.
public struct AnalyzedSession: Sendable, Equatable {
    public let summary: SessionSummary
    public let analysis: SessionAnalysis

    public init(summary: SessionSummary, analysis: SessionAnalysis) {
        self.summary = summary
        self.analysis = analysis
    }
}

/// How many weaknesses were confirmed as of one session.
public struct WeaknessHistoryPoint: Sendable, Equatable, Identifiable {
    /// 1-based position of the session in the history.
    public let index: Int
    public let date: Date
    public let accuracy: Int
    public let speed: Int
    public var id: Int { index }
}

/// A weakness that was confirmed at some point but is not confirmed now.
/// This says only that it is no longer flagged, not that it was overcome:
/// it may simply have dropped out of the recent sessions.
public struct FormerWeakness: Sendable, Equatable, Identifiable {
    /// The finding as it stood when last confirmed.
    public let weakness: Weakness
    public let lastFlagged: Date
    public var id: String { weakness.id }
}

/// Everything the Progress dashboard shows.
public struct ProgressReport: Sendable, Equatable {
    /// Completed tests, oldest first.
    public var tests: [SessionSummary]
    public var practiceSessions: Int
    /// Highest net WPM among tests.
    public var personalBest: SessionSummary?
    /// Averages over the most recent `ProgressAnalyzer.recentTests` tests.
    public var recentWPM: Double?
    public var recentAccuracy: Double?
    public var recentConsistency: Double?
    /// Time spent typing across all sessions.
    public var totalTime: TimeInterval

    /// Aggregate over the most recent `ProgressAnalyzer.window` sessions.
    public var profile: TypingProfile
    public var weaknesses: WeaknessReport
    /// When each current weakness was first confirmed.
    public var firstFlagged: [String: Date]
    public var weaknessHistory: [WeaknessHistoryPoint]
    public var formerWeaknesses: [FormerWeakness]
}

public enum ProgressAnalyzer {
    /// Sessions (of any kind) that feed the current profile and weaknesses.
    public static let window = 30
    public static let recentTests = 10

    /// - Parameter sessions: Any order; sorted by date internally.
    public static func report(for sessions: [AnalyzedSession],
                              thresholds: WeaknessAnalyzer.Thresholds = .init()) -> ProgressReport {
        let sessions = sessions.sorted { $0.summary.date < $1.summary.date }
        let tests = sessions.map(\.summary).filter { $0.kind == .test }
        let recent = tests.suffix(recentTests)

        // Re-run the analysis as of every session to see how findings evolved.
        var history: [WeaknessHistoryPoint] = []
        var firstFlagged: [String: Date] = [:]
        var lastFlagged: [String: (weakness: Weakness, date: Date)] = [:]
        var profile = TypingProfile()
        var current = WeaknessAnalyzer.analyze(profile, thresholds: thresholds)

        for (offset, session) in sessions.enumerated() {
            let start = max(0, offset - window + 1)
            profile = TypingProfile(sessions[start...offset].map(\.analysis))
            current = WeaknessAnalyzer.analyze(profile, thresholds: thresholds)
            for weakness in current.all {
                if firstFlagged[weakness.id] == nil { firstFlagged[weakness.id] = session.summary.date }
                lastFlagged[weakness.id] = (weakness, session.summary.date)
            }
            if current.hasEnoughData {
                history.append(WeaknessHistoryPoint(index: offset + 1, date: session.summary.date,
                                                    accuracy: current.accuracy.count, speed: current.speed.count))
            }
        }

        let currentIDs = Set(current.all.map(\.id))
        let former = lastFlagged.values
            .filter { !currentIDs.contains($0.weakness.id) }
            .map { FormerWeakness(weakness: $0.weakness, lastFlagged: $0.date) }
            .sorted { ($0.lastFlagged, $1.id) > ($1.lastFlagged, $0.id) }

        return ProgressReport(
            tests: tests,
            practiceSessions: sessions.count - tests.count,
            personalBest: tests.max { ($0.metrics.netWPM, $1.date) < ($1.metrics.netWPM, $0.date) },
            recentWPM: average(recent.map(\.metrics.netWPM)),
            recentAccuracy: average(recent.map(\.metrics.accuracy)),
            recentConsistency: average(recent.compactMap(\.consistency)),
            totalTime: sessions.reduce(0) { $0 + $1.summary.metrics.elapsed },
            profile: profile,
            weaknesses: current,
            firstFlagged: firstFlagged.filter { currentIDs.contains($0.key) },
            weaknessHistory: history,
            formerWeaknesses: former
        )
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
