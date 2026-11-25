import Foundation

/// Daily Flow: one short guided session a day. A warm-up, the keys you
/// currently miss most inside real words, then real sentences.
///
/// The rules, and why:
/// - **Time is active practice.** Each gap between key presses counts, up to
///   `DailyFlowPlan.maximumGap`, so walking away does not fill the session.
/// - **A session ends at the end of a passage**, once the planned time is
///   reached, so it never cuts you off mid-sentence. It can run slightly long.
/// - **A hint means Keyflow showed the next key after a pause.** Keyflow
///   cannot see your eyes, so it never claims you did or did not look down.
/// - **Every finished passage is saved at once**, so ending early or quitting
///   keeps what was done.
public enum DailyFlowSegment: String, Codable, Sendable, CaseIterable, Identifiable {
    case warmUp, weakKeys, realText

    public var id: Self { self }

    public var title: String {
        switch self {
        case .warmUp: "Warm-Up"
        case .weakKeys: "Focus Words"
        case .realText: "Real Sentences"
        }
    }

    public var detail: String {
        switch self {
        case .warmUp: "Home-row words to settle your hands."
        case .weakKeys: "Real words with the keys you miss most."
        case .realText: "Plain sentences, in lower case and without punctuation."
        }
    }

    /// Tenths of the session.
    var share: Int {
        switch self {
        case .warmUp: 2
        case .weakKeys: 5
        case .realText: 3
        }
    }
}

public struct DailyFlowPlan: Sendable, Equatable {
    public static let lengths = [5, 10, 15]
    public static let defaultMinutes = 10
    /// The most one gap between key presses adds to active time.
    public static let maximumGap: TimeInterval = 5

    public let minutes: Int

    /// Lengths other than 5, 10 and 15 become the default.
    public init(minutes: Int = Self.defaultMinutes) {
        self.minutes = Self.lengths.contains(minutes) ? minutes : Self.defaultMinutes
    }

    public var totalSeconds: TimeInterval { TimeInterval(minutes * 60) }

    public func seconds(for segment: DailyFlowSegment) -> TimeInterval {
        TimeInterval(minutes * 6 * segment.share)
    }

    /// The segment at this much active time, or nil once the plan is done.
    public func segment(atActive seconds: TimeInterval) -> DailyFlowSegment? {
        var end: TimeInterval = 0
        for segment in DailyFlowSegment.allCases {
            end += self.seconds(for: segment)
            if seconds < end { return segment }
        }
        return nil
    }

    /// 0...1 through the session.
    public func fraction(atActive seconds: TimeInterval) -> Double {
        min(1, max(0, seconds / totalSeconds))
    }
}

/// When to offer a hint: after a pause clearly longer than your own rhythm,
/// so a slower typist is not interrupted on every key.
public struct DailyFlowPace: Sendable, Equatable {
    public static let minimumDelay: TimeInterval = 1.5
    public static let maximumDelay: TimeInterval = 4
    public static let startingDelay: TimeInterval = 2
    static let window = 24
    static let minimumSamples = 5

    private var gaps: [TimeInterval] = []

    public init() {}

    /// A gap between two key presses. Long pauses say nothing about rhythm.
    public mutating func record(gap: TimeInterval) {
        guard gap > 0, gap <= Self.maximumDelay else { return }
        gaps.append(gap)
        if gaps.count > Self.window { gaps.removeFirst(gaps.count - Self.window) }
    }

    /// Twice your recent median gap, kept within 1.5...4 seconds.
    public var delay: TimeInterval {
        guard gaps.count >= Self.minimumSamples else { return Self.startingDelay }
        let sorted = gaps.sorted()
        let middle = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        return min(Self.maximumDelay, max(Self.minimumDelay, median * 2))
    }
}

/// Picks the keys to focus on, from recent per-key counts. The rule is plain:
/// letters seen at least 8 times, missed at least twice and at least 5% of
/// the time, worst rate first.
public enum DailyFlowFocus {
    public static let limit = 4
    public static let minimumAttempts = 8
    public static let minimumErrors = 2
    public static let minimumRate = 0.05
    /// Used until there is enough data: the most common letters in English.
    public static let starterKeys: [Character] = ["e", "t", "a", "o"]

