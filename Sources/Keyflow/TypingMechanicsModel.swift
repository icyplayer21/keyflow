import Foundation
import KeyflowCore
import Observation

/// Drives Typing Mechanics: the chosen drill, the live typing engine, Shift
/// and Caps Lock observation, and saving each completed round.
///
/// The typing engine sees characters exactly as in every other mode. Beside
/// it, a `ModifierTracker` records how each accepted character was produced;
/// the two are paired one-to-one for the round analysis.
@MainActor
@Observable
final class TypingMechanicsModel {
    struct RoundSummary {
        let result: MechanicsRoundResult
        let tips: [MechanicsTip]
        /// This round made the drill steady.
        let justSteadied: Bool
        /// Capitalisation Lab: the finished pair, after its second half.
        var comparison: MechanicsProgress.LabComparison? = nil
    }

    /// A Lab comparison waiting for its second half on the same passage.
    struct PendingComparison: Equatable {
        let id: UUID
        let text: String
        /// The mode still to type.
        let awaiting: MechanicsDrill
    }

    private(set) var area: MechanicsArea
    private(set) var drill: MechanicsDrill
    private(set) var text: String
    private(set) var engine: TypingEngine
    private(set) var now: MonotonicTime = 0
    private(set) var summary: RoundSummary?
    private(set) var saveError: String?
    private(set) var lastMiss: MuscleMemoryModel.KeyMiss?
    /// Called when a wrong character is typed (sound feedback).
    @ObservationIgnored var onMistake: (() -> Void)?
    private(set) var progress: MechanicsProgress
    /// Capitalisation Overhead, pooled over recent rounds.
    private(set) var overhead: [CapitalisationOverhead.Method: CapitalisationOverhead.Estimate]
    /// What to practise next, from recent rounds.
    private(set) var recommendations: [MechanicsRecommendation]

    /// Live modifier state for the indicator and keyboard.
    private(set) var capsLockOn = false
    private(set) var heldShift: ShiftSide?
    /// The last checked character used the wrong technique; cleared by the next right one.
    private(set) var lastTechniqueMiss: CaseTechnique?
    /// Live technique validation for the round so far.
    private(set) var liveTechniqueChecked = 0
    private(set) var liveTechniqueCorrect = 0
    /// Capitalisation Lab pairing.
    private(set) var pending: PendingComparison?
    /// The comparison this round belongs to, and whether it is part 1 or 2.
    private(set) var currentComparison: (id: UUID, order: Int)?

    var showsKeyboard: Bool {
        didSet { defaults?.set(showsKeyboard, forKey: "mechanics.showsKeyboard") }
    }

    /// The keyboard layout in use, read at the start of each round.
    private(set) var layout: KeyboardLayoutInfo?
    @ObservationIgnored private let layoutProvider: () -> KeyboardLayoutInfo?

    /// Which symbols need Shift is only known on US QWERTY-compatible layouts.
    var judgesSymbols: Bool { layout?.isUSCompatible ?? false }

    @ObservationIgnored private var tracker = ModifierTracker()
    /// The observation for each character the engine accepted this round, in order.
    @ObservationIgnored private var strokes: [ObservedKeystroke] = []
    @ObservationIgnored private let store: TrainingStore?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var seeds: SeededGenerator
    @ObservationIgnored private var unsaved: [MechanicsEvent] = []
    @ObservationIgnored private var missCount = 0

    init(store: TrainingStore? = nil, defaults: UserDefaults? = nil, seed: UInt64 = .random(in: .min ... .max),
         layout: @escaping () -> KeyboardLayoutInfo? = KeyboardLayoutInfo.current) {
        let area = defaults?.string(forKey: "mechanics.area").flatMap(MechanicsArea.init(rawValue:)) ?? .shiftControl
        let progress = MechanicsProgress(events: store?.mechanicsEvents ?? [])
        let drill = progress.recommended(in: area)
        var seeds = SeededGenerator(seed: seed)
        let text = MechanicsCatalog.text(for: drill, seed: seeds.next())
        if drill.labCounterpart != nil { currentComparison = (UUID(), 1) }

        self.store = store
        self.defaults = defaults
        self.layoutProvider = layout
        self.layout = layout()
        self.area = area
        self.drill = drill
        self.progress = progress
        self.overhead = CapitalisationOverhead.estimates(from: (store?.mechanicsEvents ?? []).map(\.result))
        self.recommendations = MechanicsRecommender.recommendations(from: store?.mechanicsEvents ?? [], priority: .balanced)
        self.text = text
        self.engine = Self.makeEngine(text)
        self.seeds = seeds
        self.showsKeyboard = defaults?.object(forKey: "mechanics.showsKeyboard") as? Bool ?? true
    }

