import Foundation

/// Decides which keys and transitions get extra practice.
///
/// After each round, every key and transition that was typed is checked:
/// - **Struggling** — at least `minimumAttempts` attempts, at least
///   `minimumErrors` errors and an error rate of `struggleRate` or more. Its
///   level rises by one, up to `maxLevel`. A single slip never qualifies.
/// - **Recovered** — at least `minimumAttempts` attempts and an error rate of
///   `recoveredRate` or less. Its level falls by one.
/// - Anything else leaves the level unchanged.
///
/// So that nothing is drilled forever, an item that stays in focus for
/// `maxFocusedRounds` rounds is dropped and rests for `cooldownRounds` rounds,
/// during which it cannot return to focus. The generator also caps the extra
/// practice per exercise.
public struct AdaptiveRepetition: Sendable, Equatable {
    public struct ItemState: Sendable, Equatable {
        public internal(set) var level = 0
        public internal(set) var focusedRounds = 0
        public internal(set) var cooldown = 0
    }

    public static let maxLevel = 3
    public static let maxFocusedRounds = 6
    public static let cooldownRounds = 3
    public static let minimumAttempts = 3
    public static let minimumErrors = 2
    public static let struggleRate = 0.15
    public static let recoveredRate = 0.05

    public private(set) var items: [String: ItemState] = [:]

    public init() {}

    public func level(of item: String) -> Int { items[item]?.level ?? 0 }

    public mutating func record(_ result: RoundResult) {
        record(keys: result.keys, pairs: result.pairs)
    }

    public mutating func record(keys: [String: ErrorCount], pairs: [String: ErrorCount]) {
        let observed = keys.merging(pairs) { $0 + $1 }
        for item in observed.keys.sorted() where !item.contains(" ") {
            let count = observed[item]!
            guard count.attempts > 0 else { continue }
            var state = items[item] ?? ItemState()

            if count.attempts >= Self.minimumAttempts, count.errors >= Self.minimumErrors, count.rate >= Self.struggleRate {
                if state.cooldown == 0 { state.level = min(Self.maxLevel, state.level + 1) }
            } else if state.level > 0, count.attempts >= Self.minimumAttempts, count.rate <= Self.recoveredRate {
                state.level -= 1
                state.focusedRounds = 0
            }
            items[item] = state
        }

        for (item, original) in items {
            var state = original
            if state.level > 0 {
                state.focusedRounds += 1
                if state.focusedRounds >= Self.maxFocusedRounds {
                    state = ItemState(level: 0, focusedRounds: 0, cooldown: Self.cooldownRounds)
                }
            } else if state.cooldown > 0 {
                state.cooldown -= 1
            }
            items[item] = state.level == 0 && state.cooldown == 0 ? nil : state
        }
    }

    /// Items currently in focus, highest level first.
    public func focusItems(limit: Int = ExerciseGenerator.maxFocusItems) -> [FocusItem] {
        items.filter { $0.value.level > 0 }
            .map { FocusItem(item: $0.key, level: $0.value.level) }
            .sorted { ($0.level, $1.item) > ($1.level, $0.item) }
            .prefix(limit)
            .map { $0 }
    }
}
