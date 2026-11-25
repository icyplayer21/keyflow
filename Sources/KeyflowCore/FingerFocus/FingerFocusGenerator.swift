import Foundation

/// One Finger Focus round.
public struct FingerFocusExercise: Sendable, Equatable {
    public let target: FingerFocusTarget
    public let level: FingerFocusLevel
    public let text: String
    /// 0 = basic. Higher values add longer and less familiar transitions.
    public let complexity: Int
    /// Keys and transitions that got extra practice because of recent errors.
    public let focus: [FocusItem]

    public init(target: FingerFocusTarget, level: FingerFocusLevel, text: String, complexity: Int = 0, focus: [FocusItem] = []) {
        self.target = target
        self.level = level
        self.text = text
        self.complexity = complexity
        self.focus = focus
    }

    /// Every key the text uses, besides space.
    public var keys: Set<Character> { Set(text).subtracting([" "]) }

    /// How many characters of the text are on the target finger's keys.
    public var targetKeyShare: Double {
        let characters = text.filter { $0 != " " }
        guard !characters.isEmpty else { return 0 }
        let targets = Set(target.keys)
        return Double(characters.filter { targets.contains($0) }.count) / Double(characters.count)
    }
}

/// Builds Finger Focus text. Pure and deterministic for a given seed.
///
/// Rules that always hold:
/// - Levels 1–3 use only the target fingers' keys and their neighbours' keys
///   (`FingerFocusTarget.drillKeys`); level 1 uses target keys only.
/// - Every level-1 to level-3 unit contains at least one target key.
/// - Rounds are short: a few dozen keystrokes, so a set is several short
///   rounds rather than one long one.
/// - Extra focus practice never adds a key outside those rules and adds at
///   most `maxFocusBlocks` blocks.
public enum FingerFocusGenerator {
    public static let runLength = 3
    public static let unitsPerBlock = 4
    public static let maxFocusBlocks = 4
    public static let maxComplexity = 2
    public static let wordsPerRound = 10
    public static let maximumWordLength = 8
    public static let minimumWordPool = 12
    /// Every this many words, a word on the right ring or pinky gets the
    /// punctuation key that finger owns ("." or ";").
    public static let punctuationEvery = 4

    public static func exercise(target: FingerFocusTarget, level: FingerFocusLevel, complexity: Int = 0,
                                focus: [FocusItem] = [], seed: UInt64) -> FingerFocusExercise {
        var rng = SeededGenerator(seed: seed)
        let complexity = min(max(0, complexity), maxComplexity)

        if level == .words {
            let words = words(for: target, focus: focus, using: &rng)
            return FingerFocusExercise(target: target, level: level, text: words.text, complexity: complexity,
                                       focus: words.focus)
        }

        var blocks: [[String]]
        switch level {
        case .activation: blocks = activationBlocks(target, complexity: complexity, using: &rng)
        case .coordination: blocks = coordinationBlocks(target, complexity: complexity, using: &rng)
        case .movement, .words: blocks = movementBlocks(target, complexity: complexity, using: &rng)
        }
        let applied = insertFocus(focus, target: target, level: level, into: &blocks, using: &rng)
        return FingerFocusExercise(target: target, level: level, text: blocks.joined().joined(separator: " "),
                                   complexity: complexity, focus: applied)
    }

    // MARK: Level 1: activation

    /// Basic: "aaa aaa aaa aaa" per key. With complexity, keys alternate:
    /// "aaa qqq aaa zzz".
    static func activationBlocks(_ target: FingerFocusTarget, complexity: Int,
                                 using rng: inout SeededGenerator) -> [[String]] {
        // About six key blocks per round: two passes over a three-key finger,
        // one over two fingers or an index finger's six keys.
        let passes = max(1, 6 / max(1, target.keys.count))
        var blocks: [[String]] = []
        for _ in 0..<passes {
            blocks += target.keys.shuffled(using: &rng).map { key in
                Array(repeating: run(key, runLength), count: unitsPerBlock)
            }
        }
        guard complexity > 0 else { return blocks }

        // Each non-home key alternates with its home key, so the finger
        // practises leaving and returning.
        for finger in target.fingers {
            let keys = FingerKeys.keys(for: finger)
            guard let home = keys.first else { continue }
            for key in keys.dropFirst().prefix(2) {
                blocks.insert([run(home, runLength), run(key, runLength), run(home, runLength), run(key, runLength)],
                              at: Int.random(in: 0...blocks.count, using: &rng))
            }
        }
        return blocks
    }

    // MARK: Level 2: coordination

