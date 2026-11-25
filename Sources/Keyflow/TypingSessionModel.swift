import Foundation
import KeyflowCore
import Observation

/// Bridges the pure `TypingEngine` to the UI: owns the live session, feeds it
/// monotonic timestamps, keeps the text supplied, drives the clock, and saves
/// each finished session. One instance backs Practice, another backs Test.
@MainActor
@Observable
final class TypingSessionModel {
    enum Role: Sendable {
        case practice, test

        var durations: [Int] {
            switch self {
            case .practice: [15, 30, 60, 120, 300]
            case .test: [30, 60, 120]
            }
        }

        var defaultDuration: Int { self == .practice ? 30 : 60 }
        fileprivate var key: String { self == .practice ? "practice" : "test" }
    }

    /// Everything known about the session that just ended.
    struct Result {
        let metrics: PerformanceMetrics
        let analysis: SessionAnalysis
        /// Beat the previous best saved test of the same length.
        let isPersonalBest: Bool
        let wasSaved: Bool
    }

    let role: Role
    private(set) var engine: TypingEngine
    /// Monotonic time of the latest tick or keystroke; drives live stats.
    private(set) var now: MonotonicTime = 0
    private(set) var result: Result?
    private(set) var saveError: String?
    /// The passage as the user entered it (normalised only when used).
    private(set) var customText: String
    /// While the Custom Text editor is open, typing does not reach the session.
    var isEditingCustomText: Bool

    var durationSeconds: Int {
        didSet {
            guard durationSeconds != oldValue else { return }
            defaults?.set(durationSeconds, forKey: "\(role.key).duration")
            restart()
        }
    }

    /// Practice only; tests always use sentences.
    var mode: PracticeMode {
        didSet {
            guard mode != oldValue else { return }
            defaults?.set(mode.rawValue, forKey: "practice.mode")
            isEditingCustomText = mode == .customText && !hasCustomText
            restart()
        }
    }

    /// Called when a wrong character is typed (sound feedback).
    @ObservationIgnored var onMistake: (() -> Void)?

    /// Sets the length for the next session without cutting one short:
    /// a running session keeps its length and the new one applies after it.
    func setPreferredDuration(_ seconds: Int) {
        guard role.durations.contains(seconds) else { return }
        if phase == .running {
            pendingDuration = seconds
            defaults?.set(seconds, forKey: "\(role.key).duration")
        } else {
            durationSeconds = seconds
        }
    }

    @ObservationIgnored private var pendingDuration: Int?

    /// The length the next session will use.
    var preferredDuration: Int { pendingDuration ?? durationSeconds }
    @ObservationIgnored private let store: StatisticsStore?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var seeds: SeededGenerator
    @ObservationIgnored private var supply: TextSupply
    @ObservationIgnored private var timer: Timer?

    private static let initialCharacters = 320
    private static let refillCharacters = 200
    private static let refillThreshold = 160

    /// - Parameters:
    ///   - store: Where finished sessions are saved. `nil` disables saving.
    ///   - defaults: Where mode, duration and custom text are remembered. `nil` disables that.
    init(role: Role, store: StatisticsStore? = nil, defaults: UserDefaults? = nil,
         durationSeconds: Int? = nil, mode: PracticeMode? = nil,
         seed: UInt64 = .random(in: .min ... .max)) {
        let savedDuration = defaults?.integer(forKey: "\(role.key).duration") ?? 0
        let duration = durationSeconds
            ?? (role.durations.contains(savedDuration) ? savedDuration : role.defaultDuration)
        let savedMode = defaults?.string(forKey: "practice.mode").flatMap(PracticeMode.init(rawValue:))
        let mode = role == .test ? .sentences : (mode ?? savedMode ?? .commonWords)
        let customText = role == .practice ? (defaults?.string(forKey: "practice.customText") ?? "") : ""

        var seeds = SeededGenerator(seed: seed)
        var supply = TextSupply(mode: mode, customText: customText, seed: seeds.next())

        self.role = role
        self.store = store
        self.defaults = defaults
        self.durationSeconds = duration
        self.mode = mode
        self.customText = customText
        self.isEditingCustomText = mode == .customText && TextNormalizer.normalize(customText).isEmpty
        self.engine = Self.makeEngine(duration: duration, supply: &supply)
        self.supply = supply
        self.seeds = seeds
    }

