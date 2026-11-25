import Foundation

/// Something to practise more: a single key ("k") or a transition between
/// two keys ("dk"). `level` is how much extra practice it gets (1...3).
public struct FocusItem: Sendable, Hashable {
    public let item: String
    public let level: Int

    public init(item: String, level: Int) {
        self.item = item
        self.level = level
    }

    public var isKey: Bool { item.count == 1 }
}

/// One round of Muscle Memory training.
public struct Exercise: Sendable, Equatable {
    public let category: TrainingCategory
    public let stage: TrainingStage
    public let text: String
    /// The keys introduced most recently (stages 1–3).
    public let newKeys: [Character]
    /// Extra practice that was added for keys or transitions the user finds hard.
    public let focus: [FocusItem]
    /// True when the Words stage fell back to patterns because too few real
    /// words use only the allowed keys. The UI must say so.
    public let isPracticePattern: Bool

    /// Every key the text uses, besides space.
    public var keys: Set<Character> { Set(text).subtracting([" "]) }
}

/// Builds exercise text. Pure and deterministic for a given seed.
///
/// Rules that always hold:
/// - Text uses only the category's allowed keys and single spaces.
/// - Stages 1–3 use only keys from groups introduced so far, plus the
///   home-row key each one is reached from. Groups are introduced one at a
///   time: a category starts with all but its last two groups and adds one
///   per qualifying round.
/// - Extra focus practice never adds a key the exercise could not already use,
///   and adds at most `maxFocusBlocks` blocks.
public enum ExerciseGenerator {
    public static let maxKeysPerRound = 8
    public static let maxPairsPerRound = 5
    public static let maxPatternsPerRound = 5
    public static let wordsPerRound = 12
    public static let maximumWordLength = 8
    public static let minimumWordPool = 8
    public static let maxFocusItems = 3
    public static let maxFocusBlocks = 4

    /// How many of a category's key groups are in play.
    public static func activeGroupCount(groups: Int, qualifyingRounds: Int) -> Int {
        guard groups > 0 else { return 0 }
        return min(groups, max(1, groups - 2) + max(0, qualifyingRounds))
    }

    public static func exercise(category: TrainingCategory, stage: TrainingStage, qualifyingRounds: Int = 0,
                                focus: [FocusItem] = [], seed: UInt64) -> Exercise {
        var rng = SeededGenerator(seed: seed)
        let groups = category.keyGroups
        let allowed = category.allowedKeys

        if stage == .words {
            if let words = words(allowed: allowed, targets: Set(groups.joined()), focus: focus, using: &rng) {
                return Exercise(category: category, stage: stage, text: words.text, newKeys: [],
                                focus: words.focus, isPracticePattern: false)
            }
            let drill = drill(.patterns, groups: groups, allowed: allowed, focus: focus, using: &rng)
            return Exercise(category: category, stage: stage, text: drill.text, newKeys: [],
                            focus: drill.focus, isPracticePattern: true)
        }

        let count = activeGroupCount(groups: groups.count, qualifyingRounds: qualifyingRounds)
        let drill = drill(stage, groups: Array(groups.prefix(count)), allowed: allowed, focus: focus, using: &rng)
        return Exercise(category: category, stage: stage, text: drill.text, newKeys: drill.newKeys,
                        focus: drill.focus, isPracticePattern: false)
    }

    /// The keys an exercise built from `groups` may contain: the keys
    /// themselves and the home-row key each is reached from.
    public static func permittedKeys(groups: [[Character]], allowed: Set<Character>) -> Set<Character> {
        var keys = Set(groups.joined()).intersection(allowed)
        for key in keys {
            if let anchor = anchor(for: key, allowed: allowed) { keys.insert(anchor) }
        }
        return keys
    }

    // MARK: Drills (stages 1–3)

    struct Drill {
        var text: String
        var newKeys: [Character]
        var focus: [FocusItem]
    }

    static func drill(_ stage: TrainingStage, groups: [[Character]], allowed: Set<Character>,
                      focus: [FocusItem], using rng: inout SeededGenerator) -> Drill {
        let groups = groups.map { $0.filter(allowed.contains) }.filter { !$0.isEmpty }
        let (keys, newKeys) = selectKeys(from: groups, using: &rng)
        let permitted = permittedKeys(groups: groups, allowed: allowed)

        var blocks: [[String]]
        switch stage {
        case .singleKeys: blocks = singleKeyBlocks(keys).shuffled(using: &rng)
        case .transitions: blocks = transitionBlocks(keys, allowed: allowed, using: &rng)
        case .patterns, .words: blocks = patternBlocks(keys, allowed: allowed, using: &rng)
        }
        let applied = insertFocus(focus, stage: stage, keys: keys, permitted: permitted, into: &blocks, using: &rng)
        return Drill(text: blocks.flatMap { $0 }.joined(separator: " "), newKeys: newKeys, focus: applied)
    }

