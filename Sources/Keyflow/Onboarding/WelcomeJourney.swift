import AppKit
import KeyflowCore
import Observation
import SwiftUI

/// Where a user stands with the first-launch tour. Stored in `UserDefaults`
/// under `onboarding.status` (see `Preferences.onboardingStatus`). Only the
/// first-launch tour changes it; replays from Help or Settings never do,
/// except that finishing a Full Tour's typing exercise records `completed`.
///
/// No stored value means Keyflow has never decided: on that launch, a user
/// with history or saved settings is an existing user and is recorded as
/// `skipped` (they can take the tour any time from Help); anyone else is new
/// and gets the Full Tour.
enum OnboardingStatus: String, CaseIterable {
    /// Shown, but Start Journey not pressed yet. Shown again at next launch.
    case notStarted
    /// Started and not finished; quitting part-way shows it again next launch.
    case inProgress
    /// The first typing exercise was finished.
    case completed
    /// Skipped, or an existing user from before the tour existed.
    case skipped

    /// What to do at launch, given what is stored and what the user already has.
    /// Returns whether to show the tour and the status to store, if it changes.
    static func launchDecision(stored: OnboardingStatus?, hasHistory: Bool, hasSavedSettings: Bool)
        -> (present: Bool, store: OnboardingStatus?) {
        switch stored {
        case nil:
            // Existing users are never pushed through it; new users always see it.
            if hasHistory || hasSavedSettings { return (false, .skipped) }
            return (true, .notStarted)
        case .notStarted, .inProgress:
            return (true, nil)
        case .completed, .skipped:
            return (false, nil)
        }
    }
}

/// Full: welcome, the six features, the first typing exercise, celebration.
/// Quick: the six features and a short "all caught up".
enum TutorialMode: Equatable {
    case full, quick
}

/// A real part of the window a tour step points at.
enum TourTarget: Hashable {
    /// A section in the top bar or the sidebar.
    case section(AppSection)
    /// A tab in Learn's top bar.
    case learnMode(LearnMode)
}

/// One stop on the feature tour.
struct TourStep: Equatable {
    let target: TourTarget
    let title: String
    let message: String
    /// Where the highlighted control is, so the location can be said in words.
    let place: Place
    /// The section to show while this step is up.
    let section: AppSection

    enum Place: Equatable {
        /// The main navigation: the top bar or the sidebar.
        case navigation
        /// Learn's tabs.
        case learnTabs
    }

    /// Where the highlighted control is, in words, so the arrow is never the only clue.
    func location(_ navigation: NavigationStyle) -> String {
        switch place {
        case .navigation: "\(title), \(navigation.place)"
        case .learnTabs: "\(title), at the top of Learn"
        }
    }

    static let all: [TourStep] = [
        TourStep(target: .section(.muscleMemory), title: "Learn",
                 message: "Build muscle memory with guided keyboard training.",
                 place: .navigation, section: .muscleMemory),
        TourStep(target: .section(.practice), title: "Practice",
                 message: "Improve your typing through words, sentences, and custom text.",
                 place: .navigation, section: .practice),
        TourStep(target: .section(.test), title: "Test",
                 message: "Measure your speed and accuracy with timed typing tests.",
                 place: .navigation, section: .test),
        TourStep(target: .section(.focus), title: "Focus",
                 message: "Target your weaknesses with personalised exercises.",
                 place: .navigation, section: .focus),
        TourStep(target: .section(.progress), title: "Progress",
                 message: "Track your accuracy, speed, and improvement over time.",
                 place: .navigation, section: .progress),
        TourStep(target: .learnMode(.mechanics), title: "Typing Mechanics",
                 message: "Master Shift, Caps Lock, capitalisation, numbers, and symbols.",
                 place: .learnTabs, section: .muscleMemory),
    ]
}

/// The one tutorial coordinator, behind every entry point: the first
/// launch, Help ▸ Take a Tour…, and Settings ▸ General ▸ Replay Tutorial.
///
/// It holds the tutorial's state only. Navigation goes through `AppModel`
/// (the extension below). The typing exercise uses Keyflow's own
/// `TypingEngine` and saves nothing, so it never reaches Progress.
@MainActor
@Observable
final class WelcomeJourney {
    enum Stage: Equatable {
        case welcome
        case tour(Int)
        case typing
        /// The summary is nil after a Quick Tour, which has no exercise.
        case complete(FirstTypingSummary?)
    }

    static let sentence = "My typing journey starts here."

    /// Nil when the tutorial is not showing.
    private(set) var stage: Stage?
    private(set) var mode: TutorialMode = .full
    var isActive: Bool { stage != nil }

    /// Help ▸ Take a Tour… and Settings ask Full or Quick in the main window.
    var isChoosingMode = false

    /// Where each tour target is, in window coordinates (AppKit: origin
    /// bottom-left). Reported by the targets themselves as they lay out.
    var targetFrames: [TourTarget: CGRect] = [:]

