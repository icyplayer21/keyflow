import Foundation

/// Shift against Caps Lock for one length of capitals.
public struct MethodComparison: Sendable, Equatable, Identifiable {
    public enum Verdict: Sendable, Equatable {
        case shiftFaster, capsLockFaster
        /// Enough runs of both, but their ranges overlap.
        case noClearDifference
        /// Too few runs of one or both.
        case insufficient
    }

    public let group: SegmentLength
    public let shift: CapitalisationOverhead.Estimate
    public let capsLock: CapitalisationOverhead.Estimate
    public let verdict: Verdict

    public var id: SegmentLength { group }
}

/// Everything the Progress screen shows about Typing Mechanics.
public struct MechanicsHistory: Sendable {
    public struct RoundPoint: Sendable, Equatable, Identifiable {
        public let index: Int
        public let date: Date
        public let characterAccuracy: Double
        public let techniqueAccuracy: Double?
        public var id: Int { index }
    }

    public struct OverheadPoint: Sendable, Equatable, Identifiable {
        public let index: Int
        public let method: CapitalisationOverhead.Method
        /// That round's median overhead per run.
        public let overheadMs: Double
        public var id: String { "\(index)-\(method.rawValue)" }
    }

    /// Rounds a summary average looks at.
    public static let recentRounds = 20
    /// Lab comparisons the method comparison looks at.
    public static let recentComparisons = 20
    /// A round's own overhead is charted from this many runs of a method.
    public static let pointRuns = 3

    public let rounds: Int
    public let recentCharacterAccuracy: Double?
    public let recentTechniqueAccuracy: Double?
    public let steadyStages: Int
    /// Stages that can become steady (the Lab has none).
    public let stages: Int
    public let points: [RoundPoint]
    public let overheadPoints: [OverheadPoint]
    public let overhead: [CapitalisationOverhead.Method: CapitalisationOverhead.Estimate]
    public let comparisonsDone: Int
    public let methodComparison: [MethodComparison]
    public let recommendations: [MechanicsRecommendation]

    public init(events: [MechanicsEvent]) {
        let ordered = events.sorted { $0.date < $1.date }
        let recent = ordered.suffix(Self.recentRounds).map(\.result)
        rounds = ordered.count

        let keystrokes = recent.reduce(0) { $0 + $1.keystrokes }
        recentCharacterAccuracy = keystrokes > 0 ? Double(recent.reduce(0) { $0 + $1.correctKeystrokes }) / Double(keystrokes) : nil
        let checked = recent.reduce(0) { $0 + $1.techniqueChecked }
        recentTechniqueAccuracy = checked > 0 ? Double(recent.reduce(0) { $0 + $1.techniqueCorrect }) / Double(checked) : nil

        let progress = MechanicsProgress(events: ordered)
        let trainable = MechanicsDrill.allCases.filter { $0.area != .capitalisationLab }
        stages = trainable.count
        steadyStages = trainable.filter { progress.progress($0).isSteady }.count

        points = ordered.enumerated().map { index, event in
            RoundPoint(index: index + 1, date: event.date, characterAccuracy: event.result.characterAccuracy,
                       techniqueAccuracy: event.result.techniqueAccuracy)
        }
        overheadPoints = ordered.enumerated().flatMap { index, event -> [OverheadPoint] in
            let observations = CapitalisationOverhead.observations(from: [event.result])
            return CapitalisationOverhead.Method.allCases.compactMap { method in
                let own = observations.filter { $0.method == method }.map(\.overheadMs)
                guard own.count >= Self.pointRuns, let median = TimingSamples(own).median else { return nil }
                return OverheadPoint(index: index + 1, method: method, overheadMs: median)
            }
        }
        overhead = CapitalisationOverhead.estimates(from: ordered.map(\.result))

        let comparisons = Array(progress.comparisons.suffix(Self.recentComparisons))
        comparisonsDone = progress.comparisons.count
        methodComparison = Self.compare(comparisons)
        recommendations = MechanicsRecommender.recommendations(from: ordered)
    }

    /// Shift against Caps Lock per length group, from Lab comparisons only:
    /// the same passages, typed in counterbalanced order. A method is called
    /// faster for a length only when both have `CapitalisationOverhead.minimumRuns`
    /// runs and the 95% ranges of their median overheads do not overlap.
    public static func compare(_ comparisons: [MechanicsProgress.LabComparison]) -> [MethodComparison] {
        let shift = CapitalisationOverhead.observations(from: comparisons.map(\.shift)).filter { $0.method == .shift }
        let caps = CapitalisationOverhead.observations(from: comparisons.map(\.capsLock)).filter { $0.method == .capsLock }
        return SegmentLength.allCases.map { group in
            let s = CapitalisationOverhead.estimate(shift, method: .shift, group: group)
            let c = CapitalisationOverhead.estimate(caps, method: .capsLock, group: group)
            let verdict: MethodComparison.Verdict
            if let a = s.range, let b = c.range, s.isSufficient, c.isSufficient {
                if a.upperBound < b.lowerBound { verdict = .shiftFaster }
                else if b.upperBound < a.lowerBound { verdict = .capsLockFaster }
                else { verdict = .noClearDifference }
            } else if s.isSufficient, c.isSufficient {
                verdict = .noClearDifference
            } else {
                verdict = .insufficient
            }
            return MethodComparison(group: group, shift: s, capsLock: c, verdict: verdict)
        }
    }

    /// One plain sentence about which method suits which length, claiming
    /// nothing the evidence does not support.
    public var methodSummary: String {
        let faster = { (verdict: MethodComparison.Verdict) in
            methodComparison.filter { $0.verdict == verdict }.map { "\($0.group.title)-letter" }
        }
        let shiftGroups = faster(.shiftFaster), capsGroups = faster(.capsLockFaster)
        var parts: [String] = []
        if !capsGroups.isEmpty { parts.append("for \(Self.list(capsGroups)) capitals, Caps Lock has been faster") }
        if !shiftGroups.isEmpty { parts.append("for \(Self.list(shiftGroups)) capitals, Shift has been faster") }
        if !parts.isEmpty {
            let sentence = parts.joined(separator: "; ") + " in your recent comparisons."
            return sentence.prefix(1).uppercased() + sentence.dropFirst()
        }
        if methodComparison.contains(where: { $0.verdict == .noClearDifference }) {
            return "Neither method is consistently faster yet."
        }
        return comparisonsDone == 0
            ? "No comparisons yet. In the Capitalisation Lab, type the same passage with Shift and with Caps Lock."
            : "Not enough comparisons yet: \(comparisonsDone) done; about 4 are needed before a length can be compared."
    }

    private static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items.last!
    }
}
