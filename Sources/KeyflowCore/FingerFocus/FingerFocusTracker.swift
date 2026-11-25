import Foundation

/// One completed Finger Focus round.
public struct FingerFocusEvent: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let target: FingerFocusTarget
    public let level: FingerFocusLevel
    public let result: RoundResult

    public init(id: UUID = UUID(), date: Date = .now, target: FingerFocusTarget, level: FingerFocusLevel, result: RoundResult) {
        self.id = id
        self.date = date
        self.target = target
        self.level = level
        self.result = result
    }
}

/// How a key has gone recently, from the keys Keyflow saw being pressed.
/// Says nothing about which finger pressed them.
public struct FingerKeyStat: Sendable, Equatable {
    public let key: Character
    /// The finger standard touch typing assigns to the key.
    public let recommendedFinger: Finger
    public let count: ErrorCount

    public var accuracy: Double? { count.attempts > 0 ? 1 - count.rate : nil }
}

/// A key that keeps being missed, and the level suggested for it.
public struct FingerFocusRecommendation: Sendable, Equatable {
    public let key: Character
    public let count: ErrorCount
    public let level: FingerFocusLevel
}

/// Everything derived from Finger Focus history: progress per target and
/// level, the recommended level, how complex the drills should be, adaptive
/// repetition and recommendations.
///
/// A level is **steady** after `MasteryTracker.requiredRounds` rounds at
/// `MasteryTracker.requiredAccuracy` or better, the same bar as Learn
/// lessons. Levels are never locked; steadiness only drives the
/// recommendation and the gradual increase in complexity.
public struct FingerFocusTracker: Sendable {
    public struct LevelProgress: Sendable, Equatable {
        public internal(set) var rounds = 0
        public internal(set) var qualifyingRounds = 0
        public internal(set) var accuracyHistory: [Double] = []

        public init() {}

        public var isSteady: Bool { qualifyingRounds >= MasteryTracker.requiredRounds }
    }

    /// Rounds looked at when deciding a key is a problem.
    public static let recentRounds = 8
    public static let problemMinimumErrors = 3
    public static let problemRate = 0.08
    /// Qualifying rounds at a level per step of extra complexity.
    public static let roundsPerComplexityStep = 2

    private struct LevelKey: Hashable {
        let target: FingerFocusTarget
        let level: FingerFocusLevel
    }

    private var levels: [LevelKey: LevelProgress] = [:]
    private var adaptive: [FingerFocusTarget: AdaptiveRepetition] = [:]
    private var history: [FingerFocusTarget: [FingerFocusEvent]] = [:]

    public init(events: [FingerFocusEvent]) {
        let ordered = events.enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)
        for event in ordered {
            let key = LevelKey(target: event.target, level: event.level)
            levels[key, default: LevelProgress()].rounds += 1
            levels[key]!.accuracyHistory.append(event.result.accuracy)
            if event.result.isQualifying { levels[key]!.qualifyingRounds += 1 }
            history[event.target, default: []].append(event)

            // Only keys and transitions this target trains count toward its focus.
            let allowed = event.target.drillKeys
            let keys = event.result.keys.filter { $0.key.allSatisfy(allowed.contains) }
            let pairs = event.result.pairs.filter { $0.key.allSatisfy(allowed.contains) }
            adaptive[event.target, default: AdaptiveRepetition()].record(keys: keys, pairs: pairs)
        }
    }

    public func progress(_ target: FingerFocusTarget, _ level: FingerFocusLevel) -> LevelProgress {
        levels[LevelKey(target: target, level: level)] ?? LevelProgress()
    }

    public func rounds(_ target: FingerFocusTarget) -> Int { history[target]?.count ?? 0 }

    /// The first level that is not yet steady, otherwise Words.
    public func recommendedLevel(_ target: FingerFocusTarget) -> FingerFocusLevel {
        FingerFocusLevel.allCases.first { !progress(target, $0).isSteady } ?? .words
    }

    /// 0 at first; one step more for every `roundsPerComplexityStep`
    /// qualifying rounds at that level, up to `FingerFocusGenerator.maxComplexity`.
    public func complexity(_ target: FingerFocusTarget, _ level: FingerFocusLevel) -> Int {
        min(FingerFocusGenerator.maxComplexity, progress(target, level).qualifyingRounds / Self.roundsPerComplexityStep)
    }

    public func adaptive(for target: FingerFocusTarget) -> AdaptiveRepetition {
        adaptive[target] ?? AdaptiveRepetition()
    }

    /// The target keys over the last `recentRounds` rounds for this target,
    /// in the order the target lists them.
    public func keyStats(_ target: FingerFocusTarget) -> [FingerKeyStat] {
        let recent = (history[target] ?? []).suffix(Self.recentRounds)
        return target.keys.compactMap { key in
            guard let finger = FingerMap.finger(for: key) else { return nil }
            let count = recent.reduce(ErrorCount()) { total, event in total + (event.result.keys[String(key)] ?? ErrorCount()) }
            return FingerKeyStat(key: key, recommendedFinger: finger, count: count)
        }
    }

    /// Target keys missed repeatedly in recent rounds, worst first, each with
    /// the most basic level at which it is still being missed.
    public func recommendations(_ target: FingerFocusTarget) -> [FingerFocusRecommendation] {
        let recent = Array((history[target] ?? []).suffix(Self.recentRounds))
        return keyStats(target)
            .filter { $0.count.errors >= Self.problemMinimumErrors && $0.count.rate >= Self.problemRate }
            .sorted { ($0.count.errors, $0.count.rate) > ($1.count.errors, $1.count.rate) }
            .map { stat in
                let level = FingerFocusLevel.allCases.first { level in
                    let count = recent.filter { $0.level == level }
                        .reduce(ErrorCount()) { $0 + ($1.result.keys[String(stat.key)] ?? ErrorCount()) }
                    return count.attempts > 0 && count.errors > 0 && count.rate >= Self.problemRate
                } ?? .activation
                return FingerFocusRecommendation(key: stat.key, count: stat.count, level: level)
            }
    }
}