    private(set) var engine = WelcomeJourney.makeEngine()

    /// The navigation in use, for saying where things are.
    @ObservationIgnored var navigation: @MainActor () -> NavigationStyle = { .topBar }

    /// The first-launch tour updates the saved status; replays never do.
    @ObservationIgnored private(set) var isFirstLaunch = false
    /// The section to return to when the tutorial closes.
    @ObservationIgnored private(set) var originalSection: AppSection?

    var currentStep: TourStep? {
        if case .tour(let index) = stage { return TourStep.all[index] }
        return nil
    }

    /// Full: the six features plus the exercise. Quick: the six features.
    var stepCount: Int { TourStep.all.count + (mode == .full ? 1 : 0) }

    /// "3 of 7" for the tour and the exercise; nil on the welcome and the completion.
    var stepNumber: Int? {
        switch stage {
        case .tour(let index): index + 1
        case .typing: stepCount
        default: nil
        }
    }

    /// A Quick Tour starts on the first feature; there is nothing before it.
    var canGoBack: Bool {
        switch stage {
        case .tour(0): mode == .full
        case .tour, .typing: true
        default: false
        }
    }

    // MARK: First typing exercise

    private static func makeEngine() -> TypingEngine {
        TypingEngine(target: sentence, configuration: .init(timeLimit: nil, finishesAtEndOfText: false))
    }

    var hasMistakeShowing: Bool {
        zip(engine.typed, engine.target).contains { $0 != $1 }
    }

    /// The whole sentence, every character right.
    var isTypedCorrectly: Bool { engine.typed == engine.target }

    /// Keys while the exercise is up. Letters type, Delete and ⌥Delete
    /// correct. Return, Escape, Tab and ⌘ shortcuts pass on to the buttons
    /// and menus. Returns whether the key was used.
    func handle(_ key: KeyPress) -> Bool {
        guard stage == .typing, !key.hasCommandOrControl else { return false }
        if key.keyCode == KeyPress.delete {
            if key.hasOption { engine.deleteWord(at: key.timestamp) } else { engine.backspace(at: key.timestamp) }
            return true
        }
        guard let character = key.printableCharacter else { return false }
        // At the end with a mistake showing, extra letters go nowhere: the hint says to fix it.
        engine.insert(character, at: key.timestamp)
        if isTypedCorrectly {
            let metrics = PerformanceCalculator.metrics(for: engine.session(at: key.timestamp))
            stage = .complete(FirstTypingSummary(seconds: metrics.elapsed, accuracy: metrics.accuracy))
            announce("Done. \(TutorialCompletion.full.title)")
        }
        return true
    }

    // MARK: Moving through the tutorial

    fileprivate func open(_ mode: TutorialMode, from section: AppSection, firstLaunch: Bool) {
        self.mode = mode
        isFirstLaunch = firstLaunch
        originalSection = section
        engine = Self.makeEngine()
        targetFrames = [:]
        stage = mode == .full ? .welcome : nil
        if mode == .full { announce(.welcome) }
    }

    fileprivate func go(to next: Stage) {
        if next == .typing, stage != .typing { engine = Self.makeEngine() }
        stage = next
        announce(next)
    }

    /// Closes the tutorial and returns the section to show again, if any.
    fileprivate func close() -> AppSection? {
        stage = nil
        targetFrames = [:]
        engine = Self.makeEngine()
        isFirstLaunch = false
        defer { originalSection = nil }
        return originalSection
    }

    // MARK: VoiceOver

    private func announce(_ stage: Stage) {
        switch stage {
        case .welcome:
            announce("Welcome to Keyflow")
        case .tour(let index):
            let step = TourStep.all[index]
            announce("Step \(index + 1) of \(stepCount). \(step.title). \(step.message) Highlighted: \(step.location(navigation())).")
        case .typing:
            announce("Step \(stepCount) of \(stepCount). Your first keystrokes. Type: \(Self.sentence)")
        case .complete(let summary):
            if summary == nil { announce(TutorialCompletion.quick.title) }
        }
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}

/// How the first sentence went. Time and accuracy only: a WPM from one
/// short sentence would be misleading.
struct FirstTypingSummary: Equatable {
    let seconds: TimeInterval
    /// 0...1. Corrected mistakes count, as everywhere in Keyflow.
    let accuracy: Double
}

/// The words at the end of each tour.
enum TutorialCompletion {
    case full, quick

    var title: String {
        switch self {
        case .full: "You’re ready to flow."
        case .quick: "You’re all caught up."
        }
    }

