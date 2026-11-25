import Foundation
import Testing
@testable import Keyflow
import KeyflowCore

@MainActor
@Suite struct NavigationStyleTests {
    private func makeApp(_ preferences: Preferences = Preferences(defaults: nil)) throws -> AppModel {
        AppModel(store: try StatisticsStore.inMemory(), trainingStore: try TrainingStore.inMemory(), defaults: nil,
                 preferences: preferences)
    }

    private func key(_ c: Character, at time: Double) -> KeyPress {
        KeyPress(keyCode: 1, characters: String(c), hasCommandOrControl: false, hasOption: false, timestamp: time)
    }

    @Test func topBarIsTheDefault() {
        #expect(Preferences(defaults: nil).navigation == .topBar)
        #expect(!Preferences(defaults: nil).sidebarHidden)
    }

    @Test func theChoiceIsKeptAcrossLaunches() throws {
        let suite = "keyflow-navigation-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = Preferences(defaults: defaults)
        first.navigation = .sidebar
        first.sidebarHidden = true
        let again = Preferences(defaults: defaults)
        #expect(again.navigation == .sidebar)
        #expect(again.sidebarHidden)
    }

    @Test func resetSettingsBringsBackTheTopBarButNotTheWindowState() throws {
        let suite = "keyflow-navigation-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        preferences.navigation = .sidebar
        preferences.sidebarHidden = true
        preferences.resetToDefaults()
        #expect(preferences.navigation == .topBar)
        #expect(defaults.object(forKey: Preferences.Key.navigation) == nil, "nothing pinned")
        #expect(preferences.sidebarHidden, "how you left the window is not a setting")
    }

    @Test func switchingKeepsTheScreenAndTheExercise() throws {
        let app = try makeApp()
        app.section = .muscleMemory
        app.learnMode = .keyRepetition
        app.keyRepetition.start()
        _ = app.keyRepetition.handle(key(app.keyRepetition.letter, at: 1))
        _ = app.keyRepetition.handle(key(app.keyRepetition.letter, at: 1.3))
        app.setNavigation(.sidebar)
        #expect(app.preferences.navigation == .sidebar)
        #expect(app.section == .muscleMemory && app.learnMode == .keyRepetition)
        #expect(app.keyRepetition.stage == .training && app.keyRepetition.counter.correct == 2)
        app.setNavigation(.topBar)
        #expect(app.keyRepetition.stage == .training && app.keyRepetition.counter.correct == 2)
    }

    @Test func choosingTheSidebarShowsIt() throws {
        let app = try makeApp()
        app.preferences.sidebarHidden = true
        app.setNavigation(.sidebar)
        #expect(!app.preferences.sidebarHidden)
    }

    @Test func switchingBringsTheTopBarBack() throws {
        let app = try makeApp()
        app.section = .practice
        app.topBar.noteTyping(exerciseRunning: true)
        app.setNavigation(.sidebar)
        #expect(!app.topBar.isFaded)
    }

    @Test func hideSidebarOnlyWorksInSidebarMode() throws {
        let app = try makeApp()
        app.toggleSidebar()
        #expect(!app.preferences.sidebarHidden, "nothing to hide with the top bar")
        app.setNavigation(.sidebar)
        app.toggleSidebar()
        #expect(app.preferences.sidebarHidden)
        app.toggleSidebar()
        #expect(!app.preferences.sidebarHidden)
    }

    @Test func theTourSaysWhereToLook() {
        let learn = TourStep.all[0]
        #expect(learn.location(.topBar) == "Learn, in the top bar")
        #expect(learn.location(.sidebar) == "Learn, in the sidebar")
        let mechanics = try? #require(TourStep.all.last)
        #expect(mechanics?.location(.sidebar) == "Typing Mechanics, at the top of Learn")
    }

    @Test func theTopBarStaysForAssistiveTechnology() {
        let bar = TopBarVisibility(keepsVisible: { true })
        bar.noteTyping(exerciseRunning: true)
        #expect(!bar.isFaded, "VoiceOver, Switch Control or Full Keyboard Access keep it on screen")
    }

    @Test func navigationIsASettingAndSidebarHiddenIsNot() {
        #expect(Preferences.Key.all.contains(Preferences.Key.navigation))
        #expect(!Preferences.Key.all.contains(Preferences.Key.sidebarHidden))
    }
}
