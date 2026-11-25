import Foundation

/// One completed Typing Mechanics round.
public struct MechanicsEvent: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let drill: MechanicsDrill
    public let result: MechanicsRoundResult

    public init(id: UUID = UUID(), date: Date = .now, drill: MechanicsDrill, result: MechanicsRoundResult) {
        self.id = id
        self.date = date
        self.drill = drill
        self.result = result
    }
}

/// A short, explainable observation about one round.
public struct MechanicsTip: Sendable, Equatable {
    public let title: String
    public let detail: String
}

public enum MechanicsFeedback {
    /// Samples needed on each side before a timing comparison is mentioned.
    public static let minimumSamples = 3
    /// A transition this many times its baseline is called slow.
    public static let slowRatio = 1.4

    /// Observed median, baseline median and their difference (ms), when
    /// both sides have enough samples.
    public static func comparison(_ kind: TransitionClass, in result: MechanicsRoundResult)
        -> (observed: Double, baseline: Double, difference: Double)? {
        guard let base = kind.baseline else { return nil }
        let observed = result.samples(kind), baseline = result.samples(base)
        guard observed.count >= minimumSamples, baseline.count >= minimumSamples,
              let o = observed.median, let b = baseline.median else { return nil }
        return (o, b, o - b)
    }

    /// At most two tips, most useful first. Nothing when the evidence is thin.
    public static func tips(for result: MechanicsRoundResult, drill: MechanicsDrill) -> [MechanicsTip] {
        var tips: [MechanicsTip] = []

        if result.techniqueChecked >= minimumSamples, let accuracy = result.techniqueAccuracy, accuracy < 0.8,
           let wanted = drill.wantedTechnique {
            let detail = wanted == .shift
                ? "Several capitals were typed with Caps Lock. This drill trains Shift: hold it for each capital."
                : "Several capitals were typed with Shift. Switch Caps Lock on before the capitals and off after them."
            tips.append(MechanicsTip(title: wanted == .shift ? "Use Shift" : "Use Caps Lock", detail: detail))
        }
        if result.capsLockLeftOn > 0 {
            tips.append(MechanicsTip(title: "Caps Lock stayed on",
                                     detail: "\(result.capsLockLeftOn) lower-case \(result.capsLockLeftOn == 1 ? "letter was" : "letters were") typed in capitals. Switch it off right after the last capital."))
        }
        let shiftCount = result.oppositeHandShift + result.sameHandShift
        if drill.area == .shiftControl, shiftCount >= 4, Double(result.oppositeHandShift) / Double(shiftCount) < 0.5 {
            tips.append(MechanicsTip(title: "Try the other Shift",
                                     detail: "\(result.sameHandShift) of \(shiftCount) capitals used the Shift on the same hand as the letter. The opposite Shift lets one hand hold while the other types."))
        }
        if let watch = charactersToWatch(in: result).first {
            let count = result.characters?[String(watch.character)]
            let detail = watch.reason == .errors
                ? "\u{201C}\(watch.character)\u{201D} was wrong \(count?.errors ?? 0) of \(count?.attempts ?? 0) times. Look at where it sits, then type it slowly a few times."
                : "\u{201C}\(watch.character)\u{201D} took about \(Int((watch.ratio * 100 - 100).rounded()))% longer to reach than your usual key change."
            tips.append(MechanicsTip(title: "Watch \u{201C}\(watch.character)\u{201D}", detail: detail))
        }
        for kind in [TransitionClass.intoDigitDirect, .intoDigitAcrossSpace, .outOfDigitDirect, .outOfDigitAcrossSpace] {
            guard let c = comparison(kind, in: result), c.baseline > 0, c.observed / c.baseline >= slowRatio else { continue }
            let into = kind == .intoDigitDirect || kind == .intoDigitAcrossSpace
            tips.append(MechanicsTip(title: into ? "Reaching for numbers is slow" : "Coming back from numbers is slow",
                                     detail: "About \(Int(c.difference.rounded())) ms longer than the same key change between letters (\(Int(c.observed.rounded())) vs \(Int(c.baseline.rounded())) ms, median)."))
            break
        }
        for kind in [TransitionClass.intoUpperDirect, .intoUpperAcrossSpace, .outOfUpperDirect, .outOfUpperAcrossSpace] {
            guard let c = comparison(kind, in: result), c.baseline > 0, c.observed / c.baseline >= slowRatio else { continue }
            let into = kind == .intoUpperDirect || kind == .intoUpperAcrossSpace
            tips.append(MechanicsTip(title: into ? "Starting capitals is slow" : "Returning to lower case is slow",
                                     detail: "About \(Int(c.difference.rounded())) ms longer than the same key change in lower case (\(Int(c.observed.rounded())) vs \(Int(c.baseline.rounded())) ms, median)."))
            break
        }
        return Array(tips.prefix(2))
    }

}

extension MechanicsDrill {
    /// The technique the drill is built to train, if it insists on one.
    public var wantedTechnique: TechniqueRule? {
        switch self {
        case .labShiftOnly: .shift
        case .labCapsLockOnly: .capsLock
        case .labFreeChoice: nil
        default:
            switch area {
            case .shiftControl: .shift
            case .capsLockControl: .capsLock
            // Symbols can only be typed with Shift, so there is no method to train.
            case .caseTransitions, .capitalisationLab, .numbersSymbols: nil
            }
        }
    }
}