    /// Same-row pairs of a target key and a neighbouring finger's key.
    public static func coordinationPairs(_ target: FingerFocusTarget) -> [String] {
        var pairs: [String] = []
        for row in 0..<3 {
            for finger in target.fingers {
                for neighbour in FingerKeys.neighbours(of: finger) {
                    if let key = FingerKeys.key(for: finger, row: row), let other = FingerKeys.key(for: neighbour, row: row) {
                        pairs.append(String([key, other]))
                    }
                }
            }
        }
        return pairs
    }

    /// Basic: "as sa as sa". Complexity 1 adds rolls ("asa sas"); 2 adds
    /// diagonal reaches between rows ("aw wa").
    static func coordinationBlocks(_ target: FingerFocusTarget, complexity: Int,
                                   using rng: inout SeededGenerator) -> [[String]] {
        let pairs = coordinationPairs(target)
        // Home-row pairs always; others shuffled, up to the limit.
        let limit = 3 * target.fingers.count + 1
        let home = Array(pairs.prefix(pairs.count / 3))
        let chosen = home + pairs.dropFirst(home.count).shuffled(using: &rng).prefix(max(0, limit - home.count))
        var blocks = chosen.map(alternation)

        if complexity >= 1 {
            for pair in chosen.shuffled(using: &rng).prefix(2) {
                let a = pair.first!, b = pair.last!
                blocks.append([String([a, b, a]), String([b, a, b]), String([a, b, a]), String([b, a, b])])
            }
        }
        if complexity >= 2 {
            var diagonals: [String] = []
            for finger in target.fingers {
                for neighbour in FingerKeys.neighbours(of: finger) {
                    for (row, other) in [(0, 1), (0, 2), (1, 0), (2, 0)] {
                        if let key = FingerKeys.key(for: finger, row: row), let next = FingerKeys.key(for: neighbour, row: other) {
                            diagonals.append(String([key, next]))
                        }
                    }
                }
            }
            blocks += diagonals.shuffled(using: &rng).prefix(2).map(alternation)
        }
        return blocks.shuffled(using: &rng)
    }

    // MARK: Level 3: movement

    /// Pairs among one finger's own keys: home–top, home–bottom, top–bottom.
    public static func movementPairs(_ target: FingerFocusTarget) -> [String] {
        target.fingers.flatMap { finger -> [String] in
            let keys = FingerKeys.keys(for: finger)
            var pairs = [String([keys[0], keys[1]]), String([keys[0], keys[2]]), String([keys[1], keys[2]])]
            // Index fingers also reach sideways to the inner column.
            if keys.count > 3 { pairs.append(String([keys[0], keys[3]])) }
            return pairs
        }
    }

    /// Basic: "aq qa aq qa". Complexity 1 adds full sweeps ("qaz zaq");
    /// 2 adds out-and-back reaches ("aqa aza").
    static func movementBlocks(_ target: FingerFocusTarget, complexity: Int,
                               using rng: inout SeededGenerator) -> [[String]] {
        var blocks = movementPairs(target).map(alternation)
        for finger in target.fingers {
            let keys = FingerKeys.keys(for: finger)
            let (home, top, bottom) = (keys[0], keys[1], keys[2])
            if complexity >= 1 {
                blocks.append([String([top, home, bottom]), String([bottom, home, top]),
                               String([top, home, bottom]), String([bottom, home, top])])
            }
            if complexity >= 2 {
                blocks.append([String([home, top, home]), String([home, bottom, home]),
                               String([home, top, home]), String([home, bottom, home])])
            }
        }
        return blocks.shuffled(using: &rng)
    }

    // MARK: Focus

    /// Adds extra blocks for keys and transitions the user has been missing.
    /// Higher focus levels get more blocks, within `maxFocusBlocks`.
    static func insertFocus(_ focus: [FocusItem], target: FingerFocusTarget, level: FingerFocusLevel,
                            into blocks: inout [[String]], using rng: inout SeededGenerator) -> [FocusItem] {
        let ordered = focus
            .filter { $0.level > 0 }
            .sorted { ($0.level, $1.item) > ($1.level, $0.item) }

        var budget = maxFocusBlocks
        var applied: [FocusItem] = []
        for item in ordered where budget > 0 {
            guard let block = focusBlock(item, target: target, level: level) else { continue }
            for _ in 0..<min(item.level, budget) {
                blocks.insert(block, at: Int.random(in: 0...blocks.count, using: &rng))
                budget -= 1
            }
            applied.append(item)
        }
        return applied
    }

