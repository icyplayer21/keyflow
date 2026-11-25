import KeyflowCore
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case muscleMemory, practice, test, focus, progress

    var id: Self { self }

    var title: String {
        switch self {
        case .muscleMemory: "Learn"
        case .practice: "Practice"
        case .test: "Test"
        case .focus: "Focus"
        case .progress: "Progress"
        }
    }

    var symbol: String {
        switch self {
        case .muscleMemory: "graduationcap"
        case .practice: "keyboard"
        case .test: "stopwatch"
        case .focus: "scope"
        case .progress: "chart.line.uptrend.xyaxis"
        }
    }
}

/// The parts of Learn, in the order of its top bar.
enum LearnMode: String, CaseIterable, Identifiable, Hashable {
    case today, dailyFlow, lessons, fingerFocus, keyRepetition, mechanics

    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .dailyFlow: "Daily Flow"
        case .lessons: "Lessons"
        case .fingerFocus: "Finger Focus"
        case .keyRepetition: "Key Repetition"
        case .mechanics: "Typing Mechanics"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var section: AppSection {
        didSet { if section != oldValue { preferences.lastSection = section } }
    }
    let store: StatisticsStore?
    /// Set when the on-disk store could not be opened.
    let storageError: String?
    let preferences: Preferences
    private(set) var practice: TypingSessionModel
    private(set) var test: TypingSessionModel
    let trainingStore: TrainingStore?
    private(set) var muscleMemory: MuscleMemoryModel
    private(set) var fingerFocus: FingerFocusModel
    private(set) var mechanics: TypingMechanicsModel
    private(set) var keyRepetition: KeyRepetitionModel
    private(set) var dailyFlow: DailyFlowModel
    /// Learn opens on Today at every launch: it is Keyflow's front door.
    var learnMode: LearnMode = .today
    /// The first-launch Welcome Journey (Onboarding/).
    let journey = WelcomeJourney()
    /// Whether the top navigation has stepped aside for typing.
    let topBar = TopBarVisibility()
    @ObservationIgnored private let defaults: UserDefaults?

    /// Keyflow's saved defaults keys as found at launch, before anything this
    /// launch writes; tells an existing user from a new one.
    @ObservationIgnored private(set) var launchDefaultsKeys: [String] = []

    convenience init() {
        let launchKeys = Self.savedDefaultsKeys
        var store: StatisticsStore?
        var storageError: String?
        do {
            store = try StatisticsStore.onDisk(at: StatisticsStore.defaultURL)
        } catch {
            storageError = "Your history could not be opened, so sessions from this launch will not be kept. (\(error.localizedDescription))"
            store = try? StatisticsStore.inMemory()
        }
        var trainingStore: TrainingStore?
        do {
            trainingStore = try TrainingStore.onDisk(at: TrainingStore.defaultURL)
        } catch {
            let message = "Muscle Memory progress could not be opened, so training from this launch will not be kept. (\(error.localizedDescription))"
            storageError = [storageError, message].compactMap { $0 }.joined(separator: "\n")
            trainingStore = try? TrainingStore.inMemory()
        }
        self.init(store: store, trainingStore: trainingStore, storageError: storageError, defaults: .standard,
                  preferences: .shared)
        launchDefaultsKeys = launchKeys
    }

    /// Tests pass in-memory stores and no defaults.
    init(store: StatisticsStore?, trainingStore: TrainingStore?, storageError: String? = nil, defaults: UserDefaults?,
         preferences: Preferences = Preferences(defaults: nil)) {
        self.store = store
        self.storageError = storageError
        self.trainingStore = trainingStore
        self.defaults = defaults
        self.preferences = preferences
        section = preferences.launchSection
        muscleMemory = MuscleMemoryModel(store: trainingStore, defaults: defaults)
        fingerFocus = FingerFocusModel(store: trainingStore, defaults: defaults)
        mechanics = TypingMechanicsModel(store: trainingStore, defaults: defaults)
        keyRepetition = KeyRepetitionModel(store: trainingStore, defaults: defaults)
        dailyFlow = DailyFlowModel(store: trainingStore, statistics: store, defaults: defaults)
        practice = TypingSessionModel(role: .practice, store: store, defaults: defaults)
        test = TypingSessionModel(role: .test, store: store, defaults: defaults)
        connectModels()
        journey.navigation = { preferences.navigation }
    }