    /// The newest group, plus whole earlier groups for review while they fit.
    static func selectKeys(from groups: [[Character]], using rng: inout SeededGenerator) -> (keys: [Character], newKeys: [Character]) {
        guard let newest = groups.last else { return ([], []) }
        var count = newest.count
        var chosen = Set<Int>()
        for index in Array(groups.indices.dropLast()).shuffled(using: &rng)
        where count + groups[index].count <= maxKeysPerRound {
            chosen.insert(index)
            count += groups[index].count
        }
        let review = groups.indices.dropLast().filter { chosen.contains($0) }.flatMap { groups[$0] }
        return (review + newest, newest)
    }

    /// "ffff jjjj ffff jjjj"
    static func singleKeyBlocks(_ keys: [Character]) -> [[String]] {
        stride(from: 0, to: keys.count, by: 2).map { index in
            let first = run(keys[index], 4)
            guard index + 1 < keys.count else { return [first, first] }
            let second = run(keys[index + 1], 4)
            return [first, second, first, second]
        }
    }

    /// "fj fj fj fj"
    static func transitionBlocks(_ keys: [Character], allowed: Set<Character>,
                                 using rng: inout SeededGenerator) -> [[String]] {
        var primary = stride(from: 0, to: keys.count - 1, by: 2).map { String([keys[$0], keys[$0 + 1]]) }

        var secondary: [String] = []
        for key in keys {
            if let anchor = anchor(for: key, allowed: allowed) { secondary.append(String([anchor, key])) }
        }
        let placed = keys.compactMap { key in KeyboardLayout.position(of: key).map { (key, $0) } }
            .sorted { ($0.1.row, $0.1.column) < ($1.1.row, $1.1.column) }
        for (a, b) in zip(placed, placed.dropFirst())
        where a.1.row == b.1.row && b.1.column == a.1.column + 1 && FingerMap.hand(for: a.0) == FingerMap.hand(for: b.0) {
            secondary.append(String([a.0, b.0]))
        }

        if primary.isEmpty, let only = keys.first {
            primary = [String([anchor(for: only, allowed: allowed) ?? only, only])]
        }
        secondary = unique(secondary)
            .filter { pair in !primary.contains(pair) && !primary.contains(String(pair.reversed())) }
            .shuffled(using: &rng)
        let pairs = primary + secondary.prefix(max(0, maxPairsPerRound - primary.count))
        return pairs.map { Array(repeating: $0, count: 4) }
    }

    /// "asdf asdf asdf", "frf frf frf"
    static func patternBlocks(_ keys: [Character], allowed: Set<Character>,
                              using rng: inout SeededGenerator) -> [[String]] {
        var candidates: [String] = []

        // Rolls along one row with one hand, in both directions.
        var runs: [String: [(Character, Int)]] = [:]
        for key in keys {
            guard let position = KeyboardLayout.position(of: key), let hand = FingerMap.hand(for: key) else { continue }
            runs["\(position.row)\(hand.rawValue)", default: []].append((key, position.column))
        }
        for name in runs.keys.sorted() {
            let ordered = runs[name]!.sorted { $0.1 < $1.1 }.map(\.0)
            for start in stride(from: 0, to: ordered.count, by: 4) {
                let chunk = Array(ordered[start..<min(start + 4, ordered.count)])
                guard chunk.count >= 2 else { continue }
                candidates.append(String(chunk))
                candidates.append(String(chunk.reversed()))
            }
        }
        // Reaches out from the home row and back.
        for key in keys {
            if let anchor = anchor(for: key, allowed: allowed) { candidates.append(String([anchor, key, anchor])) }
        }
        // Alternation between paired keys.
        for index in stride(from: 0, to: keys.count - 1, by: 2) {
            candidates.append(String([keys[index], keys[index + 1], keys[index], keys[index + 1]]))
        }
        if candidates.isEmpty, let only = keys.first { candidates = [run(only, 3)] }

        // Pick patterns that cover as many different keys as possible.
        var remaining = unique(candidates).shuffled(using: &rng)
        var chosen: [String] = []
        var covered = Set<Character>()
        while chosen.count < maxPatternsPerRound, !remaining.isEmpty {
            var best = 0
            var bestGain = -1
            for (index, pattern) in remaining.enumerated() {
                let gain = Set(pattern).subtracting(covered).count
                if gain > bestGain { best = index; bestGain = gain }
            }
            let pattern = remaining.remove(at: best)
            covered.formUnion(pattern)
            chosen.append(pattern)
        }
        return chosen.map { Array(repeating: $0, count: 3) }
    }

