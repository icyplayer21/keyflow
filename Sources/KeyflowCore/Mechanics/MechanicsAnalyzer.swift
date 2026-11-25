import Foundation

/// Timing samples for one kind of key change, in milliseconds.
public struct TimingSamples: Codable, Sendable, Equatable {
    public var values: [Double]

    public init(_ values: [Double] = []) { self.values = values }

    public var count: Int { values.count }

    public var median: Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

/// The kinds of key change Typing Mechanics times. A *span* runs from one
/// key press to another; spans of one key change are compared with spans of
/// one key change, and spans across a space with spans across a space.
public enum TransitionClass: String, Codable, Sendable, CaseIterable {
    /// Lower-case letter → capital ("aB").
    case intoUpperDirect
    /// Lower-case letter → space → capital ("a B"): two key changes.
    case intoUpperAcrossSpace
    /// Capital → lower-case letter ("Ab").
    case outOfUpperDirect
    /// Capital → space → lower-case letter ("A b").
    case outOfUpperAcrossSpace
    /// Capital → capital ("AB").
    case withinUpper
    /// Baseline: lower-case letter → lower-case letter.
    case lowerDirect
    /// Baseline: lower-case letter → space → lower-case letter.
    case lowerAcrossSpace
    /// Baseline: one key change between a lower-case letter and a space, either way.
    case spaceAdjacent
    /// Lower-case letter → digit ("a1").
    case intoDigitDirect
    /// Lower-case letter → space → digit ("a 1").
    case intoDigitAcrossSpace
    /// Digit → lower-case letter ("1a").
    case outOfDigitDirect
    /// Digit → space → lower-case letter ("1 a").
    case outOfDigitAcrossSpace
    /// Digit → digit ("12").
    case withinDigits
    /// A letter or digit → a shifted symbol ("5%", "o!").
    case intoShiftedSymbol

    /// The baseline a transition is compared with.
    public var baseline: TransitionClass? {
        switch self {
        case .intoUpperDirect, .outOfUpperDirect, .withinUpper: .lowerDirect
        case .intoUpperAcrossSpace, .outOfUpperAcrossSpace: .lowerAcrossSpace
        case .intoDigitDirect, .outOfDigitDirect, .withinDigits, .intoShiftedSymbol: .lowerDirect
        case .intoDigitAcrossSpace, .outOfDigitAcrossSpace: .lowerAcrossSpace
        case .lowerDirect, .lowerAcrossSpace, .spaceAdjacent: nil
        }
    }
}

/// Everything kept from one Typing Mechanics round: counts and timing
/// samples, no keystroke log.
public struct MechanicsRoundResult: Codable, Sendable, Equatable {
    public var text: String
    public var duration: TimeInterval

    // Character validation
    public var keystrokes: Int
    public var correctKeystrokes: Int
    /// Wrong presses that were the right key in the wrong case ("a" for "A",
    /// "1" for "!"): Shift or Caps Lock trouble rather than a wrong key.
    public var caseErrors: Int
    /// Capitals typed where lower case was due while Caps Lock was on.
    public var capsLockLeftOn: Int

    // Technique validation (correct characters only)
    public var techniqueChecked: Int
    public var techniqueCorrect: Int
    /// Correct characters whose technique could not be observed.
    public var techniqueUnknown: Int
    public var techniques: [String: Int]
    /// Shift capitals typed with the Shift on the other hand to the letter.
    public var oppositeHandShift: Int
    public var sameHandShift: Int

    // Timing (ms)
    /// Shift press → letter, for each Shift capital or symbol.
    public var shiftLead: TimingSamples
    /// Caps Lock switched on → first capital.
    public var capsLockLead: TimingSamples
    public var transitions: [String: TimingSamples]

    /// Every run of capitals in the text, in order. Absent in rounds saved
    /// before segments were recorded.
    public var segments: [UppercaseSegment]? = nil
    /// Capitalisation Lab: the Shift Only and Caps Lock Only rounds typed on
    /// the same passage share an id; `comparisonOrder` is 1 or 2.
    public var comparisonID: UUID? = nil
    public var comparisonOrder: Int? = nil
    /// Digits and symbols: attempts, errors and reach time per character.
    public var characters: [String: CharacterStat]? = nil