    /// Hooks the feature models up to the preferences they depend on.
    private func connectModels() {
        let preferences = preferences
        let mistake: () -> Void = { if preferences.soundFeedback == .mistakes { FeedbackSound.mistake() } }
        practice.onMistake = mistake
        test.onMistake = mistake
        muscleMemory.onMistake = mistake
        fingerFocus.onMistake = mistake
        mechanics.onMistake = mistake
        keyRepetition.onMistake = mistake
        dailyFlow.onMistake = mistake
        mechanics.priority = preferences.trainingPriority.core
    }

    // MARK: Settings ▸ Data & Privacy

    /// Deletes every saved session and all Learn progress (lessons, Finger
    /// Focus rounds and checks, Typing Mechanics rounds). Preferences and
    /// screen choices are kept. The feature models start fresh afterwards.
    func resetProgress() throws {
        try store?.deleteAll()
        try trainingStore?.deleteAll()
        muscleMemory = MuscleMemoryModel(store: trainingStore, defaults: defaults)
        fingerFocus = FingerFocusModel(store: trainingStore, defaults: defaults)
        mechanics = TypingMechanicsModel(store: trainingStore, defaults: defaults)
        keyRepetition = KeyRepetitionModel(store: trainingStore, defaults: defaults)
        dailyFlow = DailyFlowModel(store: trainingStore, statistics: store, defaults: defaults)
        practice = TypingSessionModel(role: .practice, store: store, defaults: defaults)
        test = TypingSessionModel(role: .test, store: store, defaults: defaults)
        connectModels()
    }

    /// Every setting shown in Settings back to its default. Training history
    /// and screen choices (lesson, finger, area) are kept.
    func resetSettings() {
        preferences.resetToDefaults()
        test.setPreferredDuration(TypingSessionModel.Role.test.defaultDuration)
        muscleMemory.showsKeyboard = true
        fingerFocus.showsKeyboard = true
        mechanics.showsKeyboard = true
        keyRepetition.showsKeyboard = true
        dailyFlow.showsKeyboard = true
        mechanics.priority = preferences.trainingPriority.core
    }

    /// The session shown in the current section, if it has one.
    var activeSession: TypingSessionModel? {
        switch section {
        case .practice: practice
        case .test: test
        case .muscleMemory, .focus, .progress: nil
        }
    }

    /// An exercise is under way on the screen in front, not paused.
    var isExerciseRunning: Bool {
        guard !journey.isActive else { return false }
        switch section {
        case .practice: return practice.phase == .running
        case .test: return test.phase == .running
        case .focus, .progress: return false
        case .muscleMemory:
            switch learnMode {
            case .today: return false
            case .dailyFlow: return dailyFlow.stage == .flowing && !dailyFlow.isPaused
            case .lessons: return muscleMemory.phase == .running
            case .fingerFocus: return fingerFocus.phase == .running
            case .keyRepetition: return keyRepetition.stage == .training && !keyRepetition.isPaused
            case .mechanics: return mechanics.phase == .running
            }
        }
    }

    var canRestart: Bool { activeSession != nil || (section == .muscleMemory && learnMode != .today) }

    func restartCurrent() {
        guard section == .muscleMemory else { activeSession?.restart(); return }
        switch learnMode {
        case .today: break
        case .dailyFlow: dailyFlow.restartPassage()
        case .lessons: muscleMemory.restart()
        case .fingerFocus: fingerFocus.restart()
        case .keyRepetition: keyRepetition.restart()
        case .mechanics: mechanics.restart()
        }
    }

    /// Daily Flow chooses its own passages, Key Repetition has just one, and Today has none.
    var hasNextLearnExercise: Bool { ![.today, .keyRepetition, .dailyFlow].contains(learnMode) }

    func nextLearnExercise() {
        switch learnMode {
        case .today, .dailyFlow, .keyRepetition: break
        case .lessons: muscleMemory.nextExercise()
        case .fingerFocus: fingerFocus.nextExercise()
        case .mechanics: mechanics.nextExercise()
        }
    }

    /// Progress → finger → Finger Focus, with the finger already chosen.
    func trainFinger(_ target: FingerFocusTarget) {
        fingerFocus.open(target)
        learnMode = .fingerFocus
        section = .muscleMemory
    }

    /// Progress → a Typing Mechanics recommendation → that stage in Learn.
    func openMechanics(_ recommendation: MechanicsRecommendation) {
        mechanics.follow(recommendation)
        learnMode = .mechanics
        section = .muscleMemory
    }

    /// Opens Finger Focus straight into a check for the finger.
    func checkFinger(_ target: FingerFocusTarget) {
        fingerFocus.open(target)
        fingerFocus.startCheck()
        learnMode = .fingerFocus
        section = .muscleMemory
    }

