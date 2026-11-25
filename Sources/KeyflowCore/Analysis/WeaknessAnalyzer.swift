import Foundation

/// Something the user does measurably worse than their own typical typing.
public struct Weakness: Sendable, Equatable, Identifiable {
    public enum Category: String, Sendable, CaseIterable {
        case key, combination, word, transition
    }

    public enum Dimension: String, Sendable, CaseIterable {
        case accuracy, speed
    }

    public let category: Category
    public let dimension: Dimension
    /// The key ("e"), pair ("th") or word ("their").
    public let item: String
    /// Attempts (accuracy) or latency samples (speed) behind the finding.
    public let samples: Int
    /// Wrong attempts. Zero for speed findings.
    public let errors: Int
    /// Error rate 0...1 (accuracy) or mean latency in seconds (speed).
    public let value: Double
    /// The same measure across the user's typing as a whole.
    public let baseline: Double

    public var id: String { "\(dimension.rawValue).\(category.rawValue).\(item)" }
    /// How many times worse than baseline. Always above 1.
    public var severity: Double { baseline > 0 ? value / baseline : 1 }
}

public struct WeaknessReport: Sendable, Equatable {
    /// Confirmed accuracy weaknesses, most severe first.
    public var accuracy: [Weakness]
    /// Confirmed speed weaknesses, most severe first.
    public var speed: [Weakness]
    public var sessions: Int
    public var keystrokes: Int
    /// Keystrokes required before anything is reported.
    public var keystrokesNeeded: Int

    /// False until there is enough typing to judge anything at all. When
    /// false, both lists are empty and the UI must say "Not enough data yet."
    public var hasEnoughData: Bool { keystrokes >= keystrokesNeeded }
    public var all: [Weakness] { accuracy + speed }
}

/// Finds weaknesses offline, from the user's own history.
///
/// Nothing is reported from a single mistake. An item is confirmed only when
/// **all** of these hold:
///
/// 1. *Enough evidence overall* — the profile holds at least `minimumKeystrokes`.
/// 2. *Enough evidence for the item* — a minimum number of attempts (or latency
///    samples), and for accuracy a minimum number of actual errors.
/// 3. *Meaningfully worse* — at least `minimumRatio` × the user's own baseline.
/// 4. *Unlikely to be chance* — for accuracy, the lower bound of the Wilson
///    score interval of the item's error rate is above the baseline rate; for
///    speed, the mean latency exceeds the baseline by more than `z` standard
///    errors.
///
/// Baselines are the user's own averages over the same sessions, never an
/// external norm. Accuracy and speed are judged and reported separately.
///
/// One cause is reported once:
/// - a letter combination must be worse than its second key is elsewhere;
/// - a key that is only bad inside confirmed combinations is dropped;
/// - a word containing a confirmed weak key or combination is not listed.
public enum WeaknessAnalyzer {
    public struct Thresholds: Sendable, Equatable {
        public var minimumKeystrokes = 600

        public var keyAttempts = 30
        public var keyErrors = 3
        public var pairAttempts = 12
        public var pairErrors = 3
        public var wordAttempts = 6
        public var wordMistakes = 3

        public var keyLatencySamples = 20
        public var pairLatencySamples = 8

        public var minimumRatio = 1.25
        /// One-sided 99.5% confidence. Hundreds of keys, pairs and words are
        /// tested at once, so each one has to clear a high bar.
        public var z = 2.576

        public init() {}
    }

