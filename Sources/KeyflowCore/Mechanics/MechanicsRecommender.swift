import Foundation

/// A suggestion for what to practise next, with the evidence behind it.
public struct MechanicsRecommendation: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case slowShift, capsLockState, slowReturnToLower, slowIntoCapitals, slowNumbers, missedCharacters, inconsistentStrategy
    }

    public let kind: Kind
    /// Where to practise. For the Capitalisation Lab the area is what
    /// matters: the Lab chooses the counterbalanced order itself.
    public let area: MechanicsArea
    public let drill: MechanicsDrill
    public let title: String
    /// What was observed, in plain words with the numbers behind it.
    public let evidence: String
    /// Rounds the evidence came from.
    public let rounds: Int

    public init(kind: Kind, area: MechanicsArea, drill: MechanicsDrill, title: String, evidence: String, rounds: Int) {
        self.kind = kind
        self.area = area
        self.drill = drill
        self.title = title
        self.evidence = evidence
        self.rounds = rounds
    }

    public var id: Kind { kind }
}

/// Turns recent Typing Mechanics results into a short list of targeted
/// suggestions. Deliberately simple, so every suggestion can be explained.
///
/// Rules, over the most recent `window` rounds. Each needs evidence from at
/// least `minimumRounds` rounds, so one bad round never triggers anything.
///
/// - **Slow Shift → Shift Control.** The Shift overhead estimate's 95% range
///   lies entirely above `slowShiftOverheadMs`, or Shift is held a median
///   of `slowShiftLeadMs` or more before the letter over at least
///   `minimumSamples` capitals.
/// - **Caps Lock state errors → Caps Lock Control.** At least
///   `capsLockStateErrors` capitals typed with Caps Lock left on, or Caps
///   Lock drill technique accuracy below `capsLockTechniqueAccuracy` over at
///   least `minimumSamples` checked capitals.
/// - **Slow return to lower case → Case Transitions (Upper to Lower)** and
///   **slow start of capitals → Case Transitions (Lower to Upper).** Each
///   transition sample is divided by the same round's lower-case baseline of
///   the same shape; the median of those ratios over at least
///   `minimumSamples` samples is `slowRatio` or more.
/// - **Slow number input → Numbers & Symbols.** The same ratio test, applied
///   separately to key changes into numbers, out of them and within them.
/// - **Missed characters → Numbers & Symbols.** One digit or symbol is among
///   the characters to watch in `minimumRounds` or more rounds.
/// - **Inconsistent capitalisation → Capitalisation Lab.** Where the method
///   was free, capitals of one length group were typed with both Shift and
///   Caps Lock, the less used method at least `inconsistentShare` of at
///   least `minimumSamples` runs.
///
/// At most `limit` suggestions, strongest evidence first.
public enum MechanicsRecommender {
    public static let window = 20
    public static let minimumRounds = 2
    public static let minimumSamples = 8
    public static let slowShiftOverheadMs = 60.0
    public static let slowShiftLeadMs = 250.0
    public static let capsLockStateErrors = 3
    public static let capsLockTechniqueAccuracy = 0.8
    public static let slowRatio = MechanicsFeedback.slowRatio
    public static let inconsistentShare = 0.3
    public static let limit = 3

    /// What to put first when several suggestions apply (Settings ▸ Training).
    public enum Priority: Sendable { case balanced, accuracy, speed }

    /// Kinds about getting characters or technique right, and kinds about time.
    static let accuracyKinds: Set<MechanicsRecommendation.Kind> = [.capsLockState, .missedCharacters]
    static let speedKinds: Set<MechanicsRecommendation.Kind> = [.slowShift, .slowReturnToLower, .slowIntoCapitals, .slowNumbers]
    // A priority puts its kinds first, each group still ordered by strength of
    // evidence. It never creates a suggestion the evidence does not support.

