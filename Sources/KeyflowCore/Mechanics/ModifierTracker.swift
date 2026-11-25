import Foundation

/// One key press as Typing Mechanics sees it: the character, what it
/// required, how it was actually produced, and the modifier timing around it.
public struct ObservedKeystroke: Sendable, Equatable {
    public let character: Character
    public let keyCode: UInt16
    /// Monotonic seconds (the event's own timestamp).
    public let time: TimeInterval
    /// An auto-repeat from a held key. Repeats are never used for timing.
    public let isRepeat: Bool
    public let requirement: CaseRequirement
    public let technique: CaseTechnique
    /// Seconds from pressing the Shift key this keystroke used to this key
    /// press. `nil` when Shift was not used, or its press was not observed
    /// (held before typing began, or before focus returned).
    public let shiftLead: TimeInterval?
    /// When Caps Lock was last switched on, if this keystroke relied on it
    /// and the switch was observed.
    public let capsLockOnAt: TimeInterval?
    /// The key press's own modifier flags disagreed with the tracked state,
    /// so an earlier modifier event was missed and the state was corrected.
    public let reconciled: Bool
}

/// Follows Shift and Caps Lock between key presses and classifies how each
/// typed character was produced.
///
/// Sources, in order of trust:
/// 1. The modifier flags carried by the key-down event itself. They are
///    what macOS used to produce the character, so they decide the technique.
/// 2. `flagsChanged` events between key presses. They give the *timing*:
///    when Shift went down, when Caps Lock was switched.
///
/// When the two disagree (a modifier changed while the window was not
/// listening), the key-down wins, the state is corrected, and the timing for
/// that modifier becomes unknown rather than guessed. After focus is lost,
/// held Shift keys are released and Caps Lock is unknown until the next sync
/// or key press, because key-ups may never arrive.
///
/// Nothing here infers technique from the character alone: an upper-case
/// letter with no modifier observed is `.unknown`, not assumed to be Shift.
public struct ModifierTracker: Sendable {
    /// A held modifier. `since` is `nil` when the press itself was not observed.
    public struct Held: Sendable, Equatable {
        public let since: TimeInterval?
    }

    public private(set) var leftShift: Held?
    public private(set) var rightShift: Held?
    /// Shift reported without a side (some keyboards and remappers).
    public private(set) var unsidedShift: Held?
    /// `nil` while unknown (after focus loss, before the first sync).
    public private(set) var capsLock: Bool?
    /// When Caps Lock last changed, if observed.
    public private(set) var capsLockChangedAt: TimeInterval?

    public private(set) var modifierEvents: [ModifierEvent] = []
    public private(set) var keystrokes: [ObservedKeystroke] = []

    public init() {}

    /// Drops the event and keystroke history but keeps the current modifier
    /// state, so a new round starts knowing which keys are held.
    public mutating func clearHistory() {
        modifierEvents = []
        keystrokes = []
    }

    public var isShiftHeld: Bool { leftShift != nil || rightShift != nil || unsidedShift != nil }

    // MARK: Modifier events

    public mutating func apply(_ event: ModifierEvent) {
        modifierEvents.append(event)
        switch event {
        case .shiftDown(let side, let time):
            switch side {
            case .left: leftShift = Held(since: time)
            case .right: rightShift = Held(since: time)
            case .both: leftShift = Held(since: time); rightShift = Held(since: time)
            case nil: unsidedShift = Held(since: time)
            }
        case .shiftUp(let side, _):
            switch side {
            case .left: leftShift = nil
            case .right: rightShift = nil
            case .both: leftShift = nil; rightShift = nil
            case nil: unsidedShift = nil
            }
            if leftShift == nil, rightShift == nil { unsidedShift = nil }
        case .capsLock(let on, let time):
            if capsLock != on { capsLockChangedAt = time }
            capsLock = on
        case .focusLost:
            leftShift = nil
            rightShift = nil
            unsidedShift = nil
            capsLock = nil
            capsLockChangedAt = nil
        case .sync(let snapshot, _):
            _ = reconcile(with: snapshot)
        }
    }