    public static func analyze(_ profile: TypingProfile, thresholds: Thresholds = Thresholds()) -> WeaknessReport {
        var report = WeaknessReport(accuracy: [], speed: [], sessions: profile.sessions,
                                    keystrokes: profile.keystrokes, keystrokesNeeded: thresholds.minimumKeystrokes)
        guard report.hasEnoughData else { return report }
        let t = thresholds

        // Keys
        for key in profile.keys.values {
            let name = String(key.character)
            if let baseline = profile.keyErrorRate,
               isUnreliable(errors: key.errors, attempts: key.attempts, baseline: baseline,
                            minimumAttempts: t.keyAttempts, minimumErrors: t.keyErrors, thresholds: t) {
                report.accuracy.append(Weakness(category: .key, dimension: .accuracy, item: name, samples: key.attempts,
                                                errors: key.errors, value: key.errorRate, baseline: baseline))
            }
            if let baseline = profile.meanKeyLatency, let mean = key.meanLatency,
               isSlow(mean: mean, total: key.latencyTotal, squares: key.latencySquares, samples: key.latencySamples,
                      baseline: baseline, minimumSamples: t.keyLatencySamples, thresholds: t) {
                report.speed.append(Weakness(category: .key, dimension: .speed, item: name, samples: key.latencySamples,
                                             errors: 0, value: mean, baseline: baseline))
            }
        }

        let inaccurateKeys = Set(report.accuracy.map { Character($0.item) })
        let slowKeys = Set(report.speed.map { Character($0.item) })

        // Letter combinations. A pair counts only if it is worse than its own
        // second key is elsewhere; otherwise the key is the real finding.
        for pair in profile.bigrams.values {
            if let global = profile.bigramErrorRate,
               let baseline = errorBaseline(for: pair, in: profile, global: global, weakKeys: inaccurateKeys, thresholds: t) {
                if isUnreliable(errors: pair.errors, attempts: pair.attempts, baseline: baseline,
                                minimumAttempts: t.pairAttempts, minimumErrors: t.pairErrors, thresholds: t) {
                    report.accuracy.append(Weakness(category: .combination, dimension: .accuracy, item: pair.bigram,
                                                    samples: pair.attempts, errors: pair.errors,
                                                    value: pair.errorRate, baseline: baseline))
                }
            }
            if let global = profile.meanBigramLatency,
               let baseline = latencyBaseline(for: pair, in: profile, global: global, weakKeys: slowKeys, thresholds: t) {
                if isSlow(mean: pair.meanLatency, total: pair.total, squares: pair.squares, samples: pair.samples,
                          baseline: baseline, minimumSamples: t.pairLatencySamples, thresholds: t) {
                    report.speed.append(Weakness(category: .combination, dimension: .speed, item: pair.bigram,
                                                 samples: pair.samples, errors: 0,
                                                 value: pair.meanLatency, baseline: baseline))
                }
            }
        }

        // Transitions involving spaces, digits and symbols: speed only.
        for pair in profile.transitions.values {
            if let global = profile.meanTransitionLatency,
               let baseline = latencyBaseline(for: pair, in: profile, global: global, weakKeys: slowKeys, thresholds: t) {
                if isSlow(mean: pair.meanLatency, total: pair.total, squares: pair.squares, samples: pair.samples,
                          baseline: baseline, minimumSamples: t.pairLatencySamples, thresholds: t) {
                    report.speed.append(Weakness(category: .transition, dimension: .speed, item: pair.bigram,
                                                 samples: pair.samples, errors: 0,
                                                 value: pair.meanLatency, baseline: baseline))
                }
            }
        }

        // A key whose trouble comes entirely from confirmed pairs is not a
        // finding of its own: drop it if it passes no test without them.
        let confirmedAccuracy = report.accuracy
        report.accuracy.removeAll { weakness in
            guard weakness.category == .key, let key = profile.keys[Character(weakness.item)] else { return false }
            let pairs = confirmedAccuracy.filter { $0.category == .combination && $0.item.hasSuffix(weakness.item) }
            guard !pairs.isEmpty else { return false }
            return !isUnreliable(errors: key.errors - pairs.reduce(0) { $0 + $1.errors },
                                 attempts: key.attempts - pairs.reduce(0) { $0 + $1.samples },
                                 baseline: weakness.baseline, minimumAttempts: t.keyAttempts,
                                 minimumErrors: t.keyErrors, thresholds: t)
        }
        let confirmedSpeed = report.speed
        report.speed.removeAll { weakness in
            guard weakness.category == .key, let key = profile.keys[Character(weakness.item)] else { return false }
            let pairs = confirmedSpeed
                .filter { $0.category != .key && $0.item.hasSuffix(weakness.item) }
                .compactMap { $0.category == .combination ? profile.bigrams[$0.item] : profile.transitions[$0.item] }
            guard !pairs.isEmpty else { return false }
            let samples = key.latencySamples - pairs.reduce(0) { $0 + $1.samples }
            let total = key.latencyTotal - pairs.reduce(0) { $0 + $1.total }
            let squares = key.latencySquares - pairs.reduce(0) { $0 + $1.squares }
            return !isSlow(mean: samples > 0 ? total / Double(samples) : 0, total: total, squares: squares,
                           samples: samples, baseline: weakness.baseline,
                           minimumSamples: t.keyLatencySamples, thresholds: t)
        }

        // Words: accuracy only. A word that contains an already-confirmed weak
        // key or combination is explained by it and not listed again.
        let weakKeys = Set(report.accuracy.filter { $0.category == .key }.map(\.item))
        let weakPairs = report.accuracy.filter { $0.category == .combination }.map(\.item)
        for word in profile.words.values {
            guard let baseline = profile.wordMistakeRate,
                  isUnreliable(errors: word.mistakes, attempts: word.attempts, baseline: baseline,
                               minimumAttempts: t.wordAttempts, minimumErrors: t.wordMistakes, thresholds: t),
                  !word.word.contains(where: { weakKeys.contains(String($0)) }),
                  !weakPairs.contains(where: { word.word.contains($0) })
            else { continue }
            report.accuracy.append(Weakness(category: .word, dimension: .accuracy, item: word.word,
                                            samples: word.attempts, errors: word.mistakes,
                                            value: Double(word.mistakes) / Double(word.attempts), baseline: baseline))
        }

        report.accuracy.sort(by: mostSevereFirst)
        report.speed.sort(by: mostSevereFirst)
        return report
    }

