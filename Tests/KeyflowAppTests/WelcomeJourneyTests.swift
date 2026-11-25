import AppKit
import Foundation
import Testing
@testable import Keyflow
import KeyflowCore

/// The Welcome Journey: who sees it, how it moves, the first typing
/// exercise, and that it leaves history and settings alone.
@MainActor
@Suite struct WelcomeJourneyTests {
    private func suite() -> UserDefaults {
        let name = "keyflow.journey.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func app(defaults: UserDefaults? = nil) throws -> AppModel {
        AppModel(store: try StatisticsStore.inMemory(), trainingStore: try TrainingStore.inMemory(),
                 defaults: defaults, preferences: Preferences(defaults: defaults))
    }

    private var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private func key(_ character: Character, at time: TimeInterval) -> KeyPress {
        KeyPress(keyCode: 0, characters: String(character), hasCommandOrControl: false, hasOption: false, timestamp: time)
    }

    private func delete(at time: TimeInterval, option: Bool = false) -> KeyPress {
        KeyPress(keyCode: KeyPress.delete, characters: "\u{7F}", hasCommandOrControl: false, hasOption: option, timestamp: time)
    }

    private func type(_ text: String, into app: AppModel, from start: TimeInterval) -> TimeInterval {
        var time = start
        for character in text { _ = app.handleJourneyKey(key(character, at: time)); time += 0.15 }
        return time
    }

    // MARK: Who sees it

