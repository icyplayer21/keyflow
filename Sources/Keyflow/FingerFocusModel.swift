import Foundation
import KeyflowCore
import Observation

/// Drives Finger Focus: the chosen finger and level, a short set of rounds
/// with optional rests between them, the live typing engine, and saving
/// every completed round.
@MainActor
@Observable
final class FingerFocusModel {
    static let setSizes = [3, 5, 8]
    static let restOptions = [0, 10, 20, 30]

    /// A finished finger check, with the comparison against the check before it.
    struct CheckSummary {
        let event: FingerAssessmentEvent
        /// `nil` for the first check of this target: it becomes the baseline.
        let comparison: FingerAssessmentComparison?
    }

    struct RoundSummary {
        let result: RoundResult
        /// The last round of the set.
        let completesSet: Bool
    }

    private(set) var target: FingerFocusTarget
    private(set) var level: FingerFocusLevel
    private(set) var exercise: FingerFocusExercise
    private(set) var engine: TypingEngine
    private(set) var now: MonotonicTime = 0
    private(set) var summary: RoundSummary?
    private(set) var saveError: String?
    private(set) var lastMiss: MuscleMemoryModel.KeyMiss?
    /// Called when a wrong character is typed (sound feedback).
    @ObservationIgnored var onMistake: (() -> Void)?
    private(set) var tracker: FingerFocusTracker
    /// 1-based position of the current round in the set.
    private(set) var roundInSet = 1
    /// Results of the rounds completed in this set.
    private(set) var setResults: [RoundResult] = []
    /// Seconds left of the rest after a round, while resting.
    private(set) var restRemaining: Int?
    /// True while a finger check (baseline or retest) is on screen instead of training.
    private(set) var isCheck = false
    private(set) var checkSummary: CheckSummary?

    /// Rounds per set ("repetitions").
    var roundsPerSet: Int {
        didSet { defaults?.set(roundsPerSet, forKey: "fingerFocus.roundsPerSet") }
    }

    /// Rest between rounds in seconds; 0 turns rests off.
    var restSeconds: Int {
        didSet { defaults?.set(restSeconds, forKey: "fingerFocus.restSeconds") }
    }

    var showsKeyboard: Bool {
        didSet { defaults?.set(showsKeyboard, forKey: "fingerFocus.showsKeyboard") }
    }

    @ObservationIgnored private let store: TrainingStore?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var seeds: SeededGenerator
    @ObservationIgnored private var unsavedEvents: [FingerFocusEvent] = []
    @ObservationIgnored private var unsavedChecks: [FingerAssessmentEvent] = []
    @ObservationIgnored private var missCount = 0
    @ObservationIgnored private var restTask: Task<Void, Never>?

    init(store: TrainingStore? = nil, defaults: UserDefaults? = nil, seed: UInt64 = .random(in: .min ... .max)) {
        let target = defaults?.string(forKey: "fingerFocus.target").flatMap(FingerFocusTarget.init(rawValue:)) ?? .leftPinky
        let tracker = FingerFocusTracker(events: store?.fingerFocusEvents ?? [])
        let level = tracker.recommendedLevel(target)
        var seeds = SeededGenerator(seed: seed)
        let exercise = Self.generate(target: target, level: level, tracker: tracker, seed: seeds.next())

        self.store = store
        self.defaults = defaults
        self.target = target
        self.level = level
        self.tracker = tracker
        self.exercise = exercise
        self.engine = Self.makeEngine(exercise)
        self.seeds = seeds
        let savedSize = defaults?.integer(forKey: "fingerFocus.roundsPerSet") ?? 0
        self.roundsPerSet = savedSize > 0 ? savedSize : 5
        self.restSeconds = max(0, defaults?.integer(forKey: "fingerFocus.restSeconds") ?? 0)
        self.showsKeyboard = defaults?.object(forKey: "fingerFocus.showsKeyboard") as? Bool ?? true
    }

    // MARK: Derived state

    var phase: TypingEngine.Phase { engine.phase }
    var metrics: PerformanceMetrics { PerformanceCalculator.metrics(for: engine.session(at: now)) }
    var levelProgress: FingerFocusTracker.LevelProgress { tracker.progress(target, level) }
    var recommendedLevel: FingerFocusLevel { tracker.recommendedLevel(target) }
    var recommendations: [FingerFocusRecommendation] { tracker.recommendations(target) }
    var keyStats: [FingerKeyStat] { tracker.keyStats(target) }
    var isSetComplete: Bool { summary?.completesSet == true }

    /// Finger checks for the current target, oldest first.
    var checks: [FingerAssessmentEvent] {
        ((store?.assessmentEvents ?? []) + unsavedChecks).filter { $0.target == target }.sorted { $0.date < $1.date }
    }

    /// "Baseline Check" before the first check of a target, "Retest" after.
    var checkTitle: String { checks.isEmpty ? "Baseline Check" : "Retest This Finger" }

    /// The character to type next, or `nil` once the round is over.
    var nextKey: Character? {
        guard phase != .finished, engine.position < engine.target.count else { return nil }
        return engine.target[engine.position]
    }

    /// Accuracy over every keystroke of the rounds completed in this set.
    var setAccuracy: Double? {
        let keystrokes = setResults.reduce(0) { $0 + $1.keystrokes }
        guard keystrokes > 0 else { return nil }
        return Double(setResults.reduce(0) { $0 + $1.correctKeystrokes }) / Double(keystrokes)
    }

