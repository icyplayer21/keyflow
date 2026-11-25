import Foundation
import KeyflowCore
import Observation

/// Drives Learn ▸ Daily Flow: one guided session of warm-up, focus words and
/// real sentences, with the next key shown only after a pause. The rules live
/// in KeyflowCore/DailyFlow; the typing engine is used as it is.
@MainActor
@Observable
final class DailyFlowModel {
    enum Stage: Equatable {
        case start
        case flowing
        case complete(DailyFlowHistory.Session)
    }

    private(set) var stage: Stage = .start
    private(set) var plan: DailyFlowPlan
    private(set) var segment: DailyFlowSegment = .warmUp
    private(set) var engine = TypingEngine(target: "")
    private(set) var focusKeys: [Character] = []
    /// True until there is enough history to choose keys from it.
    private(set) var usesStarterKeys = true
    private(set) var isPaused = false
    private(set) var isHintShowing = false
    private(set) var activeSeconds: TimeInterval = 0
    private(set) var saveError: String?
    /// Changes whenever the pause before a hint starts over.
    private(set) var activityID = 0

    /// Off: the next key is never shown.
    var showsKeyboard: Bool {
        didSet {
            defaults?.set(showsKeyboard, forKey: "dailyFlow.showsHints")
            if !showsKeyboard { isHintShowing = false }
        }
    }
    @ObservationIgnored var onMistake: (() -> Void)?

    @ObservationIgnored private let store: TrainingStore?
    @ObservationIgnored private let statistics: StatisticsStore?
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let clock: () -> MonotonicTime
    @ObservationIgnored private var generator: DailyFlowGenerator
    @ObservationIgnored private var pace = DailyFlowPace()
    @ObservationIgnored private var unsaved: [DailyFlowEvent] = []
    @ObservationIgnored private var sessionID = UUID()
    @ObservationIgnored private var sessionRounds = 0
    @ObservationIgnored private var lastKeyTime: MonotonicTime?
    @ObservationIgnored private var lastActivity: MonotonicTime = 0
    @ObservationIgnored private var passageActive: TimeInterval = 0
    @ObservationIgnored private var hintedPositions = Set<Int>()

    init(store: TrainingStore? = nil, statistics: StatisticsStore? = nil, defaults: UserDefaults? = nil,
         seed: UInt64 = .random(in: .min ... .max),
         clock: @escaping () -> MonotonicTime = { ProcessInfo.processInfo.systemUptime }) {
        self.store = store
        self.statistics = statistics
        self.defaults = defaults
        self.clock = clock
        generator = DailyFlowGenerator(seed: seed)
        plan = DailyFlowPlan(minutes: defaults?.integer(forKey: "dailyFlow.minutes") ?? DailyFlowPlan.defaultMinutes)
        showsKeyboard = defaults?.object(forKey: "dailyFlow.showsHints") as? Bool ?? true
        refreshFocus()
    }

    // MARK: Derived

    var events: [DailyFlowEvent] { (store?.dailyFlowEvents ?? []) + unsaved }
    var history: DailyFlowHistory { DailyFlowHistory(events: events) }
    var hasPractisedToday: Bool { history.hasPractised(on: .now) }
    var fraction: Double { plan.fraction(atActive: activeSeconds) }
    var hintDelay: TimeInterval { pace.delay }
    var hintsThisPassage: Int { hintedPositions.count }

    var nextKey: Character? {
        guard stage == .flowing, engine.phase != .finished, engine.position < engine.target.count else { return nil }
        return engine.target[engine.position]
    }

    // MARK: Actions

    func setMinutes(_ minutes: Int) {
        guard stage == .start else { return }
        plan = DailyFlowPlan(minutes: minutes)
        defaults?.set(plan.minutes, forKey: "dailyFlow.minutes")
    }

    /// Recomputes today's focus keys from recent practice.
    func refreshFocus() {
        var counts: [String: ErrorCount] = [:]
        func add(_ keys: [String: ErrorCount]) {
            for (key, count) in keys { counts[key, default: ErrorCount()] = counts[key, default: ErrorCount()] + count }
        }
        for session in statistics?.analyzedSessions(limit: 8) ?? [] {
            for key in session.analysis.keys {
                add([String(key.character): ErrorCount(attempts: key.attempts, errors: key.errors)])
            }
        }
        for event in (store?.events ?? []).suffix(20) { if let round = event.round { add(round.keys) } }
        for event in events.suffix(20) { add(event.round.result.keys) }
        let keys = DailyFlowFocus.keys(from: counts)
        usesStarterKeys = keys.isEmpty
        focusKeys = keys.isEmpty ? DailyFlowFocus.starterKeys : keys
    }