    // MARK: Derived state

    var phase: TypingEngine.Phase { engine.phase }
    var kind: SessionKind { role == .test ? .test : .practice(mode) }
    var metrics: PerformanceMetrics { PerformanceCalculator.metrics(for: engine.session(at: now)) }
    var remaining: TimeInterval { engine.remaining(at: now) ?? 0 }
    var hasCustomText: Bool { !TextNormalizer.normalize(customText).isEmpty }

    // MARK: Actions

    func restart() {
        if let pending = pendingDuration {
            pendingDuration = nil
            if pending != durationSeconds { durationSeconds = pending; return }  // didSet restarts
        }
        stopTimer()
        supply = TextSupply(mode: mode, customText: customText, seed: seeds.next())
        engine = Self.makeEngine(duration: durationSeconds, supply: &supply)
        now = 0
        result = nil
        saveError = nil
    }

    /// Replaces the Custom Text passage, closes the editor, and starts over.
    func setCustomText(_ text: String) {
        customText = text
        defaults?.set(text, forKey: "practice.customText")
        isEditingCustomText = false
        restart()
    }

    /// Handles a key press. Returns true when the key was consumed.
    func handle(_ key: KeyPress) -> Bool {
        guard !key.hasCommandOrControl, !isEditingCustomText else { return false }

        switch key.keyCode {
        case KeyPress.tab, KeyPress.escape:
            restart()
            return true
        case KeyPress.return, KeyPress.enter:
            guard phase == .finished else { return false }
            restart()
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
        let expected = phase != .finished && engine.position < engine.target.count ? engine.target[engine.position] : nil
        apply(at: key.timestamp) { engine, time in engine.insert(character, at: time) }
        if let expected, character != expected { onMistake?() }
        return true
    }

    // MARK: Private

    private func apply(at time: MonotonicTime, _ change: (inout TypingEngine, MonotonicTime) -> Void) {
        guard phase != .finished else { return }
        change(&engine, time)
        now = max(now, time)
        topUpIfNeeded()
        sessionDidAdvance()
    }

    private func tick() {
        now = ProcessInfo.processInfo.systemUptime
        engine.tick(at: now)
        sessionDidAdvance()
    }

    private func topUpIfNeeded() {
        guard supply.isEndless, engine.target.count - engine.position < Self.refillThreshold else { return }
        engine.appendTarget(" " + supply.next(atLeast: Self.refillCharacters))
    }

    private func sessionDidAdvance() {
        switch phase {
        case .running:
            startTimerIfNeeded()
        case .finished:
            stopTimer()
            if result == nil { finalize() }
        case .idle:
            stopTimer()
        }
    }

    /// Runs once per session, the moment it ends: analyse, then save.
    private func finalize() {
        let session = engine.session(at: now)
        let metrics = PerformanceCalculator.metrics(for: session)
        var isPersonalBest = false
        var wasSaved = false

        if let store {
            let previousBest = role == .test ? store.personalBest(of: kind, timeLimit: durationSeconds) : nil
            do {
                try store.record(session, kind: kind, timeLimit: durationSeconds)
                wasSaved = true
                if let previousBest { isPersonalBest = metrics.netWPM > previousBest.metrics.netWPM }
            } catch {
                saveError = error.localizedDescription
            }
        }
        result = Result(metrics: metrics, analysis: SessionAnalyzer.analyze(session),
                        isPersonalBest: isPersonalBest, wasSaved: wasSaved)
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private static func makeEngine(duration: Int, supply: inout TextSupply) -> TypingEngine {
        TypingEngine(
            target: supply.next(atLeast: initialCharacters),
            configuration: .init(timeLimit: TimeInterval(duration), finishesAtEndOfText: !supply.isEndless)
        )
    }
}