/// A digit or symbol that keeps being missed or is slow to reach.
public struct CharacterToWatch: Sendable, Equatable {
    public enum Reason: Sendable { case errors, slow }
    public let character: Character
    public let reason: Reason
    /// Error rate, or reach time ÷ the round's usual key change.
    public let ratio: Double
}

extension MechanicsFeedback {
    /// Missed at least `minimumErrors` times with an error rate of
    /// `errorRate` or more, or reached `slowRatio`× slower than the round's
    /// median key change over at least `minimumSamples` clean presses.
    /// Worst first: errors before slowness.
    public static let minimumErrors = 2
    public static let errorRate = 0.15

    public static func charactersToWatch(in result: MechanicsRoundResult) -> [CharacterToWatch] {
        guard let characters = result.characters else { return [] }
        let usual = TimingSamples(result.samples(.lowerDirect).values + result.samples(.withinDigits).values).median
        var watch: [CharacterToWatch] = []
        for (key, stat) in characters {
            guard let character = key.first else { continue }
            if stat.errors >= minimumErrors, stat.errorRate >= errorRate {
                watch.append(CharacterToWatch(character: character, reason: .errors, ratio: stat.errorRate))
            } else if let usual, usual > 0, stat.reach.count >= minimumSamples, let median = stat.reach.median,
                      median / usual >= slowRatio {
                watch.append(CharacterToWatch(character: character, reason: .slow, ratio: median / usual))
            }
        }
        return watch.sorted { a, b in
            if (a.reason == .errors) != (b.reason == .errors) { return a.reason == .errors }
            return (a.ratio, String(b.character)) > (b.ratio, String(a.character))
        }
    }
}

/// Rounds and steadiness per drill.
///
/// A drill is **steady** after `MasteryTracker.requiredRounds` rounds with
/// character accuracy of at least `MasteryTracker.requiredAccuracy` and,
/// where technique could be checked, technique accuracy of at least
/// `requiredTechniqueAccuracy`. Drills are never locked.
public struct MechanicsProgress: Sendable {
    public static let requiredTechniqueAccuracy = 0.9

    public struct DrillProgress: Sendable, Equatable {
        public internal(set) var rounds = 0
        public internal(set) var qualifyingRounds = 0
        public internal(set) var lastResult: MechanicsRoundResult?

        public var isSteady: Bool { qualifyingRounds >= MasteryTracker.requiredRounds }
    }

    private var drills: [MechanicsDrill: DrillProgress] = [:]
    /// Lab comparisons with both halves done, oldest first.
    public private(set) var comparisons: [LabComparison] = []

    /// One passage typed with Shift Only and with Caps Lock Only.
    public struct LabComparison: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let shift: MechanicsRoundResult
        public let capsLock: MechanicsRoundResult
        /// Which was typed first, for counterbalancing.
        public let first: MechanicsDrill
        public let date: Date
    }

    public init(events: [MechanicsEvent]) {
        for event in events.sorted(by: { $0.date < $1.date }) {
            var progress = drills[event.drill] ?? DrillProgress()
            progress.rounds += 1
            progress.lastResult = event.result
            if Self.qualifies(event.result) { progress.qualifyingRounds += 1 }
            drills[event.drill] = progress
        }

        var halves: [UUID: [MechanicsEvent]] = [:]
        for event in events where event.result.comparisonID != nil {
            halves[event.result.comparisonID!, default: []].append(event)
        }
        comparisons = halves.compactMap { id, events -> LabComparison? in
            guard let shift = events.first(where: { $0.drill == .labShiftOnly }),
                  let caps = events.first(where: { $0.drill == .labCapsLockOnly }) else { return nil }
            let first = shift.result.comparisonOrder == 1 ? MechanicsDrill.labShiftOnly : .labCapsLockOnly
            return LabComparison(id: id, shift: shift.result, capsLock: caps.result, first: first,
                                 date: max(shift.date, caps.date))
        }
        .sorted { $0.date < $1.date }
    }

    /// Counterbalancing: comparisons alternate which technique comes first,
    /// so practice within a pair favours neither.
    public var nextLabFirst: MechanicsDrill {
        comparisons.count.isMultiple(of: 2) ? .labShiftOnly : .labCapsLockOnly
    }

    public static func qualifies(_ result: MechanicsRoundResult) -> Bool {
        result.keystrokes > 0 && result.characterAccuracy >= MasteryTracker.requiredAccuracy
            && (result.techniqueAccuracy ?? 1) >= requiredTechniqueAccuracy
    }

    public func progress(_ drill: MechanicsDrill) -> DrillProgress { drills[drill] ?? DrillProgress() }

    /// The first drill of an area that is not yet steady, else its last.
    public func recommended(in area: MechanicsArea) -> MechanicsDrill {
        if area == .capitalisationLab { return nextLabFirst }
        return area.drills.first { !progress($0).isSteady } ?? area.drills.last!
    }
}