    // MARK: Derived

    var phase: TypingEngine.Phase { engine.phase }
    var metrics: PerformanceMetrics { PerformanceCalculator.metrics(for: engine.session(at: now)) }
    var drillProgress: MechanicsProgress.DrillProgress { progress.progress(drill) }

    var nextKey: Character? {
        guard phase != .finished, engine.position < engine.target.count else { return nil }
        return engine.target[engine.position]
    }

    /// What the next key needs from the modifiers, for guidance.
    var nextRule: TechniqueRule {
        guard nextKey != nil else { return .none }
        return rule(at: engine.position)
    }

    /// The drill's rule, minus symbol checks the layout makes unreliable.
    func rule(at position: Int) -> TechniqueRule {
        let rule = drill.rule(at: position, in: engine.target)
        if !judgesSymbols, engine.target.indices.contains(position),
           CaseRequirement.of(engine.target[position]) == .shiftedSymbol { return .none }
        return rule
    }

    /// Recommended Shift for the next key: the one on the other hand.
    /// Only where the drill requires Shift: elsewhere the method is the user's choice.
    var recommendedShift: ShiftSide? {
        guard let key = nextKey, nextRule == .shift else { return nil }
        switch FingerMap.hand(for: key) {
        case .left: return .right
        case .right: return .left
        case nil: return nil
        }
    }

    /// Caps Lock needs switching for the next key: on before a run, off after it.
    var capsLockNeedsToggle: Bool {
        guard let key = nextKey else { return false }
        if nextRule == .capsLock { return !capsLockOn }
        if capsLockOn, key.isLetter, key.isLowercase { return true }
        if capsLockOn, drill.wantedTechnique == .shift, key.isLetter { return true }
        return false
    }

    // MARK: Actions

    func select(_ area: MechanicsArea) {
        guard area != self.area else { return }
        self.area = area
        defaults?.set(area.rawValue, forKey: "mechanics.area")
        // Back in the Lab with a comparison half done: offer its other half.
        drill = (area == .capitalisationLab ? pending?.awaiting : nil) ?? progress.recommended(in: area)
        nextExercise()
    }

    func select(_ drill: MechanicsDrill) {
        guard drill != self.drill else { return }
        self.drill = drill
        area = drill.area
        nextExercise()
    }

    /// Settings ▸ Training ▸ Training priority: orders the suggestions.
    var priority: MechanicsRecommender.Priority = .balanced {
        didSet {
            guard priority != oldValue else { return }
            recommendations = MechanicsRecommender.recommendations(
                from: ((store?.mechanicsEvents ?? []) + unsaved).sorted { $0.date < $1.date }, priority: priority)
        }
    }

    /// Goes to the practice a recommendation points to.
    func follow(_ recommendation: MechanicsRecommendation) {
        if recommendation.area == .capitalisationLab {
            // The Lab picks the counterbalanced order (or a waiting half) itself.
            if area == .capitalisationLab { performLabStart() } else { select(.capitalisationLab) }
        } else if recommendation.drill == drill {
            nextExercise()
        } else {
            select(recommendation.drill)
        }
    }

    private func performLabStart() {
        drill = pending?.awaiting ?? progress.nextLabFirst
        nextExercise()
    }

    /// The suggestion to show while idle: the first that is not already on screen.
    var suggestion: MechanicsRecommendation? {
        recommendations.first { $0.area == .capitalisationLab ? area != .capitalisationLab : $0.drill != drill }
    }

    /// The same text again. Repeating a finished Lab half starts a new
    /// comparison on this passage, so no pair ever holds two attempts.
    func restart() {
        if summary != nil, currentComparison != nil {
            pending = nil
            currentComparison = (UUID(), 1)
        }
        engine = Self.makeEngine(text)
        resetRound()
    }

    func nextExercise() {
        if drill.labCounterpart != nil {
            if let pending, pending.awaiting == drill {
                text = pending.text
                currentComparison = (pending.id, 2)
            } else {
                pending = nil
                text = MechanicsCatalog.text(for: drill, seed: seeds.next())
                currentComparison = (UUID(), 1)
            }
        } else {
            currentComparison = nil
            text = MechanicsCatalog.text(for: drill, seed: seeds.next())
        }
        engine = Self.makeEngine(text)
        resetRound()
    }

    /// After a round: the other half of a Lab comparison, a new comparison
    /// (counterbalanced), or simply the next exercise.
    func performPrimaryAction() {
        if let pending, summary != nil {
            select(pending.awaiting)
        } else if summary?.comparison != nil {
            drill = progress.nextLabFirst
            nextExercise()
        } else {
            nextExercise()
        }
    }