    public static func recommendations(from events: [MechanicsEvent], priority: Priority = .balanced) -> [MechanicsRecommendation] {
        let recent = Array(events.sorted { $0.date < $1.date }.suffix(window))
        var found: [(strength: Double, recommendation: MechanicsRecommendation)] = []
        func add(_ strength: Double, _ r: MechanicsRecommendation) { found.append((strength, r)) }

        // Slow Shift
        let results = recent.map(\.result)
        let shift = CapitalisationOverhead.estimates(from: results)[.shift]
        let shiftRounds = recent.filter { !($0.result.segments ?? []).filter { $0.method == .shift && $0.overheadMs != nil }.isEmpty }.count
        if let shift, let range = shift.range, range.lowerBound > slowShiftOverheadMs, shiftRounds >= minimumRounds {
            add(range.lowerBound / slowShiftOverheadMs, MechanicsRecommendation(
                kind: .slowShift, area: .shiftControl, drill: .alternatingCase, title: "Make Shift capitals smoother",
                evidence: "Capitals with Shift take about \(OverheadMath.rounded(shift.overheadMs ?? 0)) ms longer than ordinary key changes (\(shift.runs) runs over \(shiftRounds) rounds).",
                rounds: shiftRounds))
        } else {
            let leads = recent.filter { $0.result.shiftLead.count > 0 }
            let values = leads.flatMap(\.result.shiftLead.values)
            if leads.count >= minimumRounds, values.count >= minimumSamples, let median = TimingSamples(values).median,
               median >= slowShiftLeadMs {
                add(median / slowShiftLeadMs, MechanicsRecommendation(
                    kind: .slowShift, area: .shiftControl, drill: .singleCapitals, title: "Press Shift closer to the letter",
                    evidence: "Shift is held a median of \(OverheadMath.rounded(median)) ms before the letter (\(values.count) capitals over \(leads.count) rounds).",
                    rounds: leads.count))
            }
        }

        // Caps Lock state errors
        let leftOn = recent.filter { $0.result.capsLockLeftOn > 0 }
        let leftOnCount = leftOn.reduce(0) { $0 + $1.result.capsLockLeftOn }
        let capsDrills = recent.filter { $0.drill.wantedTechnique == .capsLock && $0.result.techniqueChecked > 0 }
        let checked = capsDrills.reduce(0) { $0 + $1.result.techniqueChecked }
        let correct = capsDrills.reduce(0) { $0 + $1.result.techniqueCorrect }
        if leftOnCount >= capsLockStateErrors, leftOn.count >= minimumRounds {
            add(Double(leftOnCount) / Double(capsLockStateErrors), MechanicsRecommendation(
                kind: .capsLockState, area: .capsLockControl, drill: .capsMixedCase, title: "Switch Caps Lock off on time",
                evidence: "\(leftOnCount) lower-case letters came out in capitals with Caps Lock still on, in \(leftOn.count) rounds.",
                rounds: leftOn.count))
        } else if capsDrills.count >= minimumRounds, checked >= minimumSamples,
                  Double(correct) / Double(checked) < capsLockTechniqueAccuracy {
            let accuracy = Double(correct) / Double(checked)
            add(capsLockTechniqueAccuracy / max(accuracy, 0.01), MechanicsRecommendation(
                kind: .capsLockState, area: .capsLockControl, drill: .uppercaseBlocks, title: "Use Caps Lock for words in capitals",
                evidence: "In Caps Lock drills, \(Int((accuracy * 100).rounded()))% of capitals used Caps Lock (\(checked) checked over \(capsDrills.count) rounds).",
                rounds: capsDrills.count))
        }

        // Slow transitions
        func ratios(_ kinds: [TransitionClass]) -> (values: [Double], rounds: Int) {
            var values: [Double] = []
            var rounds = 0
            for result in results {
                var any = false
                for kind in kinds {
                    guard let base = kind.baseline else { continue }
                    let baseline = result.samples(base)
                    guard baseline.count >= MechanicsFeedback.minimumSamples, let median = baseline.median, median > 0 else { continue }
                    let own = result.samples(kind).values
                    if !own.isEmpty { any = true }
                    values += own.map { $0 / median }
                }
                if any { rounds += 1 }
            }
            return (values, rounds)
        }
        func slow(_ kinds: [TransitionClass]) -> (ratio: Double, samples: Int, rounds: Int)? {
            let r = ratios(kinds)
            guard r.rounds >= minimumRounds, r.values.count >= minimumSamples, let median = TimingSamples(r.values).median,
                  median >= slowRatio else { return nil }
            return (median, r.values.count, r.rounds)
        }
        func percent(_ ratio: Double) -> Int { Int(((ratio - 1) * 100 / 5).rounded()) * 5 }

        if let s = slow([.outOfUpperDirect, .outOfUpperAcrossSpace]) {
            add(s.ratio, MechanicsRecommendation(
                kind: .slowReturnToLower, area: .caseTransitions, drill: .upperToLower, title: "Return to lower case faster",
                evidence: "Going from capitals back to lower case takes about \(percent(s.ratio))% longer than ordinary key changes (\(s.samples) changes over \(s.rounds) rounds).",
                rounds: s.rounds))
        }
        // A slow start of capitals is usually the same Shift problem: one suggestion is enough.
        let shiftFound = found.contains { $0.recommendation.kind == .slowShift }
        if !shiftFound, let s = slow([.intoUpperDirect, .intoUpperAcrossSpace]) {
            add(s.ratio * 0.95, MechanicsRecommendation(
                kind: .slowIntoCapitals, area: .caseTransitions, drill: .lowerToUpper, title: "Start capitals without a pause",
                evidence: "Going from lower case into capitals takes about \(percent(s.ratio))% longer than ordinary key changes (\(s.samples) changes over \(s.rounds) rounds).",
                rounds: s.rounds))
        }
        // Each part of number input on its own, so a fine part cannot hide a slow one.
        let numberParts: [(kinds: [TransitionClass], what: String, drill: MechanicsDrill)] = [
            ([.intoDigitDirect, .intoDigitAcrossSpace], "Reaching from letters to numbers", .mixedText),
            ([.outOfDigitDirect, .outOfDigitAcrossSpace], "Coming back from numbers to letters", .mixedText),
            ([.withinDigits], "Typing digit after digit", .numberRow),
        ]
        let slowest = numberParts.compactMap { part in slow(part.kinds).map { (part, $0) } }.max { $0.1.ratio < $1.1.ratio }
        if let (part, s) = slowest {
            add(s.ratio, MechanicsRecommendation(
                kind: .slowNumbers, area: .numbersSymbols, drill: part.drill, title: "Speed up number input",
                evidence: "\(part.what) takes about \(percent(s.ratio))% longer than a key change between letters (\(s.samples) changes over \(s.rounds) rounds).",
                rounds: s.rounds))
        }

        // Characters missed again and again
        var flagged: [Character: Int] = [:]
        for result in results {
            for watch in MechanicsFeedback.charactersToWatch(in: result) where watch.reason == .errors {
                flagged[watch.character, default: 0] += 1
            }
        }
        let repeated = flagged.filter { $0.value >= minimumRounds }.sorted { ($0.value, String($1.key)) > ($1.value, String($0.key)) }
        if let first = repeated.first {
            let list = repeated.prefix(3).map { "\u{201C}\($0.key)\u{201D}" }.joined(separator: ", ")
            let symbol = CaseRequirement.of(first.key) == .shiftedSymbol
            add(1 + Double(first.value) / 10, MechanicsRecommendation(
                kind: .missedCharacters, area: .numbersSymbols, drill: symbol ? .shiftedSymbols : .numberRow,
                title: "Practise \(list)",
                evidence: "\(list) \(repeated.count == 1 ? "was" : "were") missed repeatedly in \(first.value) rounds.",
                rounds: first.value))
        }

        // Inconsistent capitalisation where the method was free
        let free = recent.filter { $0.drill.wantedTechnique == nil }
        var byGroup: [SegmentLength: (shift: Int, caps: Int, rounds: Set<UUID>)] = [:]
        for event in free {
            for segment in event.result.segments ?? [] where segment.clean {
                var entry = byGroup[segment.group] ?? (0, 0, [])
                switch segment.method {
                case .shift: entry.shift += 1
                case .capsLock: entry.caps += 1
                case .mixed, .unknown: continue
                }
                entry.rounds.insert(event.id)
                byGroup[segment.group] = entry
            }
        }
        let mixedGroups = byGroup.compactMap { group, entry -> (SegmentLength, Double, Int, Int)? in
            let total = entry.shift + entry.caps
            guard total >= minimumSamples, entry.rounds.count >= minimumRounds else { return nil }
            let share = Double(min(entry.shift, entry.caps)) / Double(total)
            return share >= inconsistentShare ? (group, share, total, entry.rounds.count) : nil
        }
        .sorted { $0.0 < $1.0 }
        if let first = mixedGroups.first {
            let groups = mixedGroups.map { "\($0.0.title)-letter" }.joined(separator: ", ")
            add(1 + first.1, MechanicsRecommendation(
                kind: .inconsistentStrategy, area: .capitalisationLab, drill: .labShiftOnly,
                title: "Find your best method for \(groups) capitals",
                evidence: "You used both Shift and Caps Lock for \(groups) capitals (\(first.2) runs over \(first.3) rounds). A Lab comparison shows which is faster for you.",
                rounds: first.3))
        }

        /// 1 for the kinds the chosen priority puts first, else 0.
        func tier(_ entry: (strength: Double, recommendation: MechanicsRecommendation)) -> Int {
            switch priority {
            case .balanced: 0
            case .accuracy: accuracyKinds.contains(entry.recommendation.kind) ? 1 : 0
            case .speed: speedKinds.contains(entry.recommendation.kind) ? 1 : 0
            }
        }
        return found.sorted {
            (tier($0), $0.strength, $1.recommendation.kind.rawValue) > (tier($1), $1.strength, $0.recommendation.kind.rawValue)
        }
            .prefix(limit)
            .map(\.recommendation)
    }
}

enum OverheadMath {
    static func rounded(_ value: Double) -> Int { Int((value / 5).rounded()) * 5 }
}