    public var characterAccuracy: Double { keystrokes > 0 ? Double(correctKeystrokes) / Double(keystrokes) : 0 }
    public var techniqueAccuracy: Double? { techniqueChecked > 0 ? Double(techniqueCorrect) / Double(techniqueChecked) : nil }

    public func samples(_ kind: TransitionClass) -> TimingSamples { transitions[kind.rawValue] ?? TimingSamples() }
}

/// Analyses a finished round.
///
/// **Character validation** asks whether the right character was typed, as
/// everywhere in Keyflow. **Technique validation** asks, for each character
/// typed *correctly*, whether it was produced the way the drill requires. A
/// capital typed with Caps Lock in a Shift drill is a correct character with
/// an incorrect technique, never a character error. Characters whose
/// technique could not be observed are counted separately and not judged.
///
/// **Timing** uses spans between consecutive correct key presses typed in one
/// forward pass (no correction inside the span, no pause longer than
/// `SessionAnalyzer.pauseThreshold`, no auto-repeat). A Caps Lock switch
/// happens inside such a span, so its cost is included.
public enum MechanicsAnalyzer {
    /// - Parameter judgeSymbols: whether Shift for symbols is judged. Pass
    ///   `false` on keyboard layouts that are not US QWERTY, where which
    ///   symbols need Shift is not known.
    public static func analyze(_ session: TypingSession, strokes: [ObservedKeystroke],
                               drill: MechanicsDrill, judgeSymbols: Bool = true) -> MechanicsRoundResult {
        let target = session.target
        let inserts = session.events.enumerated().filter { $0.element.kind == .insert }
        var result = MechanicsRoundResult(text: String(target), duration: session.elapsed, keystrokes: 0, correctKeystrokes: 0,
                                          caseErrors: 0, capsLockLeftOn: 0, techniqueChecked: 0, techniqueCorrect: 0,
                                          techniqueUnknown: 0, techniques: [:], oppositeHandShift: 0, sameHandShift: 0,
                                          shiftLead: TimingSamples(), capsLockLead: TimingSamples(), transitions: [:])

        // The stroke for each insert event, matched in order.
        var strokeForEvent: [Int: ObservedKeystroke] = [:]
        for (pair, stroke) in zip(inserts, strokes) { strokeForEvent[pair.offset] = stroke }

        var capsLeadCounted = Set<Double>()
        for (index, event) in inserts {
            result.keystrokes += 1
            let stroke = strokeForEvent[index]
            guard event.isCorrect else {
                if isCaseError(expected: event.expected, typed: event.typed) { result.caseErrors += 1 }
                if event.expected.isLowercase, event.typed.isUppercase, stroke?.technique.usesCapsLock == true {
                    result.capsLockLeftOn += 1
                }
                continue
            }
            result.correctKeystrokes += 1

            var rule = drill.rule(at: event.position, in: target)
            if !judgeSymbols, CaseRequirement.of(event.expected) == .shiftedSymbol { rule = .none }
            guard rule != .none, let stroke else { continue }
            result.techniques[stroke.technique.rawValue, default: 0] += 1
            if stroke.technique == .unknown {
                result.techniqueUnknown += 1
            } else {
                result.techniqueChecked += 1
                if rule.accepts(stroke.technique) { result.techniqueCorrect += 1 }
            }
            if let lead = stroke.shiftLead { result.shiftLead.values.append(ms(lead)) }
            if let on = stroke.capsLockOnAt, !stroke.isRepeat, !capsLeadCounted.contains(on), stroke.time >= on {
                capsLeadCounted.insert(on)
                result.capsLockLead.values.append(ms(stroke.time - on))
            }
            if event.expected.isLetter || CaseRequirement.of(event.expected) == .shiftedSymbol,
               let side = stroke.technique.shiftSide, let hand = FingerMap.hand(for: event.expected) {
                if (hand == .left && side == .right) || (hand == .right && side == .left) {
                    result.oppositeHandShift += 1
                } else {
                    result.sameHandShift += 1
                }
            }
        }

        let timeline = Timeline(session, strokes: strokeForEvent)
        result.transitions = transitions(timeline)
        result.segments = segments(timeline, baselines: RoundBaseline(result))
        result.characters = characterStats(session, timeline)
        return result
    }