    // MARK: Actions

    func select(_ target: FingerFocusTarget) {
        guard target != self.target else { return }
        isCheck = false
        self.target = target
        defaults?.set(target.rawValue, forKey: "fingerFocus.target")
        level = tracker.recommendedLevel(target)
        startNewSet()
    }

    func select(_ level: FingerFocusLevel) {
        guard level != self.level || isCheck else { return }
        isCheck = false
        self.level = level
        startNewSet()
    }

    /// Starts the same exercise again from the beginning. Repeating a
    /// finished round replaces it in the set (it stays in history).
    func restart() {
        // A finished check is never retyped: a retest must not reuse text.
        if isCheck, checkSummary != nil { nextExercise(); return }
        if summary != nil, !setResults.isEmpty, !isCheck { setResults.removeLast() }
        engine = Self.makeEngine(exercise)
        resetRound()
    }

    /// Opens training for a target, as when arriving from Progress: ends any
    /// check and starts a fresh set even if the target is already selected.
    func open(_ target: FingerFocusTarget) {
        isCheck = false
        if target == self.target { startNewSet() } else { select(target) }
    }

    /// Starts a finger check: one passage, comparable to earlier checks but
    /// never the same text. It is saved and compared, not counted as training.
    func startCheck() {
        isCheck = true
        nextExercise()
    }

    /// Back from a check to training, at a new set.
    func endCheck() {
        isCheck = false
        startNewSet()
    }

    /// A freshly generated exercise in place of the current round.
    func nextExercise() {
        exercise = isCheck
            ? FingerFocusExercise(target: target, level: .words, text: FingerAssessment.text(for: target, seed: seeds.next()))
            : Self.generate(target: target, level: level, tracker: tracker, seed: seeds.next())
        engine = Self.makeEngine(exercise)
        resetRound()
    }

    /// Starts the set over from round 1.
    func startNewSet() {
        roundInSet = 1
        setResults = []
        nextExercise()
    }

    /// After a round: on to the next round (ending any rest early), or a new set.
    func performPrimaryAction() {
        if isCheck {
            if checkSummary != nil { endCheck() } else { nextExercise() }
            return
        }
        guard summary != nil else { nextExercise(); return }
        if isSetComplete {
            startNewSet()
        } else {
            roundInSet += 1
            nextExercise()
        }
    }

    /// Ends the rest early without starting the next round.
    func skipRest() {
        cancelRest()
    }

    /// Handles a key press. Returns true when the key was consumed.
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

        guard let character = key.printableCharacter else { return false }
        let expected = nextKey
        apply(at: key.timestamp) { engine, time in engine.insert(character, at: time) }
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
        if phase == .finished, summary == nil, checkSummary == nil {
            if isCheck { finishCheck() } else { finishRound() }
        }
    }

    private func finishRound() {
        let result = RoundResult(session: engine.session(at: now))
        save(FingerFocusEvent(target: target, level: level, result: result))
        setResults.append(result)
        let completesSet = roundInSet >= max(1, roundsPerSet)
        summary = RoundSummary(result: result, completesSet: completesSet)
        if !completesSet, restSeconds > 0 { startRest() }
    }

    private func finishCheck() {
        let event = FingerAssessmentEvent(target: target,
                                          result: FingerAssessment.result(for: engine.session(at: now), target: target))
        if let store {
            do {
                try store.record(event)
                saveError = nil
            } catch {
                unsavedChecks.append(event)
                saveError = error.localizedDescription
            }
        } else {
            unsavedChecks.append(event)
        }
        let comparison = FingerAssessment.latestComparison(
            for: target, assessments: checks, training: (store?.fingerFocusEvents ?? []) + unsavedEvents)
        checkSummary = CheckSummary(event: event, comparison: comparison)
    }

    private func startRest() {
        cancelRest()
        restRemaining = restSeconds
        restTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, let remaining = self.restRemaining else { return }
                if remaining <= 1 {
                    self.restRemaining = nil
                    self.performPrimaryAction()
                    return
                }
                self.restRemaining = remaining - 1
            }
        }
    }

    private func cancelRest() {
        restTask?.cancel()
        restTask = nil
        restRemaining = nil
    }

    private func save(_ event: FingerFocusEvent) {
        if let store {
            do {
                try store.record(event)
                saveError = nil
            } catch {
                unsavedEvents.append(event)
                saveError = error.localizedDescription
            }
        } else {
            unsavedEvents.append(event)
        }
        tracker = FingerFocusTracker(events: (store?.fingerFocusEvents ?? []) + unsavedEvents)
    }

    private func resetRound() {
        cancelRest()
        now = 0
        summary = nil
        checkSummary = nil
        lastMiss = nil
    }

    private static func generate(target: FingerFocusTarget, level: FingerFocusLevel,
                                 tracker: FingerFocusTracker, seed: UInt64) -> FingerFocusExercise {
        FingerFocusGenerator.exercise(
            target: target,
            level: level,
            complexity: tracker.complexity(target, level),
            focus: tracker.adaptive(for: target).focusItems(),
            seed: seed
        )
    }

    private static func makeEngine(_ exercise: FingerFocusExercise) -> TypingEngine {
        TypingEngine(target: exercise.text, configuration: .init(timeLimit: nil, finishesAtEndOfText: true))
    }
}