    @Test func launchDecisionForEveryCase() {
        typealias S = OnboardingStatus
        #expect(S.launchDecision(stored: nil, hasHistory: false, hasSavedSettings: false) == (true, .notStarted))
        #expect(S.launchDecision(stored: nil, hasHistory: true, hasSavedSettings: false) == (false, .skipped))
        #expect(S.launchDecision(stored: nil, hasHistory: false, hasSavedSettings: true) == (false, .skipped))
        #expect(S.launchDecision(stored: .notStarted, hasHistory: true, hasSavedSettings: true) == (true, nil))
        #expect(S.launchDecision(stored: .inProgress, hasHistory: true, hasSavedSettings: true) == (true, nil),
                "quitting part-way shows it again")
        #expect(S.launchDecision(stored: .completed, hasHistory: false, hasSavedSettings: false) == (false, nil))
        #expect(S.launchDecision(stored: .skipped, hasHistory: false, hasSavedSettings: false) == (false, nil))
    }

    @Test func onlyKeyflowsOwnKeysCountAsSavedSettings() {
        #expect(!AppModel.hasSavedSettings([]))
        #expect(!AppModel.hasSavedSettings(["NSWindow Frame main", "AppleLanguages", "com.apple.SwiftUI.x", "onboarding.status"]))
        #expect(AppModel.hasSavedSettings(["NSWindow Frame main", "sidebar.hidden"]))
        #expect(AppModel.hasSavedSettings(["settings.appearance.theme"]))
    }

    @Test func newUserSeesTheWelcome() throws {
        let defaults = suite()
        let app = try app(defaults: defaults)
        app.presentWelcomeJourneyIfNeeded(savedKeys: [])
        #expect(app.journey.stage == .welcome)
        #expect(defaults.string(forKey: Preferences.Key.onboardingStatus) == "notStarted")
    }

    @Test func existingUserWithHistoryIsNotForcedThrough() throws {
        let defaults = suite()
        let app = try app(defaults: defaults)
        var engine = TypingEngine(target: "the cat", configuration: .init(timeLimit: 30, finishesAtEndOfText: true))
        var time = 10.0
        for character in "the cat" { _ = engine.insert(character, at: time); time += 0.2 }
        try app.store?.record(engine.session(at: time), kind: .test, timeLimit: 30)
        app.presentWelcomeJourneyIfNeeded(savedKeys: [])
        #expect(!app.journey.isActive)
        #expect(app.preferences.onboardingStatus == .skipped)
        // And the decision sticks: a later launch with the history gone still does not show it.
        let later = try self.app(defaults: defaults)
        later.presentWelcomeJourneyIfNeeded(savedKeys: [])
        #expect(!later.journey.isActive)
    }

    @Test func existingUserWithSettingsOnlyIsNotForcedThrough() throws {
        let app = try app(defaults: suite())
        app.presentWelcomeJourneyIfNeeded(savedKeys: ["settings.appearance.theme"])
        #expect(!app.journey.isActive)
    }

    @Test func statusSurvivesRelaunch() throws {
        let defaults = suite()
        let first = try app(defaults: defaults)
        first.presentWelcomeJourneyIfNeeded(savedKeys: [])
        first.startJourney()
        #expect(Preferences(defaults: defaults).onboardingStatus == .inProgress)
        let relaunched = try app(defaults: defaults)
        relaunched.presentWelcomeJourneyIfNeeded(savedKeys: ["settings.general.lastSection"])
        #expect(relaunched.journey.stage == .welcome, "an unfinished journey comes back, from the welcome")
    }

    // MARK: Moving through it

    @Test func tourVisitsEveryFeatureInOrder() throws {
        let app = try app()
        app.presentWelcomeJourneyIfNeeded(savedKeys: [])
        app.journeyNext()
        var visited: [TourTarget] = []
        while case .tour = app.journey.stage {
            let step = try #require(app.journey.currentStep)
            #expect(app.section == step.section, "\(step.title) shows its section")
            #expect(!step.message.isEmpty && !step.location(.topBar).isEmpty && !step.location(.sidebar).isEmpty, "every step says in words where to look")
            visited.append(step.target)
            app.journeyNext()
        }
        #expect(visited == [.section(.muscleMemory), .section(.practice), .section(.test), .section(.focus),
                            .section(.progress), .learnMode(.mechanics)])
        #expect(app.journey.stage == .typing)
        #expect(app.journey.stepNumber == 7 && app.journey.stepCount == 7)
    }

    @Test func backRetracesTheSteps() throws {
        let app = try app()
        app.presentWelcomeJourneyIfNeeded(savedKeys: [])
        app.journeyNext()
        app.journeyNext()
        #expect(app.journey.stage == .tour(1) && app.section == .practice)
        app.journeyBack()
        #expect(app.journey.stage == .tour(0) && app.section == .muscleMemory)
        app.journeyBack()
        #expect(app.journey.stage == .welcome)
        for _ in 0...TourStep.all.count { app.journeyNext() }
        #expect(app.journey.stage == .typing)
        app.journeyBack()
        #expect(app.journey.stage == .tour(TourStep.all.count - 1))
    }

    @Test func tourDoesNotChangeTheLearnMode() throws {
        let app = try app()
        app.learnMode = .fingerFocus
        app.presentWelcomeJourneyIfNeeded(savedKeys: [])
        for _ in 0...TourStep.all.count { app.journeyNext() }
        #expect(app.learnMode == .fingerFocus, "pointing at Typing Mechanics does not switch to it")
    }

    @Test func skipRecordsSkippedAndReturnsToWhereTheUserWas() throws {
        let app = try app()
        app.section = .test
        app.presentWelcomeJourneyIfNeeded(savedKeys: [])
        app.journeyNext()
        app.journeyNext()
        app.skipJourney()
        #expect(!app.journey.isActive)
        #expect(app.preferences.onboardingStatus == .skipped)
        #expect(app.section == .test)
        #expect(app.preferences.lastSection == .test, "the tour's navigation does not change the remembered section")
    }

    // MARK: First typing exercise

    @Test func typingTheSentenceCompletesTheJourney() throws {
        let app = try app()
        app.presentWelcomeJourneyIfNeeded(savedKeys: [])
        for _ in 0...TourStep.all.count { app.journeyNext() }
        _ = type(WelcomeJourney.sentence, into: app, from: uptime)
        guard case .complete(let summary?) = app.journey.stage else { Issue.record("not complete"); return }
        #expect(summary.accuracy == 1)
        #expect(summary.seconds > 0)
        #expect(app.preferences.onboardingStatus == .completed, "completed as soon as the sentence is done")
    }

    @Test func mistakesAreFixedWithDeleteAndNeverFail() throws {
        let app = try app()
        app.presentWelcomeJourneyIfNeeded(savedKeys: [])
        for _ in 0...TourStep.all.count { app.journeyNext() }
        var time = type("My typpng", into: app, from: uptime)
        #expect(app.journey.hasMistakeShowing)
        #expect(app.journey.stage == .typing, "a mistake is not a failure")
        _ = app.handleJourneyKey(delete(at: time)); time += 0.1
        _ = app.handleJourneyKey(delete(at: time)); time += 0.1
        _ = app.handleJourneyKey(delete(at: time)); time += 0.1
        #expect(!app.journey.hasMistakeShowing)
        time = type("ing journey starts here.", into: app, from: time)
        guard case .complete(let summary?) = app.journey.stage else { Issue.record("not complete"); return }
        #expect(summary.accuracy < 1, "the corrected mistake still counts, as everywhere in Keyflow")
    }

    @Test func aWrongSentenceDoesNotComplete() throws {
        let app = try app()
        app.presentWelcomeJourneyIfNeeded(savedKeys: [])
        for _ in 0...TourStep.all.count { app.journeyNext() }
        let time = type("My typing journey starts herr.", into: app, from: uptime)
        #expect(app.journey.stage == .typing, "every character must be right")
        #expect(app.journey.engine.typed.count == WelcomeJourney.sentence.count)
        // Extra letters go nowhere; ⌥Delete removes the word.
        _ = app.handleJourneyKey(key("x", at: time))
        #expect(app.journey.engine.typed.count == WelcomeJourney.sentence.count)
        _ = app.handleJourneyKey(delete(at: time + 0.1, option: true))
        _ = type("here.", into: app, from: time + 0.2)
        if case .complete = app.journey.stage {} else { Issue.record("fixing the word completes it") }
    }

    @Test func returnEscapeAndShortcutsPassToTheButtons() throws {
        let app = try app()
        app.presentWelcomeJourneyIfNeeded(savedKeys: [])
        for _ in 0...TourStep.all.count { app.journeyNext() }
        let t = uptime
        #expect(!app.handleJourneyKey(KeyPress(keyCode: KeyPress.return, characters: "\r", hasCommandOrControl: false, hasOption: false, timestamp: t)))
        #expect(!app.handleJourneyKey(KeyPress(keyCode: KeyPress.escape, characters: "\u{1B}", hasCommandOrControl: false, hasOption: false, timestamp: t)))
        #expect(!app.handleJourneyKey(KeyPress(keyCode: 12, characters: "q", hasCommandOrControl: true, hasOption: false, timestamp: t)))
        #expect(app.journey.engine.typed.isEmpty)
    }

    @Test func keysAreIgnoredOutsideTheExercise() throws {
        let app = try app()
        app.presentWelcomeJourneyIfNeeded(savedKeys: [])
        #expect(!app.handleJourneyKey(key("M", at: uptime)), "the welcome takes no typing")
        #expect(app.journey.engine.typed.isEmpty)
    }

    @Test func exerciseSavesNothingAndLeavesSettingsAlone() throws {
        let defaults = suite()
        let app = try app(defaults: defaults)
        app.preferences.theme = .dark
        app.preferences.typingFontSize = 30
        // Every setting; the remembered section is where the user navigates, not a setting.
        func settings() -> [String: Any] {
            defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("settings.") && $0.key != Preferences.Key.lastSection }
        }
        let before = settings()
        app.presentWelcomeJourneyIfNeeded(savedKeys: [])
        for _ in 0...TourStep.all.count { app.journeyNext() }
        _ = type(WelcomeJourney.sentence, into: app, from: uptime)
        app.finishJourney(startLearning: true)
        let after = settings()
        #expect(NSDictionary(dictionary: before).isEqual(to: after), "no setting changed")
        #expect(app.store?.summaries.isEmpty == true, "no Practice or Test session saved")
        #expect(app.trainingStore?.events.isEmpty == true && app.trainingStore?.mechanicsEvents.isEmpty == true,
                "no training record saved")
        #expect(app.practice.engine.position == 0 && app.muscleMemory.engine.position == 0)
        #expect(app.section == .muscleMemory && app.learnMode == .lessons, "Start Learning opens the first lesson")
    }

    @Test func startLearningOpensLearnAndExploreReturns() throws {
        let app = try app()
        app.section = .progress
        app.presentWelcomeJourneyIfNeeded(savedKeys: [])
        for _ in 0...TourStep.all.count { app.journeyNext() }
        _ = type(WelcomeJourney.sentence, into: app, from: uptime)
        app.finishJourney(startLearning: false)
        #expect(app.section == .progress && !app.journey.isActive)

        app.startTour(.full)
        for _ in 0...TourStep.all.count { app.journeyNext() }
        _ = type(WelcomeJourney.sentence, into: app, from: uptime)
        app.finishJourney(startLearning: true)
        #expect(app.section == .muscleMemory)
    }

    // MARK: Replay

    @Test func replayStartsAtTheWelcomeAndKeepsCompleted() throws {
        let app = try app()
        app.preferences.onboardingStatus = .completed
        app.startTour(.full)
        #expect(app.journey.stage == .welcome)
        app.startJourney()
        #expect(app.preferences.onboardingStatus == .completed, "starting a replay does not unfinish it")
        app.skipJourney()
        #expect(app.preferences.onboardingStatus == .completed, "skipping a replay does not either")
    }

    @Test func replayStartsTheExerciseAfresh() throws {
        let app = try app()
        app.presentWelcomeJourneyIfNeeded(savedKeys: [])
        for _ in 0...TourStep.all.count { app.journeyNext() }
        _ = type("My ty", into: app, from: uptime)
        app.skipJourney()
        app.startTour(.full)
        for _ in 0...TourStep.all.count { app.journeyNext() }
        #expect(app.journey.engine.typed.isEmpty)
    }

    @Test func replayEndsARunningTestWithoutSavingIt() throws {
        let app = try app()
        app.section = .test
        var time = uptime
        for character in app.test.engine.target.prefix(5) {
            _ = app.test.handle(key(character, at: time)); time += 0.1
        }
        #expect(app.hasRunningSession)
        app.startTour(.full)
        #expect(!app.hasRunningSession)
        #expect(app.store?.summaries.isEmpty == true)
    }

    @Test func resetSettingsDoesNotBringTheJourneyBack() throws {
        let defaults = suite()
        let app = try app(defaults: defaults)
        app.preferences.onboardingStatus = .skipped
        app.resetSettings()
        #expect(Preferences(defaults: defaults).onboardingStatus == .skipped)
    }

    // MARK: Entry points and modes

    @Test func takeATourAsksFirstAndChangesNothingUntilChosen() throws {
        let app = try app()
        app.section = .progress
        app.requestTour()
        #expect(app.journey.isChoosingMode)
        #expect(!app.journey.isActive && app.section == .progress, "nothing happens until a tour is chosen")
        // Cancel is the alert simply closing.
        app.journey.isChoosingMode = false
        #expect(!app.journey.isActive && app.section == .progress)
    }

    @Test func takeATourDoesNothingWhileATourIsShowing() throws {
        let app = try app()
        app.startTour(.quick)
        app.requestTour()
        #expect(!app.journey.isChoosingMode)
    }

    @Test func quickTourIsJustTheSixFeatures() throws {
        let app = try app()
        app.section = .test
        app.startTour(.quick)
        #expect(app.journey.mode == .quick && app.journey.stage == .tour(0), "no welcome")
        #expect(app.journey.stepCount == 6 && app.journey.stepNumber == 1)
        #expect(!app.journey.canGoBack, "nothing before Learn")
        app.journeyBack()
        #expect(app.journey.stage == .tour(0))
        for _ in 0..<TourStep.all.count { app.journeyNext() }
        #expect(app.journey.stage == .complete(nil), "no typing exercise")
        #expect(!app.handleJourneyKey(key("M", at: uptime)))
        app.finishJourney(startLearning: false)
        #expect(app.section == .test, "Back to Keyflow returns to where the user was")
    }

    @Test func replaysNeverChangeTheSavedStatus() throws {
        for saved in [OnboardingStatus.skipped, .completed] {
            let defaults = suite()
            let app = try app(defaults: defaults)
            app.preferences.onboardingStatus = saved
            app.startTour(.quick)
            app.journeyNext()
            app.skipJourney()
            app.startTour(.full)
            app.startJourney()
            #expect(Preferences(defaults: defaults).onboardingStatus == saved,
                    "starting a replayed Full Tour does not mark it in progress")
            // Quitting part-way leaves nothing that brings it back at launch.
            let relaunched = try self.app(defaults: defaults)
            relaunched.presentWelcomeJourneyIfNeeded(savedKeys: [])
            #expect(!relaunched.journey.isActive)
        }
    }

    @Test func choiceWarnsOnlyWhenASessionIsRunning() throws {
        let app = try app()
        #expect(!app.tourChoiceMessage.contains("in progress"))
        app.section = .practice
        var time = uptime
        for character in app.practice.engine.target.prefix(3) { _ = app.practice.handle(key(character, at: time)); time += 0.1 }
        #expect(app.tourChoiceMessage.contains("Practice session in progress will end without being saved"))
    }

    @Test func learnExercisesWaitUntouchedThroughATour() throws {
        let app = try app()
        app.section = .muscleMemory
        var time = uptime
        for character in app.muscleMemory.engine.target.prefix(4) { _ = app.muscleMemory.handle(key(character, at: time)); time += 0.1 }
        let typed = app.muscleMemory.engine.typed
        #expect(!app.hasRunningSession, "a Learn exercise has no clock, so there is nothing to end")
        app.startTour(.quick)
        for _ in 0..<TourStep.all.count { app.journeyNext() }
        app.finishJourney(startLearning: false)
        #expect(app.section == .muscleMemory && app.muscleMemory.engine.typed == typed, "the exercise is exactly where it was")
    }

    @Test func completionWording() {
        #expect(TutorialCompletion.full.title == "You’re ready to flow.")
        #expect(TutorialCompletion.full.message == "Your typing journey starts now.")
        #expect(TutorialCompletion.quick.title == "You’re all caught up.")
    }

    // MARK: Keyboard routing

    @Test func typingScreensHearNothingWhileTheJourneyShows() {
        let window = NSWindow()
        KeyboardMonitor.journeyIsShowing = true
        defer { KeyboardMonitor.journeyIsShowing = false }
        #expect(!KeyboardMonitor.accepts(window, scope: .main))
        #expect(KeyboardMonitor.accepts(window, scope: .onboarding))
        KeyboardMonitor.journeyIsShowing = false
        #expect(KeyboardMonitor.accepts(window, scope: .main))
        #expect(!KeyboardMonitor.accepts(window, scope: .onboarding))
    }

    // MARK: Layout

    @Test func sidebarTargetGetsPanelOnTheRight() throws {
        let bounds = CGRect(x: 0, y: 0, width: 1100, height: 740)
        let row = CGRect(x: 16, y: 60, width: 160, height: 22)
        let layout = try #require(TourLayout.make(target: row, popover: CGSize(width: 300, height: 180), bounds: bounds))
        #expect(layout.side == .right)
        #expect(layout.spotlight.contains(row))
        #expect(!layout.popover.intersects(layout.spotlight))
        #expect(bounds.contains(layout.popover))
        #expect(layout.arrowEnd.x > layout.spotlight.maxX && layout.arrowEnd.x - layout.spotlight.maxX <= TourLayout.arrowClearance + 0.5)
        #expect(abs(layout.arrowEnd.y - row.midY) < 0.5, "the arrow points at the row's middle")
    }

    @Test func topTargetGetsPanelBelowAndStaysInsideSmallWindows() throws {
        for width in [920.0, 1100, 1600] {
            let bounds = CGRect(x: 0, y: 0, width: width, height: 640)
            let tab = CGRect(x: width - 330, y: 64, width: 130, height: 26)
            let layout = try #require(TourLayout.make(target: tab, popover: CGSize(width: 300, height: 180), bounds: bounds))
            #expect(layout.side == .below)
            #expect(bounds.insetBy(dx: TourLayout.margin, dy: TourLayout.margin).contains(layout.popover))
            #expect(!layout.popover.intersects(layout.spotlight))
            #expect(layout.arrowEnd.y > layout.spotlight.maxY)
        }
    }

    @Test func offscreenOrUnmeasuredTargetsGetNoArrow() {
        let bounds = CGRect(x: 0, y: 0, width: 1100, height: 740)
        #expect(TourLayout.make(target: CGRect(x: -400, y: 60, width: 160, height: 22), popover: CGSize(width: 300, height: 180), bounds: bounds) == nil)
        #expect(TourLayout.make(target: .zero, popover: CGSize(width: 300, height: 180), bounds: bounds) == nil)
        #expect(TourLayout.make(target: CGRect(x: 16, y: 60, width: 160, height: 22), popover: .zero, bounds: bounds) == nil,
                "no arrow before the panel has been measured")
    }

    @Test func windowCoordinatesConvertToOverlayCoordinates() {
        // AppKit window coordinates have their origin at the bottom left.
        let overlay = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let target = CGRect(x: 20, y: 600, width: 100, height: 30)
        #expect(TourLayout.local(target, in: overlay) == CGRect(x: 20, y: 70, width: 100, height: 30))
    }
}