    /// The same key in the wrong case or shift state.
    public static func isCaseError(expected: Character, typed: Character) -> Bool {
        guard expected != typed else { return false }
        if expected.isLetter, typed.isLetter, expected.lowercased() == typed.lowercased() { return true }
        let a = KeyboardLayout.baseKey(for: expected), b = KeyboardLayout.baseKey(for: typed)
        return a != nil && a == b
    }

    // MARK: Timing

    /// When each position was finally typed correctly, in one clean forward
    /// pass, and how spans between positions are timed.
    struct Timeline {
        struct Typed {
            let time: TimeInterval
            let eventIndex: Int
            let stroke: ObservedKeystroke?
        }

        let target: [Character]
        private(set) var finals: [Int: Typed] = [:]
        /// Positions that ever received a wrong character.
        private(set) var mistyped = Set<Int>()

        init(_ session: TypingSession, strokes: [Int: ObservedKeystroke]) {
            target = session.target
            for (index, event) in session.events.enumerated() where event.kind == .insert {
                if event.isCorrect {
                    finals[event.position] = Typed(time: event.time, eventIndex: index, stroke: strokes[index])
                } else {
                    finals[event.position] = nil
                    mistyped.insert(event.position)
                }
            }
            // A position whose correct press was later deleted does not count.
            let typed = session.typed
            finals = finals.filter { $0.key < typed.count && typed[$0.key] == session.target[$0.key] }
        }

        /// Milliseconds from position a to b, if every key in between was typed
        /// cleanly and consecutively, without pauses or auto-repeat.
        func span(_ a: Int, _ b: Int) -> Double? {
            guard a >= 0, b < target.count, a < b else { return nil }
            var previous: Typed?
            for position in a...b {
                guard let typed = finals[position], typed.stroke?.isRepeat != true else { return nil }
                if let previous {
                    guard typed.eventIndex == previous.eventIndex + 1 else { return nil }
                    let gap = typed.time - previous.time
                    guard gap > 0, gap <= SessionAnalyzer.pauseThreshold else { return nil }
                }
                previous = typed
            }
            return MechanicsAnalyzer.ms(finals[b]!.time - finals[a]!.time)
        }

        func isLower(_ i: Int) -> Bool { target.indices.contains(i) && target[i].isLetter && target[i].isLowercase }
        func isUpper(_ i: Int) -> Bool { target.indices.contains(i) && CaseRequirement.of(target[i]) == .uppercaseLetter }
        func isSpace(_ i: Int) -> Bool { target.indices.contains(i) && target[i] == " " }
        func isDigit(_ i: Int) -> Bool { target.indices.contains(i) && target[i].isASCII && target[i].isNumber }
        func isShiftedSymbol(_ i: Int) -> Bool { target.indices.contains(i) && CaseRequirement.of(target[i]) == .shiftedSymbol }
    }

    /// Digits and symbols: every attempt, every error, and the time to
    /// reach the character from the key before (clean presses only).
    static func characterStats(_ session: TypingSession, _ t: Timeline) -> [String: CharacterStat] {
        var stats: [String: CharacterStat] = [:]
        func tracked(_ c: Character) -> Bool { c != " " && !c.isLetter }
        for event in session.events where event.kind == .insert && tracked(event.expected) {
            stats[String(event.expected), default: CharacterStat()].attempts += 1
            if !event.isCorrect { stats[String(event.expected), default: CharacterStat()].errors += 1 }
        }
        for i in t.target.indices where tracked(t.target[i]) {
            if let reach = t.span(i - 1, i) { stats[String(t.target[i]), default: CharacterStat()].reach.values.append(reach) }
        }
        return stats
    }

