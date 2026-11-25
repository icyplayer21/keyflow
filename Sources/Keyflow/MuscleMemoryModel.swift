import Foundation
import KeyflowCore
import Observation

/// Drives the Muscle Memory section: the current category, stage and
/// exercise, the live typing engine, and saving each completed round.
@MainActor
@Observable
final class MuscleMemoryModel {
    /// A wrong keystroke, for the keyboard's error flash.
    struct KeyMiss: Equatable {
        let expected: Character
        let typed: Character
        let id: Int
    }

    struct RoundSummary {
        let result: RoundResult
        let progress: StageProgress
        /// This round completed mastery of the stage.
        let justMastered: Bool
    }

    private(set) var category: TrainingCategory
    private(set) var stage: TrainingStage
    private(set) var exercise: Exercise
    private(set) var engine: TypingEngine
    private(set) var now: MonotonicTime = 0
    private(set) var summary: RoundSummary?
    private(set) var saveError: String?
    private(set) var lastMiss: KeyMiss?
    /// Called when a wrong character is typed (sound feedback).
    @ObservationIgnored var onMistake: (() -> Void)?
    private(set) var tracker: MasteryTracker

    var showsKeyboard: Bool {
        didSet { defaults?.set(showsKeyboard, forKey: "muscleMemory.showsKeyboard") }
    }

    @ObservationIgnored private let store: TrainingStore?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var seeds: SeededGenerator
    /// Events not in the store: everything when there is no store, or rounds that failed to save.
    @ObservationIgnored private var unsavedEvents: [TrainingEvent] = []
    @ObservationIgnored private var missCount = 0

    init(store: TrainingStore? = nil, defaults: UserDefaults? = nil, seed: UInt64 = .random(in: .min ... .max)) {
        let savedCategory = defaults?.string(forKey: "muscleMemory.category").flatMap(TrainingCategory.init(rawValue:))
        let category = savedCategory ?? .homeRow
        let tracker = MasteryTracker(events: store?.events ?? [])
        let stage = tracker.currentStage(category)
        var seeds = SeededGenerator(seed: seed)
        let exercise = Self.generate(category: category, stage: stage, tracker: tracker, seed: seeds.next())

        self.store = store
        self.defaults = defaults
        self.category = category
        self.stage = stage
        self.tracker = tracker
        self.exercise = exercise
        self.engine = Self.makeEngine(exercise)
        self.seeds = seeds
        self.showsKeyboard = defaults?.object(forKey: "muscleMemory.showsKeyboard") as? Bool ?? true
    }

    // MARK: Derived state

    var phase: TypingEngine.Phase { engine.phase }
    var metrics: PerformanceMetrics { PerformanceCalculator.metrics(for: engine.session(at: now)) }
    var stageProgress: StageProgress { tracker.progress(category, stage) }
    var canSkipStage: Bool { tracker.status(category, stage) == .available }

    func status(of stage: TrainingStage) -> StageStatus { tracker.status(category, stage) }

    /// The character to type next, or `nil` once the round is over.
    var nextKey: Character? {
        guard phase != .finished, engine.position < engine.target.count else { return nil }
        return engine.target[engine.position]
    }

    /// The next stage, once the current one is mastered.
    var nextStageToContinue: TrainingStage? {
        guard stageProgress.isMastered, let next = stage.next, status(of: next) != .locked else { return nil }
        return next
    }

    // MARK: Actions

    func select(_ category: TrainingCategory) {
        guard category != self.category else { return }
        self.category = category
        defaults?.set(category.rawValue, forKey: "muscleMemory.category")
        stage = tracker.currentStage(category)
        nextExercise()
    }

    func select(_ stage: TrainingStage) {
        guard status(of: stage) != .locked else { return }
        self.stage = stage
        nextExercise()
    }

    /// Starts the same exercise again from the beginning.
    func restart() {
        engine = Self.makeEngine(exercise)
        resetRound()
    }

    /// Starts a freshly generated exercise for the current stage.
    func nextExercise() {
        exercise = Self.generate(category: category, stage: stage, tracker: tracker, seed: seeds.next())
        engine = Self.makeEngine(exercise)
        resetRound()
    }

    func continueToNextStage() {
        if let next = nextStageToContinue { stage = next }
        nextExercise()
    }

    /// After a round: move on to the next stage if this one is mastered, otherwise a new exercise.
    func performPrimaryAction() {
        if nextStageToContinue != nil { continueToNextStage() } else { nextExercise() }
    }

    /// Marks the current stage as skipped (never as mastered) and moves on.
    func skipStage() {
        guard canSkipStage else { return }
        save(TrainingEvent(category: category, stage: stage, kind: .skip))
        if let next = stage.next { stage = next }
        nextExercise()
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
            lastMiss = KeyMiss(expected: expected, typed: character, id: missCount)
        }
        return true
    }

    // MARK: Private

    private func apply(at time: MonotonicTime, _ change: (inout TypingEngine, MonotonicTime) -> Void) {
        guard phase != .finished else { return }
        change(&engine, time)
        now = max(now, time)
        if phase == .finished, summary == nil { finishRound() }
    }

    private func finishRound() {
        let result = RoundResult(session: engine.session(at: now))
        let wasMastered = stageProgress.isMastered
        save(TrainingEvent(category: category, stage: stage, kind: .round(result)))
        let progress = stageProgress
        summary = RoundSummary(result: result, progress: progress, justMastered: !wasMastered && progress.isMastered)
    }

    private func save(_ event: TrainingEvent) {
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
        tracker = MasteryTracker(events: (store?.events ?? []) + unsavedEvents)
    }

    private func resetRound() {
        now = 0
        summary = nil
        lastMiss = nil
    }

    private static func generate(category: TrainingCategory, stage: TrainingStage,
                                 tracker: MasteryTracker, seed: UInt64) -> Exercise {
        ExerciseGenerator.exercise(
            category: category,
            stage: stage,
            qualifyingRounds: tracker.progress(category, stage).qualifyingRounds,
            focus: tracker.adaptive(for: category).focusItems(),
            seed: seed
        )
    }

    private static func makeEngine(_ exercise: Exercise) -> TypingEngine {
        TypingEngine(target: exercise.text, configuration: .init(timeLimit: nil, finishesAtEndOfText: true))
    }
}