    /// The extra block for one focus item, or `nil` if it does not belong in
    /// this level for this target.
    static func focusBlock(_ item: FocusItem, target: FingerFocusTarget, level: FingerFocusLevel) -> [String]? {
        let characters = Array(item.item)
        let targetKeys = Set(target.keys)
        guard (1...2).contains(characters.count), characters.allSatisfy(target.drillKeys.contains),
              characters.contains(where: targetKeys.contains) else { return nil }

        switch level {
        case .activation:
            guard characters.count == 1 else { return nil }
            return Array(repeating: run(characters[0], runLength), count: unitsPerBlock)

        case .coordination:
            if characters.count == 2 {
                return isCoordination(characters, target) ? alternation(String(characters)) : nil
            }
            let pair = coordinationPairs(target).first { $0.contains(characters[0]) }
            return pair.map(alternation)

        case .movement:
            let key = characters[0]
            guard let finger = target.fingers.first(where: { FingerKeys.keys(for: $0).contains(key) }) else { return nil }
            let own = FingerKeys.keys(for: finger)
            if characters.count == 2 {
                return own.contains(characters[1]) ? alternation(String(characters)) : nil
            }
            let home = own[0]
            if key == home { return alternation(String([home, own[1]])) }
            // Hard keys at a higher focus level get the out-and-back reach.
            return item.level >= 2
                ? Array(repeating: String([home, key, home]), count: unitsPerBlock)
                : alternation(String([home, key]))

        case .words:
            return nil
        }
    }

    private static func isCoordination(_ pair: [Character], _ target: FingerFocusTarget) -> Bool {
        let fingers = pair.compactMap(FingerMap.finger(for:))
        guard fingers.count == 2, fingers[0] != fingers[1] else { return false }
        return target.fingers.contains { finger in
            fingers.contains(finger) && fingers.contains { FingerKeys.neighbours(of: finger).contains($0) }
        }
    }

    // MARK: Level 4: words

    struct WordDrill {
        var text: String
        var focus: [FocusItem]
    }

    /// The share of a word's letters that sit on `targets`.
    public static func density(of word: String, targets: Set<Character>) -> Double {
        guard !word.isEmpty else { return 0 }
        return Double(word.filter { targets.contains($0) }.count) / Double(word.count)
    }

    /// Real words that contain at least one target letter, richest in
    /// target letters first. At least `minimumWordPool` words when the list
    /// has that many.
    public static func wordPool(for target: FingerFocusTarget, from list: [String] = TrainingWords.all) -> [String] {
        let targets = Set(target.keys.filter(\.isLetter))
        let usable = list.filter { word in
            word.count >= 2 && word.count <= maximumWordLength && word.contains(where: targets.contains)
        }
        let ranked = usable.enumerated()
            .sorted { (density(of: $1.element, targets: targets), $0.offset) < (density(of: $0.element, targets: targets), $1.offset) }
            .map(\.element)
        // Words where at least a third of the letters are targets, or the top of the ranking.
        let rich = ranked.filter { density(of: $0, targets: targets) >= 1.0 / 3.0 }
        return rich.count >= minimumWordPool ? rich : Array(ranked.prefix(minimumWordPool))
    }

    static func words(for target: FingerFocusTarget, focus: [FocusItem],
                      from list: [String] = TrainingWords.all, using rng: inout SeededGenerator) -> WordDrill {
        let pool = wordPool(for: target, from: list)
        guard !pool.isEmpty else { return WordDrill(text: "", focus: []) }
        let targets = Set(target.keys.filter(\.isLetter))
        let active = focus.filter { item in item.level > 0 && item.item.allSatisfy(\.isLetter) }

        let weights = pool.map { word in
            Int((density(of: word, targets: targets) * 10).rounded()) + 1
                + active.reduce(0) { total, item in total + (word.contains(item.item) ? 3 * item.level : 0) }
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
            if pool.count < 2 || pool[index] != chosen.last { chosen.append(pool[index]) }
        }

        // The right ring finger owns "." and the right pinky ";": put them to work.
        let marks = target.fingers.compactMap { finger -> Character? in
            switch finger {
            case .rightRing: "."
            case .rightPinky: ";"
            default: nil
            }
        }
        if !marks.isEmpty {
            var markIndex = 0
            for index in chosen.indices where (index + 1).isMultiple(of: punctuationEvery) {
                chosen[index].append(marks[markIndex % marks.count])
                markIndex += 1
            }
        }

        let applied = active.filter { item in chosen.contains { $0.contains(item.item) } }
        return WordDrill(text: chosen.joined(separator: " "), focus: applied)
    }

    // MARK: Helpers

    /// ["as", "sa", "as", "sa"]
    private static func alternation(_ pair: String) -> [String] {
        let reversed = String(pair.reversed())
        return [pair, reversed, pair, reversed]
    }

    private static func run(_ character: Character, _ count: Int) -> String {
        String(repeating: String(character), count: count)
    }
}
