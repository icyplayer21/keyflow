import Foundation
import KeyflowCore
import Observation

/// Drives Learn ▸ Key Repetition: choose a letter and a number of
/// repetitions, press it that many times, see the result. The counting
/// rules live in `KeyRepetitionCounter` (KeyflowCore).
///
/// Only completed sessions are saved. A session in progress is kept when
/// the user goes elsewhere in Keyflow or switches apps (it pauses), and is
/// only ended by Restart, Exit or choosing another key, after asking.
@MainActor
@Observable
final class KeyRepetitionModel {
    enum Stage: Equatable {
        case setup
        case training
        case complete(KeyRepetitionEvent)
    }

    /// What a press just did, for brief feedback. `id` changes every press.
    struct Feedback: Equatable {
        let outcome: KeyRepetitionCounter.Outcome
        /// The letter typed, for a mistake.
        let typed: Character?
        let id: Int
    }

    private(set) var stage: Stage = .setup
    private(set) var counter: KeyRepetitionCounter
    private(set) var feedback: Feedback?
    /// The last few attempts, newest last (at most `recentLimit`), drawn
    /// instead of every press so long sessions stay calm.
    private(set) var recent: [Feedback] = []
    private(set) var saveError: String?
    /// The explosion is playing, before the results. The session is already saved.
    private(set) var showsBurst = false
    /// How full the letter was on the final press (0...1). Sets the size of
    /// the explosion only; the saved result does not depend on it.
    private(set) var finalLevel = 1.0
    /// The letter's display size. Drains when the user slows down; the count never does.
    private(set) var energy = KeyRepetitionEnergy()

    /// Lower-case a–z.
    private(set) var letter: Character {
        didSet { defaults?.set(String(letter), forKey: "keyRepetition.letter") }
    }
    /// Always within `KeyRepetitionCounter.goalRange`; change it with `setGoal`.
    private(set) var goal: Int {
        didSet { defaults?.set(goal, forKey: "keyRepetition.goal") }
    }
    var mode: KeyRepetitionMode {
        didSet { defaults?.set(mode.rawValue, forKey: "keyRepetition.mode") }
    }
    var showsKeyboard: Bool {
        didSet { defaults?.set(showsKeyboard, forKey: "keyRepetition.showsKeyboard") }
    }
    /// Called on a mistake (sound, when Settings ▸ Feedback has it on).
    @ObservationIgnored var onMistake: (() -> Void)?

    static let recentLimit = 12

    @ObservationIgnored private let store: TrainingStore?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var unsaved: [KeyRepetitionEvent] = []
    @ObservationIgnored private var pressCount = 0
    @ObservationIgnored private let clock: () -> MonotonicTime

    init(store: TrainingStore? = nil, defaults: UserDefaults? = nil,
         clock: @escaping () -> MonotonicTime = { ProcessInfo.processInfo.systemUptime }) {
        self.store = store
        self.defaults = defaults
        self.clock = clock
        let letter = defaults?.string(forKey: "keyRepetition.letter")?.first.flatMap(KeyRepetitionCounter.normalize) ?? "f"
        let savedGoal = defaults?.integer(forKey: "keyRepetition.goal") ?? 0
        let goal = savedGoal > 0 ? KeyRepetitionCounter.clampGoal(savedGoal) : KeyRepetitionCounter.defaultGoal
        self.letter = letter
        self.goal = goal
        self.mode = defaults?.string(forKey: "keyRepetition.mode").flatMap(KeyRepetitionMode.init(rawValue:)) ?? .continuous
        self.showsKeyboard = defaults?.object(forKey: "keyRepetition.showsKeyboard") as? Bool ?? true
        self.counter = KeyRepetitionCounter(letter: letter, goal: goal)!
    }

    // MARK: Derived

    /// "P".
    var displayLetter: String { String(letter).uppercased() }
    /// "Right pinky", from the standard QWERTY map. A recommendation only.
    var fingerName: String { Self.fingerName(for: letter) }

    static func fingerName(for letter: Character) -> String {
        guard let finger = FingerMap.finger(for: letter), let hand = finger.hand else { return "" }
        return "\(hand == .left ? "Left" : "Right") \(finger.name.lowercased())"
    }