    var learnShowsKeyboard: Bool {
        get {
            switch learnMode {
            case .today: false
            case .dailyFlow: dailyFlow.showsKeyboard
            case .lessons: muscleMemory.showsKeyboard
            case .fingerFocus: fingerFocus.showsKeyboard
            case .keyRepetition: keyRepetition.showsKeyboard
            case .mechanics: mechanics.showsKeyboard
            }
        }
        set {
            switch learnMode {
            case .today: break
            case .dailyFlow: dailyFlow.showsKeyboard = newValue
            case .lessons: muscleMemory.showsKeyboard = newValue
            case .fingerFocus: fingerFocus.showsKeyboard = newValue
            case .keyRepetition: keyRepetition.showsKeyboard = newValue
            case .mechanics: mechanics.showsKeyboard = newValue
            }
        }
    }
}

// MARK: - Navigation

extension AppModel {
    /// Top bar or sidebar, from the button on either, a right-click, the View
    /// menu, Settings or the welcome. Only the navigation changes: the section
    /// and any exercise under way stay exactly as they were.
    func setNavigation(_ style: NavigationStyle) {
        guard preferences.navigation != style else { return }
        withMotion(DS.Motion.standard) {
            preferences.navigation = style
            // Choosing the sidebar means wanting to see it.
            if style == .sidebar, preferences.sidebarHidden { preferences.sidebarHidden = false }
        }
        topBar.reveal()
        AccessibilityNotification.Announcement("\(style.title) navigation").post()
    }

    /// View ▸ Hide Sidebar (⌃⌘S). Sidebar mode only.
    func toggleSidebar() {
        guard preferences.navigation == .sidebar else { return }
        withMotion(DS.Motion.standard) { preferences.sidebarHidden.toggle() }
    }
}

// MARK: - Today

extension AppModel {
    /// Every day with saved practice, from both stores. Skipped lesson stages
    /// are not practice.
    var practiceDays: PracticeDays {
        var dates: [Date] = store?.summaries.map(\.date) ?? []
        if let trainingStore {
            dates += trainingStore.events.filter { $0.round != nil }.map(\.date)
            dates += trainingStore.fingerFocusEvents.map(\.date)
            dates += trainingStore.assessmentEvents.map(\.date)
            dates += trainingStore.mechanicsEvents.map(\.date)
            dates += trainingStore.keyRepetitionEvents.map(\.date)
        }
        dates += dailyFlow.events.map(\.date)
        return PracticeDays(dates: dates)
    }

    /// A one-click way back into a Learn mode you have used before.
    enum PickUp: Equatable, Identifiable {
        case lessons(TrainingCategory, TrainingStage)
        case fingerFocus(FingerFocusTarget)
        case keyRepetition(Character)

        var id: String {
            switch self {
            case .lessons: "lessons"
            case .fingerFocus: "fingerFocus"
            case .keyRepetition: "keyRepetition"
            }
        }
    }

    /// Up to three rows, each only for a mode with saved practice.
    var pickUps: [PickUp] {
        guard let trainingStore else { return [] }
        var rows: [PickUp] = []
        if trainingStore.events.contains(where: { $0.round != nil }) {
            rows.append(.lessons(muscleMemory.category, muscleMemory.stage))
        }
        if !trainingStore.fingerFocusEvents.isEmpty || !trainingStore.assessmentEvents.isEmpty {
            rows.append(.fingerFocus(fingerFocus.target))
        }
        if let last = trainingStore.keyRepetitionEvents.max(by: { $0.date < $1.date }),
           let letter = last.result.letter.first {
            // The key on screen if a session is under way, else the last one saved.
            rows.append(.keyRepetition(keyRepetition.stage == .setup ? letter : keyRepetition.letter))
        }
        return rows
    }

    /// Opens the mode. Only Key Repetition's key is chosen, and only between
    /// sessions; nothing under way is changed or thrown away.
    func pickUp(_ row: PickUp) {
        switch row {
        case .lessons:
            learnMode = .lessons
        case .fingerFocus:
            learnMode = .fingerFocus
        case .keyRepetition(let letter):
            if keyRepetition.stage == .setup { keyRepetition.select(letter) }
            learnMode = .keyRepetition
        }
    }

    /// Today's Start: opens Daily Flow and begins a session, or returns to the
    /// one under way, which is never restarted.
    func startDailyFlowFromToday() {
        if dailyFlow.stage == .start, !dailyFlow.hasPractisedToday { dailyFlow.start() }
        learnMode = .dailyFlow
    }
}