    // MARK: Key presses

    /// Records a typed character. `modifiers` are the key-down's own flags;
    /// pass `nil` only when they are unavailable, and the tracked state is used.
    @discardableResult
    public mutating func keystroke(_ character: Character, keyCode: UInt16 = 0, at time: TimeInterval,
                                   isRepeat: Bool = false, modifiers: ModifierSnapshot?) -> ObservedKeystroke {
        let reconciled = modifiers.map { reconcile(with: $0) } ?? false
        let state = modifiers ?? currentSnapshot
        let requirement = CaseRequirement.of(character)
        let technique = Self.technique(for: character, requirement: requirement, state: state)

        var lead: TimeInterval?
        if technique.usesShift, !isRepeat, let since = shiftPress(for: technique)?.since, time >= since {
            lead = time - since
        }
        let capsOn = technique.usesCapsLock && capsLock == true ? capsLockChangedAt : nil

        let stroke = ObservedKeystroke(character: character, keyCode: keyCode, time: time, isRepeat: isRepeat,
                                       requirement: requirement, technique: technique, shiftLead: lead,
                                       capsLockOnAt: capsOn, reconciled: reconciled)
        keystrokes.append(stroke)
        return stroke
    }

    /// How a character was produced, from the modifier state it was typed with.
    public static func technique(for character: Character, requirement: CaseRequirement,
                                 state: ModifierSnapshot) -> CaseTechnique {
        let shift = shiftTechnique(state)
        switch requirement {
        case .uppercaseLetter:
            if state.shift && state.capsLock { return .capsLockWithShift }
            if state.shift { return shift }
            if state.capsLock { return .capsLock }
            return .unknown
        case .shiftedSymbol:
            return state.shift ? shift : .unknown
        case .plain:
            // A lower-case letter typed while upper case was active means
            // something else produced it (an input method, a remap).
            if character.isLetter, state.shift || state.capsLock { return .unknown }
            return .unmodified
        case .unsupported:
            return .unknown
        }
    }

    // MARK: Private

    private var currentSnapshot: ModifierSnapshot {
        ModifierSnapshot(leftShift: leftShift != nil, rightShift: rightShift != nil,
                         shift: isShiftHeld, capsLock: capsLock ?? false)
    }

    private static func shiftTechnique(_ state: ModifierSnapshot) -> CaseTechnique {
        switch state.shiftSide {
        case .left: .leftShift
        case .right: .rightShift
        case .both, nil: .shift
        }
    }

    /// The press of the Shift key the technique used; for both or an
    /// unknown side, the most recent one.
    private func shiftPress(for technique: CaseTechnique) -> Held? {
        switch technique {
        case .leftShift: return leftShift
        case .rightShift: return rightShift
        default:
            let held = [leftShift, rightShift, unsidedShift].compactMap { $0 }
            if held.contains(where: { $0.since == nil }) { return Held(since: nil) }
            return held.max { ($0.since ?? 0) < ($1.since ?? 0) }
        }
    }

    /// Brings the tracked state in line with flags macOS reported. Returns
    /// whether anything had to change.
    private mutating func reconcile(with snapshot: ModifierSnapshot) -> Bool {
        var changed = false
        func align(_ held: inout Held?, _ down: Bool) {
            if down, held == nil { held = Held(since: nil); changed = true }
            if !down, held != nil { held = nil; changed = true }
        }
        align(&leftShift, snapshot.leftShift)
        align(&rightShift, snapshot.rightShift)
        let unsided = snapshot.shift && !snapshot.leftShift && !snapshot.rightShift
        align(&unsidedShift, unsided)
        if capsLock != snapshot.capsLock {
            // A known state that differs means a switch was missed; unknown → known is just learning it.
            if capsLock != nil { changed = true }
            capsLock = snapshot.capsLock
            capsLockChangedAt = nil
        }
        return changed
    }
}