    /// The label for the primary action after a round.
    var primaryActionTitle: String {
        if let pending, summary != nil { return "Continue: \(pending.awaiting.title), same passage" }
        if summary?.comparison != nil { return "New Comparison" }
        return "Next Exercise"
    }

    /// Modifier changes between key presses (Shift, Caps Lock, focus).
    func handleModifier(_ event: ModifierEvent) {
        tracker.apply(event)
        refreshModifierState()
    }

    func handle(_ key: KeyPress) -> Bool {
        guard !key.hasCommandOrControl else { return false }

        switch key.keyCode {
        case KeyPress.tab, KeyPress.escape:
            restart()
            return true
        case KeyPress.return, KeyPress.enter:
            guard phase == .finished else { return false }
            performPrimaryAction()
            return true
        case KeyPress.delete:
            apply(at: key.timestamp) { engine, time in
                if key.hasOption { engine.deleteWord(at: time) } else { engine.backspace(at: time) }
            }
            return true
        default:
            break
        }

        guard let character = key.printableCharacter, phase != .finished else { return false }
        let expected = nextKey
        let position = engine.position
        var accepted = false
        apply(at: key.timestamp) { engine, time in accepted = engine.insert(character, at: time) }
        if accepted {
            let stroke = tracker.keystroke(character, keyCode: key.keyCode, at: key.timestamp,
                                           isRepeat: key.isRepeat, modifiers: key.modifiers)
            strokes.append(stroke)
            refreshModifierState()
            if let expected, character == expected {
                let rule = rule(at: position)
                if rule != .none, stroke.technique != .unknown {
                    liveTechniqueChecked += 1
                    if rule.accepts(stroke.technique) {
                        liveTechniqueCorrect += 1
                        lastTechniqueMiss = nil
                    } else {
                        lastTechniqueMiss = stroke.technique
                    }
                }
            }
            if summary == nil, phase == .finished { finishRound() }
        }
        if let expected, character != expected {
            missCount += 1
            onMistake?()
            lastMiss = .init(expected: expected, typed: character, id: missCount)
        }
        return true
    }

    // MARK: Private

    private func apply(at time: MonotonicTime, _ change: (inout TypingEngine, MonotonicTime) -> Void) {
        guard phase != .finished else { return }
        change(&engine, time)
        now = max(now, time)
    }

    private func finishRound() {
        var result = MechanicsAnalyzer.analyze(engine.session(at: now), strokes: strokes, drill: drill,
                                               judgeSymbols: judgesSymbols)
        result.comparisonID = currentComparison?.id
        result.comparisonOrder = currentComparison?.order
        let wasSteady = drillProgress.isSteady
        let event = MechanicsEvent(drill: drill, result: result)
        if let store {
            do {
                try store.record(event)
                saveError = nil
            } catch {
                unsaved.append(event)
                saveError = error.localizedDescription
            }
        } else {
            unsaved.append(event)
        }
        let history = ((store?.mechanicsEvents ?? []) + unsaved).sorted { $0.date < $1.date }
        progress = MechanicsProgress(events: history)
        overhead = CapitalisationOverhead.estimates(from: history.map(\.result))
        recommendations = MechanicsRecommender.recommendations(from: history, priority: priority)
        var summary = RoundSummary(result: result, tips: MechanicsFeedback.tips(for: result, drill: drill),
                                   justSteadied: !wasSteady && drillProgress.isSteady)
        if let current = currentComparison, let counterpart = drill.labCounterpart {
            if current.order == 1 {
                pending = PendingComparison(id: current.id, text: text, awaiting: counterpart)
            } else {
                pending = nil
                summary.comparison = progress.comparisons.first { $0.id == current.id }
            }
        }
        self.summary = summary
    }

    private func refreshModifierState() {
        let caps = tracker.capsLock ?? false
        if caps != capsLockOn { capsLockOn = caps }
        let shift: ShiftSide? = switch (tracker.leftShift != nil, tracker.rightShift != nil) {
        case (true, true): .both
        case (true, false): .left
        case (false, true): .right
        case (false, false): tracker.unsidedShift != nil ? .both : nil
        }
        if shift != heldShift { heldShift = shift }
    }

    private func resetRound() {
        let current = layoutProvider()
        if current != layout { layout = current }
        now = 0
        summary = nil
        lastMiss = nil
        lastTechniqueMiss = nil
        liveTechniqueChecked = 0
        liveTechniqueCorrect = 0
        strokes = []
        tracker.clearHistory()
    }

    private static func makeEngine(_ text: String) -> TypingEngine {
        TypingEngine(target: text, configuration: .init(timeLimit: nil, finishesAtEndOfText: true))
    }
}