    public static func keys(from counts: [String: ErrorCount]) -> [Character] {
        var letters: [Character: ErrorCount] = [:]
        for (key, count) in counts {
            guard key.count == 1, let letter = key.lowercased().first, ("a"..."z").contains(letter) else { continue }
            letters[letter, default: ErrorCount()] = letters[letter, default: ErrorCount()] + count
        }
        return letters
            .filter { $0.value.attempts >= minimumAttempts && $0.value.errors >= minimumErrors && $0.value.rate >= minimumRate }
            .sorted { lhs, rhs in
                if lhs.value.rate != rhs.value.rate { return lhs.value.rate > rhs.value.rate }
                if lhs.value.errors != rhs.value.errors { return lhs.value.errors > rhs.value.errors }
                return lhs.key < rhs.key
            }
            .prefix(limit)
            .map(\.key)
    }
}

/// Generates the passages. Deterministic for a given seed.
public struct DailyFlowGenerator: Sendable {
    private var random: SeededGenerator
    private var lastSentence: String?

    static let homeRow = Set("asdfghjkl")
    static let warmUpWords = TrainingWords.all.filter { $0.count >= 2 && $0.allSatisfy(homeRow.contains) }
    static let commonWords = WordList.common.filter { word in
        word.count >= 2 && word.count <= 7 && word.allSatisfy { ("a"..."z").contains($0) }
    }
    static let focusPool = TrainingWords.all.filter { $0.count >= 2 && $0.count <= 7 }

    /// Corpus sentences that read naturally without capitals or punctuation.
    static let sentences: [String] = Corpus.sentences.compactMap { sentence in
        guard !sentence.contains(where: { $0.isNumber || $0 == "'" || $0 == "’" || $0 == "-" }) else { return nil }
        let words = sentence.lowercased().split(separator: " ").map { $0.filter(\.isLetter) }.filter { !$0.isEmpty }
        let text = words.joined(separator: " ")
        return text.allSatisfy({ $0 == " " || ("a"..."z").contains($0) }) ? text : nil
    }

    public init(seed: UInt64) { random = SeededGenerator(seed: seed) }

    public mutating func passage(for segment: DailyFlowSegment, focus: [Character]) -> String {
        switch segment {
        case .warmUp: words(from: Self.warmUpWords, length: 36)
        case .weakKeys: focusWords(focus.isEmpty ? DailyFlowFocus.starterKeys : focus)
        case .realText: sentence()
        }
    }

    private mutating func words(from pool: [String], length: Int) -> String {
        var picked: [String] = []
        while picked.joined(separator: " ").count < length {
            guard let word = pool.randomElement(using: &random) else { break }
            if word != picked.last { picked.append(word) }
        }
        return picked.joined(separator: " ")
    }

    /// Three words in four use a focus key, taken in turn; the rest are
    /// common words, so the passage still reads like ordinary typing.
    private mutating func focusWords(_ focus: [Character]) -> String {
        var picked: [String] = []
        var turn = 0
        while picked.joined(separator: " ").count < 42 {
            let useFocus = picked.count % 4 != 3
            var pool = Self.commonWords
            if useFocus {
                let key = focus[turn % focus.count]
                turn += 1
                let common = Self.commonWords.filter { $0.contains(key) }
                let matches = common.count >= 6 ? common : Self.focusPool.filter { $0.contains(key) }
                if !matches.isEmpty { pool = matches }
            }
            guard let word = pool.randomElement(using: &random) else { break }
            if word != picked.last || pool.count == 1 { picked.append(word) }
        }
        return picked.joined(separator: " ")
    }

    /// A sentence, cut at a word boundary if it is long.
    private mutating func sentence() -> String {
        var choice = Self.sentences.randomElement(using: &random) ?? "the quiet road led home"
        if choice == lastSentence, Self.sentences.count > 1 {
            choice = Self.sentences.first { $0 != lastSentence } ?? choice
        }
        lastSentence = choice
        var kept: [Substring] = []
        for word in choice.split(separator: " ") {
            if (kept.map(\.count).reduce(0, +) + kept.count + word.count) > 64 { break }
            kept.append(word)
        }
        return kept.joined(separator: " ")
    }
}