    var message: String? {
        switch self {
        case .full: "Your typing journey starts now."
        case .quick: nil
        }
    }
}

// MARK: - AppModel

extension AppModel {
    /// At launch: the Full Tour for new users only. Existing users (with
    /// history or saved settings) are recorded as having skipped it.
    /// `savedKeys` are the keys in Keyflow's own defaults domain.
    func presentWelcomeJourneyIfNeeded(savedKeys: [String]) {
        let hasHistory = !(store?.summaries.isEmpty ?? true) || (trainingStore.map {
            !$0.events.isEmpty || !$0.fingerFocusEvents.isEmpty || !$0.assessmentEvents.isEmpty || !$0.mechanicsEvents.isEmpty
                || !$0.keyRepetitionEvents.isEmpty || !$0.dailyFlowEvents.isEmpty
        } ?? false)
        let decision = OnboardingStatus.launchDecision(stored: preferences.onboardingStatus, hasHistory: hasHistory,
                                                       hasSavedSettings: Self.hasSavedSettings(savedKeys))
        if let status = decision.store { preferences.onboardingStatus = status }
        if decision.present { journey.open(.full, from: section, firstLaunch: true) }
    }

    /// Whether any of these defaults keys were written by Keyflow itself
    /// (not by AppKit, such as window frames).
    static func hasSavedSettings(_ keys: [String]) -> Bool {
        keys.contains { key in
            !key.hasPrefix("NS") && !key.hasPrefix("Apple") && !key.hasPrefix("com.apple") && !key.hasPrefix("onboarding.")
        }
    }

    /// The keys in Keyflow's own defaults domain.
    static var savedDefaultsKeys: [String] {
        guard let id = Bundle.main.bundleIdentifier else { return [] }
        return UserDefaults.standard.persistentDomain(forName: id).map { Array($0.keys) } ?? []
    }

    // MARK: Help ▸ Take a Tour… and Settings ▸ Replay Tutorial

    /// Both entry points: asks Full or Quick (and warns about a running
    /// session) in the main window. Nothing changes until a tour is chosen.
    func requestTour() {
        guard !journey.isActive else { return }
        journey.isChoosingMode = true
    }

    /// What the Full-or-Quick question says, including what happens to a
    /// running session.
    var tourChoiceMessage: String {
        var text = "The Quick Tour shows where each feature is. The Full Tour also includes a short first typing exercise. Your history and settings are kept."
        if let running = runningSessionName {
            text += "\n\nThe \(running) in progress will end without being saved: its clock would keep running during the tour."
        }
        return text
    }

    /// A Practice or Test with its clock running. Learn exercises have no
    /// clock, so they simply wait, untouched, until the tour ends.
    var hasRunningSession: Bool { runningSessionName != nil }

    private var runningSessionName: String? {
        if practice.phase == .running { return "Practice session" }
        if test.phase == .running { return "Test" }
        return nil
    }

    /// Starts a replayed tour. The saved first-launch status is not touched.
    func startTour(_ mode: TutorialMode) {
        journey.isChoosingMode = false
        guard !journey.isActive else { return }
        if practice.phase == .running { practice.restart() }
        if test.phase == .running { test.restart() }
        journey.open(mode, from: section, firstLaunch: false)
        if mode == .quick { showTourStep(0) }
    }

    // MARK: Moving through the tour

    /// Start Journey on the welcome.
    func startJourney() {
        if journey.isFirstLaunch, preferences.onboardingStatus != .completed {
            preferences.onboardingStatus = .inProgress
        }
        showTourStep(0)
    }

    func journeyNext() {
        switch journey.stage {
        case .welcome:
            startJourney()
        case .tour(let index) where index + 1 < TourStep.all.count:
            showTourStep(index + 1)
        case .tour:
            journey.go(to: journey.mode == .full ? .typing : .complete(nil))
        default:
            break
        }
    }

    func journeyBack() {
        guard journey.canGoBack else { return }
        switch journey.stage {
        case .tour(0): journey.go(to: .welcome)
        case .tour(let index): showTourStep(index - 1)
        case .typing: showTourStep(TourStep.all.count - 1)
        default: break
        }
    }

    /// Skip at any point. Skipping the first-launch tour records `skipped`;
    /// skipping a replay changes nothing that is saved.
    func skipJourney() {
        if journey.isFirstLaunch, preferences.onboardingStatus != .completed {
            preferences.onboardingStatus = .skipped
        }
        if let original = journey.close() { section = original }
    }

    /// The completion's buttons. Start Learning opens Learn; every other way
    /// out returns to where the user was before the tour.
    func finishJourney(startLearning: Bool) {
        let original = journey.close()
        // Start Learning goes straight to the first lesson, ready to type.
        if startLearning {
            section = .muscleMemory
            learnMode = .lessons
        } else if let original {
            section = original
        }
    }

    /// Keys during the first typing exercise. Finishing the sentence
    /// completes onboarding, even if Keyflow quits on the celebration.
    func handleJourneyKey(_ key: KeyPress) -> Bool {
        let used = journey.handle(key)
        if case .complete = journey.stage, preferences.onboardingStatus != .completed {
            preferences.onboardingStatus = .completed
        }
        return used
    }

    private func showTourStep(_ index: Int) {
        let step = TourStep.all[index]
        if section != step.section { section = step.section }
        journey.go(to: .tour(index))
    }
}