    func start() {
        refreshFocus()
        sessionID = UUID()
        sessionRounds = 0
        activeSeconds = 0
        pace = DailyFlowPace()
        lastKeyTime = nil
        isPaused = false
        segment = .warmUp
        saveError = nil
        loadPassage()
        stage = .flowing
    }

    func pause() {
        guard stage == .flowing, !isPaused else { return }
        isPaused = true
        isHintShowing = false
        lastKeyTime = nil
        activityID += 1
    }

    func resume() {
        guard stage == .flowing, isPaused else { return }
        isPaused = false
        noteActivity(at: clock())
    }

    func togglePause() { isPaused ? resume() : pause() }

    /// The same passage from its start. The unfinished attempt is not saved.
    func restartPassage() {
        guard stage == .flowing else { return }
        activeSeconds = max(0, activeSeconds - passageActive)
        engine = TypingEngine(target: String(engine.target))
        resetPassageState()
    }

    /// Ends now. Finished passages are already saved; the one under way is not.
    func endEarly() {
        guard stage == .flowing else { return }
        finishSession()
    }

    /// Back to the start screen.
    func done() {
        refreshFocus()
        stage = .start
    }

    /// Shows the hint if the pause has lasted long enough.
    @discardableResult
    func revealHintIfDue(at time: MonotonicTime? = nil) -> Bool {
        guard stage == .flowing, !isPaused, showsKeyboard, !isHintShowing, nextKey != nil,
              (time ?? clock()) - lastActivity >= pace.delay else { return false }
        isHintShowing = true
        hintedPositions.insert(engine.position)
        return true
    }

    func handle(_ key: KeyPress) -> Bool {
        guard !key.hasCommandOrControl else { return false }
        let isReturn = key.keyCode == KeyPress.return || key.keyCode == KeyPress.enter
        switch stage {
        case .start:
            if isReturn { start(); return true }
            // Swallowed so a stray letter never reaches anything else in the window.
            return key.printableCharacter != nil
        case .complete:
            if isReturn { done(); return true }
            return key.printableCharacter != nil
        case .flowing:
            break
        }

        switch key.keyCode {
        case KeyPress.escape:
            togglePause()
            return true
        case KeyPress.tab:
            restartPassage()
            return true
        default:
            break
        }
        if isReturn { return true }
        if isPaused { return key.printableCharacter != nil || key.keyCode == KeyPress.delete }

        if key.keyCode == KeyPress.delete {
            if key.hasOption { engine.deleteWord(at: key.timestamp) } else { engine.backspace(at: key.timestamp) }
            countTime(at: key.timestamp)
            noteActivity(at: key.timestamp)
            return true
        }
        guard let character = key.printableCharacter else { return false }
        // A held key does not type: each character needs its own press.
        guard !key.isRepeat else { return true }

        let expected = nextKey
        engine.insert(character, at: key.timestamp)
        countTime(at: key.timestamp)
        if let expected, character != expected { onMistake?() }
        if engine.phase == .finished {
            finishPassage(at: key.timestamp)
        } else {
            noteActivity(at: key.timestamp)
        }
        return true
    }

    // MARK: Private

    private func countTime(at time: MonotonicTime) {
        if let lastKeyTime {
            let gap = max(0, time - lastKeyTime)
            pace.record(gap: gap)
            let counted = min(gap, DailyFlowPlan.maximumGap)
            activeSeconds += counted
            passageActive += counted
        }
        lastKeyTime = time
    }

    private func noteActivity(at time: MonotonicTime) {
        lastActivity = time
        isHintShowing = false
        activityID += 1
    }

    private func loadPassage() {
        engine = TypingEngine(target: generator.passage(for: segment, focus: focusKeys))
        resetPassageState()
    }

    private func resetPassageState() {
        passageActive = 0
        hintedPositions = []
        noteActivity(at: clock())
    }

    private func finishPassage(at time: MonotonicTime) {
        let round = DailyFlowRound(sessionID: sessionID, segment: segment, plannedMinutes: plan.minutes,
                                   activeSeconds: passageActive, hints: hintedPositions.count,
                                   result: RoundResult(session: engine.session(at: time)))
        save(DailyFlowEvent(round: round))
        sessionRounds += 1
        guard let next = plan.segment(atActive: activeSeconds) else {
            finishSession()
            return
        }
        segment = next
        loadPassage()
        lastActivity = time
    }

    private func save(_ event: DailyFlowEvent) {
        guard let store else { unsaved.append(event); return }
        do {
            try store.record(event)
        } catch {
            unsaved.append(event)
            saveError = error.localizedDescription
        }
    }

    private func finishSession() {
        isPaused = false
        isHintShowing = false
        activityID += 1
        if sessionRounds > 0, let session = history.sessions.first(where: { $0.id == sessionID }) {
            stage = .complete(session)
        } else {
            done()
        }
    }
}
