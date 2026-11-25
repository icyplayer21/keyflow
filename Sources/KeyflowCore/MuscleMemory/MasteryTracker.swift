import Foundation

public struct StageProgress: Sendable, Equatable {
    public internal(set) var rounds = 0
    public internal(set) var qualifyingRounds = 0
    public internal(set) var skipped = false
    /// Accuracy of every completed round, oldest first.
    public internal(set) var accuracyHistory: [Double] = []

    public init() {}

    public var isMastered: Bool { qualifyingRounds >= MasteryTracker.requiredRounds }
    public var bestAccuracy: Double? { accuracyHistory.max() }
}

public enum StageStatus: Sendable, Equatable {
    /// The previous stage is neither mastered nor skipped.
    case locked
    /// Open to practise; not yet mastered.
    case available
    /// Passed over by the user. Never counts as mastered.
    case skipped
    /// Completed `requiredRounds` rounds at `requiredAccuracy` or better.
    case mastered
}

public struct MistypedKey: Sendable, Equatable {
    public let key: Character
    public let count: ErrorCount
}

/// Everything derived from the training history: mastery per stage,
/// adaptive repetition per category, and frequently mistyped keys.
///
/// A stage is **mastered** after `requiredRounds` completed rounds with at
/// least `requiredAccuracy` accuracy. The rounds need not be consecutive, and
/// rounds below the bar neither count nor reset progress. A **skipped** stage
/// unlocks the next one but is never mastered unless the user later earns it.
public struct MasteryTracker: Sendable {
    public static let requiredAccuracy = 0.95
    public static let requiredRounds = 3

    private struct StageKey: Hashable {
        let category: TrainingCategory
        let stage: TrainingStage
    }

    private var stages: [StageKey: StageProgress] = [:]
    private var adaptive: [TrainingCategory: AdaptiveRepetition] = [:]
    private var keyErrors: [TrainingCategory: [String: ErrorCount]] = [:]

    public init(events: [TrainingEvent]) {
        let ordered = events.enumerated()
            .sorted { ($0.element.date, $0.offset) < ($1.element.date, $1.offset) }
            .map(\.element)
        for event in ordered {
            let key = StageKey(category: event.category, stage: event.stage)
            switch event.kind {
            case .skip:
                stages[key, default: StageProgress()].skipped = true
            case .round(let result):
                stages[key, default: StageProgress()].rounds += 1
                stages[key]!.accuracyHistory.append(result.accuracy)
                if result.isQualifying { stages[key]!.qualifyingRounds += 1 }
                adaptive[event.category, default: AdaptiveRepetition()].record(result)
                keyErrors[event.category, default: [:]].merge(result.keys) { $0 + $1 }
            }
        }
    }

    public func progress(_ category: TrainingCategory, _ stage: TrainingStage) -> StageProgress {
        stages[StageKey(category: category, stage: stage)] ?? StageProgress()
    }

    public func status(_ category: TrainingCategory, _ stage: TrainingStage) -> StageStatus {
        let progress = progress(category, stage)
        if progress.isMastered { return .mastered }
        if progress.skipped { return .skipped }
        guard let previous = stage.previous else { return .available }
        switch status(category, previous) {
        case .mastered, .skipped: return .available
        case .available, .locked: return .locked
        }
    }

    /// The stage to work on next: the first one open and not yet passed,
    /// otherwise the first skipped one, otherwise the last.
    public func currentStage(_ category: TrainingCategory) -> TrainingStage {
        TrainingStage.allCases.first { status(category, $0) == .available }
            ?? TrainingStage.allCases.first { status(category, $0) == .skipped }
            ?? .words
    }

    public func masteredStages(_ category: TrainingCategory) -> Int {
        TrainingStage.allCases.filter { status(category, $0) == .mastered }.count
    }

    public func adaptive(for category: TrainingCategory) -> AdaptiveRepetition {
        adaptive[category] ?? AdaptiveRepetition()
    }

    /// Keys mistyped at least twice, most errors first. `nil` covers every category.
    public func mistypedKeys(in category: TrainingCategory? = nil, limit: Int = 5) -> [MistypedKey] {
        var totals: [String: ErrorCount] = [:]
        for (owner, counts) in keyErrors where category == nil || owner == category {
            totals.merge(counts) { $0 + $1 }
        }
        return totals
            .filter { $0.key.count == 1 && $0.value.errors >= 2 }
            .map { MistypedKey(key: Character($0.key), count: $0.value) }
            .sorted { ($0.count.errors, $0.count.rate, String($1.key)) > ($1.count.errors, $1.count.rate, String($0.key)) }
            .prefix(limit)
            .map { $0 }
    }
}