    var isPaused: Bool { counter.phase == .paused }
    /// A session with presses counted that has not finished.
    var hasProgress: Bool { stage == .training && counter.attempts > 0 && !counter.isFinished }

    /// Completed sessions, saved or (if saving failed) kept for this launch.
    var events: [KeyRepetitionEvent] { (store?.keyRepetitionEvents ?? []) + unsaved }
    var history: KeyRepetitionHistory { KeyRepetitionHistory(events: events) }

    /// Seconds of active practice so far.
    func duration(at time: MonotonicTime? = nil) -> TimeInterval { counter.duration(at: time ?? clock()) }
    /// How full the letter looks right now, 0...1.
    func letterLevel(at time: MonotonicTime? = nil) -> Double { energy.level(at: time ?? clock()) }

    // MARK: Setup

    func select(_ letter: Character) {
        guard stage == .setup, let normalized = KeyRepetitionCounter.normalize(letter) else { return }
        self.letter = normalized
    }

    /// A preset or a custom number, kept within 5...500.
    func setGoal(_ value: Int) {
        guard stage == .setup else { return }
        let clamped = KeyRepetitionCounter.clampGoal(value)
        if clamped != goal { goal = clamped }
    }

    func start() {
        counter = KeyRepetitionCounter(letter: letter, goal: goal)!
        feedback = nil
        recent = []
        showsBurst = false
        energy = KeyRepetitionEnergy()
        finalLevel = 1
        stage = .training
    }

    // MARK: Training

    func pause() {
        guard stage == .training else { return }
        let now = clock()
        counter.pause(at: now)
        if isPaused { energy.pause(at: now) }
    }

    func resume() {
        guard stage == .training else { return }
        let now = clock()
        counter.resume(at: now)
        if !isPaused { energy.resume(at: now) }
    }

    func togglePause() { isPaused ? resume() : pause() }

    /// The same key and goal from zero. The unfinished session is not saved.
    func restart() {
        guard stage != .setup else { return }
        start()
    }

    /// Back to choosing a key. An unfinished session is not saved.
    func exit() {
        stage = .setup
        showsBurst = false
        feedback = nil
        recent = []
    }

    /// The explosion is over, or was skipped: on to the results.
    func finishBurst() {
        if showsBurst { showsBurst = false }
    }

    /// Handles a key press. Returns true when the key was used.
    func handle(_ key: KeyPress) -> Bool {
        guard !key.hasCommandOrControl else { return false }
        switch stage {
        case .setup:
            if key.keyCode == KeyPress.return || key.keyCode == KeyPress.enter { start(); return true }
            // Pressing a letter chooses it.
            guard let character = key.printableCharacter, !key.isRepeat,
                  let normalized = KeyRepetitionCounter.normalize(character) else { return false }
            select(normalized)
            return true
        case .complete:
            if key.keyCode == KeyPress.return || key.keyCode == KeyPress.enter {
                // During the explosion, Return only skips to the results.
                if showsBurst { finishBurst() } else { start() }
                return true
            }
            // Extra presses right after the goal are swallowed, so a stray
            // letter never reaches anything else in the window.
            return key.printableCharacter != nil
        case .training:
            break
        }

        switch key.keyCode {
        case KeyPress.escape:
            togglePause()
            return true
        case KeyPress.tab:
            restart()
            return true
        default:
            break
        }
        // Modifier-only changes never arrive here; keys that type nothing are not attempts.
        guard let character = key.printableCharacter else { return false }
        let outcome = counter.press(character, isRepeat: key.isRepeat, at: key.timestamp)
        guard outcome != .ignored else { return true }
        if outcome == .correct {
            energy.press(earned: Double(counter.correct) / Double(counter.goal), at: key.timestamp)
        }
        pressCount += 1
        let note = Feedback(outcome: outcome, typed: outcome == .incorrect ? character : nil, id: pressCount)
        feedback = note
        recent.append(note)
        if recent.count > Self.recentLimit { recent.removeFirst(recent.count - Self.recentLimit) }
        if outcome == .incorrect { onMistake?() }
        if counter.isFinished { finish(at: key.timestamp) }
        return true
    }

    private func finish(at time: MonotonicTime) {
        finalLevel = energy.level(at: time)
        let event = KeyRepetitionEvent(result: counter.result(mode: mode, at: time))
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
        showsBurst = true
        stage = .complete(event)
    }
}