    /// Lower bound of the Wilson score interval for `errors` out of `attempts`.
    public static func wilsonLowerBound(errors: Int, attempts: Int, z: Double) -> Double {
        guard attempts > 0 else { return 0 }
        let n = Double(attempts)
        let p = Double(errors) / n
        let z2 = z * z
        let centre = p + z2 / (2 * n)
        let margin = z * (p * (1 - p) / n + z2 / (4 * n * n)).squareRoot()
        return max(0, (centre - margin) / (1 + z2 / n))
    }

    // MARK: Private

    /// What to expect of a pair's second character: the overall pair error
    /// rate, or that key's error rate everywhere else if that is higher.
    /// `nil` means the pair cannot be told apart from its key: the key is
    /// already confirmed weak and is hardly typed outside this pair.
    private static func errorBaseline(for pair: BigramStat, in profile: TypingProfile, global: Double,
                                      weakKeys: Set<Character>, thresholds: Thresholds) -> Double? {
        guard let second = pair.bigram.last, let key = profile.keys[second] else { return global }
        let attempts = key.attempts - pair.attempts
        guard attempts >= thresholds.keyAttempts else { return weakKeys.contains(second) ? nil : global }
        return max(global, Double(max(0, key.errors - pair.errors)) / Double(attempts))
    }

    /// The overall pair latency, or the second key's latency everywhere else
    /// if that is slower. `nil` as for `errorBaseline`.
    private static func latencyBaseline(for pair: BigramStat, in profile: TypingProfile, global: TimeInterval,
                                        weakKeys: Set<Character>, thresholds: Thresholds) -> TimeInterval? {
        guard let second = pair.bigram.last, let key = profile.keys[second] else { return global }
        let samples = key.latencySamples - pair.samples
        guard samples >= thresholds.keyLatencySamples else { return weakKeys.contains(second) ? nil : global }
        return max(global, max(0, key.latencyTotal - pair.total) / Double(samples))
    }

    private static func isUnreliable(errors: Int, attempts: Int, baseline: Double,
                                     minimumAttempts: Int, minimumErrors: Int, thresholds: Thresholds) -> Bool {
        guard attempts >= minimumAttempts, errors >= minimumErrors, baseline > 0 else { return false }
        let rate = Double(errors) / Double(attempts)
        return rate >= baseline * thresholds.minimumRatio
            && wilsonLowerBound(errors: errors, attempts: attempts, z: thresholds.z) > baseline
    }

    private static func isSlow(mean: TimeInterval, total: TimeInterval, squares: TimeInterval, samples: Int,
                               baseline: TimeInterval, minimumSamples: Int, thresholds: Thresholds) -> Bool {
        guard samples >= minimumSamples, samples > 1, baseline > 0, mean >= baseline * thresholds.minimumRatio else {
            return false
        }
        let n = Double(samples)
        let variance = max(0, (squares - total * total / n) / (n - 1))
        let standardError = (variance / n).squareRoot()
        return mean - baseline > thresholds.z * standardError
    }

    private static func mostSevereFirst(_ a: Weakness, _ b: Weakness) -> Bool {
        (a.severity, b.id) > (b.severity, a.id)
    }
}