    static func transitions(_ t: Timeline) -> [String: TimingSamples] {
        var samples: [TransitionClass: [Double]] = [:]
        func add(_ kind: TransitionClass, _ value: Double?) { if let value { samples[kind, default: []].append(value) } }

        for i in t.target.indices {
            if t.isUpper(i) {
                if t.isLower(i - 1) { add(.intoUpperDirect, t.span(i - 1, i)) }
                if t.isSpace(i - 1), t.isLower(i - 2) { add(.intoUpperAcrossSpace, t.span(i - 2, i)) }
                if t.isUpper(i - 1) { add(.withinUpper, t.span(i - 1, i)) }
                if t.isLower(i + 1) { add(.outOfUpperDirect, t.span(i, i + 1)) }
                if t.isSpace(i + 1), t.isLower(i + 2) { add(.outOfUpperAcrossSpace, t.span(i, i + 2)) }
            } else if t.isLower(i) {
                if t.isLower(i - 1) { add(.lowerDirect, t.span(i - 1, i)) }
                if t.isSpace(i - 1), t.isLower(i - 2) { add(.lowerAcrossSpace, t.span(i - 2, i)) }
            } else if t.isSpace(i) {
                if t.isLower(i - 1) { add(.spaceAdjacent, t.span(i - 1, i)) }
                if t.isLower(i + 1) { add(.spaceAdjacent, t.span(i, i + 1)) }
            }
            if t.isDigit(i) {
                if t.isLower(i - 1) { add(.intoDigitDirect, t.span(i - 1, i)) }
                if t.isSpace(i - 1), t.isLower(i - 2) { add(.intoDigitAcrossSpace, t.span(i - 2, i)) }
                if t.isDigit(i - 1) { add(.withinDigits, t.span(i - 1, i)) }
                if t.isLower(i + 1) { add(.outOfDigitDirect, t.span(i, i + 1)) }
                if t.isSpace(i + 1), t.isLower(i + 2) { add(.outOfDigitAcrossSpace, t.span(i, i + 2)) }
            }
            if t.isShiftedSymbol(i), t.isLower(i - 1) || t.isDigit(i - 1) {
                add(.intoShiftedSymbol, t.span(i - 1, i))
            }
        }
        return Dictionary(uniqueKeysWithValues: samples.map { ($0.key.rawValue, TimingSamples($0.value)) })
    }

    /// Each run of capitals: its length, how it was produced, whether it was
    /// typed cleanly, and its timing including the keys either side, so both
    /// a Caps Lock switch on and the switch off fall inside the span.
    static func segments(_ t: Timeline, baselines: RoundBaseline) -> [UppercaseSegment] {
        var result: [UppercaseSegment] = []
        var i = 0
        while i < t.target.count {
            guard t.isUpper(i) else { i += 1; continue }
            var end = i
            while t.isUpper(end + 1) { end += 1 }
            let methods = (i...end).map { position -> UppercaseSegment.Method in
                guard let technique = t.finals[position]?.stroke?.technique else { return .unknown }
                if technique.usesCapsLock { return .capsLock }
                if technique.usesShift { return .shift }
                return .unknown
            }
            let method: UppercaseSegment.Method = methods.contains(.unknown) ? .unknown
                : (Set(methods).count == 1 ? methods[0] : .mixed)
            let clean = (i...end).allSatisfy { t.finals[$0] != nil && !t.mistyped.contains($0) }
            let before: UppercaseSegment.Neighbour = i > 0 ? .init(t.target[i - 1]) : .none
            let after: UppercaseSegment.Neighbour = end + 1 < t.target.count ? .init(t.target[end + 1]) : .none
            result.append(UppercaseSegment(
                length: end - i + 1, method: method, clean: clean,
                spanMs: t.span(i - 1, end + 1), entryMs: t.span(i - 1, i), exitMs: t.span(end, end + 1),
                before: before, after: after,
                baselineMs: baselines.expected(length: end - i + 1, before: before, after: after)))
            i = end + 1
        }
        return result
    }