/// One finished passage, as saved.
public struct DailyFlowRound: Codable, Sendable, Equatable {
    public let sessionID: UUID
    public let segment: DailyFlowSegment
    public let plannedMinutes: Int
    /// Active practice in this passage, in seconds.
    public let activeSeconds: TimeInterval
    /// Positions where the next key was shown after a pause.
    public let hints: Int
    public let result: RoundResult

    public init(sessionID: UUID, segment: DailyFlowSegment, plannedMinutes: Int, activeSeconds: TimeInterval,
                hints: Int, result: RoundResult) {
        self.sessionID = sessionID
        self.segment = segment
        self.plannedMinutes = plannedMinutes
        self.activeSeconds = activeSeconds
        self.hints = hints
        self.result = result
    }
}

public struct DailyFlowEvent: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    public let round: DailyFlowRound

    public init(id: UUID = UUID(), date: Date = .now, round: DailyFlowRound) {
        self.id = id
        self.date = date
        self.round = round
    }
}

/// Totals of passages. Counts and plain ratios only.
public struct DailyFlowTotals: Sendable, Equatable {
    public var passages = 0
    public var activeSeconds: TimeInterval = 0
    public var keystrokes = 0
    public var correctKeystrokes = 0
    public var hints = 0

    public init() {}

    public init(rounds: some Sequence<DailyFlowRound>) {
        for round in rounds {
            passages += 1
            activeSeconds += round.activeSeconds
            keystrokes += round.result.keystrokes
            correctKeystrokes += round.result.correctKeystrokes
            hints += round.hints
        }
    }

    /// Correct keystrokes ÷ all keystrokes; nil with none.
    public var accuracy: Double? { keystrokes == 0 ? nil : Double(correctKeystrokes) / Double(keystrokes) }
    /// Share of keystrokes made without a hint being shown; nil with none.
    public var withoutHints: Double? {
        keystrokes == 0 ? nil : max(0, 1 - Double(hints) / Double(keystrokes))
    }
}

public struct DailyFlowHistory: Sendable {
    public struct Session: Sendable, Equatable, Identifiable {
        public let id: UUID
        /// When its last passage was finished.
        public let date: Date
        public let plannedMinutes: Int
        public let totals: DailyFlowTotals
    }

    public struct Week: Sendable, Equatable {
        public let days: Int
        public let totals: DailyFlowTotals
    }

    /// Oldest first.
    public let sessions: [Session]
    private let events: [DailyFlowEvent]

    public init(events: [DailyFlowEvent]) {
        self.events = events
        sessions = Dictionary(grouping: events, by: \.round.sessionID)
            .compactMap { id, rounds in
                guard let last = rounds.max(by: { $0.date < $1.date }) else { return nil }
                return Session(id: id, date: last.date, plannedMinutes: last.round.plannedMinutes,
                               totals: DailyFlowTotals(rounds: rounds.map(\.round)))
            }
            .sorted { ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) }
    }

    /// The session before this one.
    public func session(before id: UUID) -> Session? {
        guard let index = sessions.firstIndex(where: { $0.id == id }), index > 0 else { return nil }
        return sessions[index - 1]
    }

    public func hasPractised(on day: Date, calendar: Calendar = .current) -> Bool {
        events.contains { calendar.isDate($0.date, inSameDayAs: day) }
    }

    /// The calendar week containing `date`.
    public func week(of date: Date, calendar: Calendar = .current) -> Week {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return Week(days: 0, totals: DailyFlowTotals())
        }
        let inWeek = events.filter { interval.contains($0.date) }
        let days = Set(inWeek.map { calendar.startOfDay(for: $0.date) }).count
        return Week(days: days, totals: DailyFlowTotals(rounds: inWeek.map(\.round)))
    }

    public func previousWeek(from date: Date, calendar: Calendar = .current) -> Week {
        guard let earlier = calendar.date(byAdding: .weekOfYear, value: -1, to: date) else {
            return Week(days: 0, totals: DailyFlowTotals())
        }
        return week(of: earlier, calendar: calendar)
    }
}