    // MARK: Focus

    static func insertFocus(_ focus: [FocusItem], stage: TrainingStage, keys: [Character], permitted: Set<Character>,
                            into blocks: inout [[String]], using rng: inout SeededGenerator) -> [FocusItem] {
        let usable = focus
            .filter { item in
                item.level > 0 && (1...2).contains(item.item.count) && item.item.allSatisfy { permitted.contains($0) }
            }
            .sorted { ($0.level, $1.item) > ($1.level, $0.item) }
            .prefix(maxFocusItems)

        var budget = maxFocusBlocks
        var applied: [FocusItem] = []
        for item in usable where budget > 0 {
            let block = focusBlock(item.item, stage: stage, keys: keys, permitted: permitted)
            for _ in 0..<min(item.level, budget) {
                blocks.insert(block, at: Int.random(in: 0...blocks.count, using: &rng))
                budget -= 1
            }
            applied.append(item)
        }
        return applied
    }

    static func focusBlock(_ item: String, stage: TrainingStage, keys: [Character], permitted: Set<Character>) -> [String] {
        let characters = Array(item)
        let pair: [Character]
        if characters.count == 2 {
            pair = characters
        } else {
            let key = characters[0]
            let partner = anchor(for: key, allowed: permitted)
                ?? mirror(of: key, in: keys)
                ?? keys.first { $0 != key }
                ?? key
            pair = [key, partner]
        }
        switch stage {
        case .singleKeys:
            return characters.count == 1 ? [run(pair[0], 4), run(pair[0], 4)] : [run(pair[0], 4), run(pair[1], 4)]
        case .transitions:
            return Array(repeating: String(pair), count: 4)
        case .patterns, .words:
            let pattern = characters.count == 1 ? String([pair[1], pair[0], pair[1]]) : String(pair + pair)
            return Array(repeating: pattern, count: 3)
        }
    }

    // MARK: Words (stage 4)

    struct WordDrill {
        var text: String
        var focus: [FocusItem]
    }

    /// Words that use only `allowed` keys, preferring those that contain at
    /// least one of `targets`.
    public static func wordPool(allowed: Set<Character>, targets: Set<Character>,
                                from list: [String] = TrainingWords.all) -> [String] {
        let usable = list.filter { word in
            !word.isEmpty && word.count <= maximumWordLength && word.allSatisfy { allowed.contains($0) }
        }
        let preferred = usable.filter { word in word.contains { targets.contains($0) } }
        return preferred.count >= minimumWordPool ? preferred : usable
    }

    /// `nil` when fewer than `minimumWordPool` real words fit.
    static func words(allowed: Set<Character>, targets: Set<Character>, focus: [FocusItem],
                      from list: [String] = TrainingWords.all, using rng: inout SeededGenerator) -> WordDrill? {
        let pool = wordPool(allowed: allowed, targets: targets, from: list)
        guard Set(pool).count >= minimumWordPool else { return nil }

        let active = focus.filter { item in item.level > 0 && item.item.allSatisfy { allowed.contains($0) } }
        let weights = pool.map { word in
            1 + active.reduce(0) { total, item in total + (word.contains(item.item) ? 2 * item.level : 0) }
        }
        let total = weights.reduce(0, +)

        var chosen: [String] = []
        while chosen.count < wordsPerRound {
            var pick = Int.random(in: 0..<total, using: &rng)
            var index = 0
            while pick >= weights[index] {
                pick -= weights[index]
                index += 1
            }
            if pool[index] != chosen.last { chosen.append(pool[index]) }
        }
        let applied = active.filter { item in chosen.contains { $0.contains(item.item) } }
        return WordDrill(text: chosen.joined(separator: " "), focus: applied)
    }

    // MARK: Helpers

    /// The home-row key a finger returns to after typing `key`, if different and allowed.
    static func anchor(for key: Character, allowed: Set<Character>) -> Character? {
        guard let home = FingerMap.finger(for: key)?.homeKey, home != key, allowed.contains(home) else { return nil }
        return home
    }

    private static func mirror(of key: Character, in keys: [Character]) -> Character? {
        guard let index = keys.firstIndex(of: key) else { return nil }
        let partner = index.isMultiple(of: 2) ? index + 1 : index - 1
        return keys.indices.contains(partner) ? keys[partner] : nil
    }

    private static func run(_ character: Character, _ count: Int) -> String {
        String(repeating: String(character), count: count)
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}