    /// The round's ordinary rhythm: median time for one key change between
    /// lower-case letters, and between a lower-case letter and a space.
    struct RoundBaseline {
        let letter: Double?
        let space: Double?

        init(_ result: MechanicsRoundResult) {
            func median(_ kind: TransitionClass) -> Double? {
                let samples = result.samples(kind)
                return samples.count >= MechanicsFeedback.minimumSamples ? samples.median : nil
            }
            letter = median(.lowerDirect)
            space = median(.spaceAdjacent)
        }

        /// What `length + 1` ordinary key changes of the same kinds would take:
        /// one into the run, one per letter pair inside it, one out of it.
        /// `nil` when a neighbour is punctuation or missing, or a needed
        /// baseline has too few samples.
        func expected(length: Int, before: UppercaseSegment.Neighbour, after: UppercaseSegment.Neighbour) -> Double? {
            func side(_ neighbour: UppercaseSegment.Neighbour) -> Double? {
                switch neighbour {
                case .space: space
                case .lowercase: letter
                case .other, .none: nil
                }
            }
            guard let entry = side(before), let exit = side(after) else { return nil }
            if length > 1 { guard let letter else { return nil }; return entry + exit + Double(length - 1) * letter }
            return entry + exit
        }
    }

    static func ms(_ seconds: TimeInterval) -> Double { (seconds * 10_000).rounded() / 10 }
}

/// One digit or symbol across a round.
public struct CharacterStat: Codable, Sendable, Equatable {
    public var attempts = 0
    public var errors = 0
    /// Milliseconds from the previous key, for clean presses.
    public var reach = TimingSamples()

    public init() {}

    public var errorRate: Double { attempts > 0 ? Double(errors) / Double(attempts) : 0 }
}

/// One run of capitals ("NASA", "B") in a round.
public struct UppercaseSegment: Codable, Sendable, Equatable {
    public enum Method: String, Codable, Sendable { case shift, capsLock, mixed, unknown }

    /// What sits either side, which shapes how the span can be compared.
    public enum Neighbour: String, Codable, Sendable {
        case lowercase, space, other, none

        init(_ character: Character) {
            if character == " " { self = .space }
            else if character.isLetter, character.isLowercase { self = .lowercase }
            else { self = .other }
        }
    }

    public var length: Int
    public var method: Method
    /// Every letter right first time.
    public var clean: Bool
    /// From the key before the capitals to the key after them (length + 1
    /// key changes), when typed in one clean pass. Includes any Caps Lock
    /// switch on and off.
    public var spanMs: Double?
    /// Key before → first capital.
    public var entryMs: Double?
    /// Last capital → key after.
    public var exitMs: Double?
    public var before: Neighbour
    public var after: Neighbour
    /// What the same key changes took in ordinary lower-case typing in the
    /// same round. `nil` when there was no comparable baseline.
    public var baselineMs: Double? = nil

    /// Observed span minus baseline: the estimated extra time for this run.
    /// May be negative.
    public var overheadMs: Double? {
        guard clean, let spanMs, let baselineMs else { return nil }
        return spanMs - baselineMs
    }

    public var group: SegmentLength { SegmentLength(length) }
}

/// Length groups for comparing capitalisation methods.
public enum SegmentLength: String, Codable, Sendable, CaseIterable, Comparable {
    case one, two, threeFour, fiveSeven, eightPlus

    public init(_ length: Int) {
        switch length {
        case ...1: self = .one
        case 2: self = .two
        case 3...4: self = .threeFour
        case 5...7: self = .fiveSeven
        default: self = .eightPlus
        }
    }

    public var title: String {
        switch self {
        case .one: "1"
        case .two: "2"
        case .threeFour: "3–4"
        case .fiveSeven: "5–7"
        case .eightPlus: "8+"
        }
    }

    public static func < (a: Self, b: Self) -> Bool { allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)! }
}

extension CaseTechnique {
    /// The Shift side, when the technique used one Shift that is known.
    public var shiftSide: ShiftSide? {
        switch self {
        case .leftShift: .left
        case .rightShift: .right
        default: nil
        }
    }
}
