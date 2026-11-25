import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Keyflow
import KeyflowCore

/// Settings 1.0: every preference persists, has its default, and changes
/// what it claims to change.
@MainActor
@Suite struct SettingsTests {
    private func suite() -> UserDefaults {
        let name = "keyflow.settings.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func app(defaults: UserDefaults? = nil) throws -> AppModel {
        AppModel(store: try StatisticsStore.inMemory(), trainingStore: try TrainingStore.inMemory(),
                 defaults: defaults, preferences: Preferences(defaults: defaults))
    }

    // MARK: Preferences

    @Test func defaultsAreDocumented() {
        let p = Preferences(defaults: suite())
        #expect(p.startupSection == .practice)
        #expect(!p.restoresLastSection)
        #expect(p.theme == .system)
        #expect(p.typingFont == .sfMono)
        #expect(p.typingFontSize == 24)
        #expect(p.caretStyle == .line)
        #expect(p.caretAnimation == .smooth)
        #expect(p.typingWidth == .comfortable)
        #expect(p.modifierGuidance)
        #expect(p.keyboardLayout == .usQWERTY)
        #expect(p.adaptiveRecommendations)
        #expect(p.trainingPriority == .balanced)
        #expect(p.soundFeedback == .off, "sound is off by default")
        #expect(p.errorEmphasis == .standard)
        #expect(p.decorativeAnimations)
        #expect(p.typingStyle == .standard, "the defaults draw exactly as before Settings existed")
    }

    @Test func everyPreferencePersists() {
        let defaults = suite()
        let p = Preferences(defaults: defaults)
        p.startupSection = .muscleMemory
        p.restoresLastSection = true
        p.theme = .dark
        p.typingFont = .menlo
        p.typingFontSize = 30
        p.caretStyle = .block
        p.caretAnimation = .instant
        p.typingWidth = .wide
        p.modifierGuidance = false
        p.adaptiveRecommendations = false
        p.trainingPriority = .speedFirst
        p.soundFeedback = .mistakes
        p.errorEmphasis = .strong
        p.decorativeAnimations = false

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.startupSection == .muscleMemory)
        #expect(reloaded.restoresLastSection)
        #expect(reloaded.theme == .dark)
        #expect(reloaded.typingFont == .menlo)
        #expect(reloaded.typingFontSize == 30)
        #expect(reloaded.caretStyle == .block)
        #expect(reloaded.caretAnimation == .instant)
        #expect(reloaded.typingWidth == .wide)
        #expect(!reloaded.modifierGuidance)
        #expect(!reloaded.adaptiveRecommendations)
        #expect(reloaded.trainingPriority == .speedFirst)
        #expect(reloaded.soundFeedback == .mistakes)
        #expect(reloaded.errorEmphasis == .strong)
        #expect(!reloaded.decorativeAnimations)
        p.theme = .system   // NSApp.appearance back to normal for other tests
    }

    @Test func badStoredValuesFallBackOrClamp() {
        let defaults = suite()
        defaults.set("purple", forKey: Preferences.Key.theme)
        defaults.set(99.0, forKey: Preferences.Key.typingFontSize)
        let p = Preferences(defaults: defaults)
        #expect(p.theme == .system)
        #expect(p.typingFontSize == 36)
        defaults.set(4.0, forKey: Preferences.Key.typingFontSize)
        #expect(Preferences(defaults: defaults).typingFontSize == 18)
    }

    @Test func launchSectionPrecedence() throws {
        let defaults = suite()
        let p = Preferences(defaults: defaults)
        p.startupSection = .progress
        p.lastSection = .test
        #expect(p.launchSection == .progress, "restore off: the chosen section")
        p.restoresLastSection = true
        #expect(p.launchSection == .test, "restore on: it wins over the chosen section")

        let first = try app(defaults: defaults)
        #expect(first.section == .test)
        first.section = .muscleMemory
        #expect(try app(defaults: defaults).section == .muscleMemory, "the last section is remembered across launches")
    }

    @Test func themeSetsTheAppAppearance() {
        _ = NSApplication.shared   // tests run without the app; create it as launch does
        let p = Preferences(defaults: nil)
        p.theme = .dark
        #expect(NSApp.appearance?.name == .darkAqua)
        p.theme = .light
        #expect(NSApp.appearance?.name == .aqua)
        p.theme = .system
        #expect(NSApp.appearance == nil)
    }

    // MARK: Appearance

    @Test func typingStyleScalesWithSizeAndFont() {
        var style = TypingStyle()
        #expect(style.lineHeight == 44 && style.caretHeight == 29, "the original metrics at 24 pt")
        let width24 = style.characterWidth
        style.size = 36
        #expect(style.lineHeight == 66)
        #expect(style.characterWidth > width24 * 1.4)
        style.size = 18
        #expect(style.lineHeight == 33)
        style.font = .menlo
        #expect(style.nsFont.fontName.hasPrefix("Menlo"))
        #expect(TypingFontChoice.sfMono.nsFont(size: 24).isFixedPitch)
    }

    @Test func widthsAreOrdered() {
        #expect(TypingWidth.comfortable.points == DS.Layout.readingWidth, "Comfortable is the previous fixed width")
        #expect(TypingWidth.compact.points < TypingWidth.comfortable.points)
        #expect(TypingWidth.comfortable.points < TypingWidth.wide.points)
    }

    // MARK: Training

    @Test func newTestLengthWaitsForTheRunningTest() {
        let defaults = suite()
        let test = TypingSessionModel(role: .test, defaults: defaults)
        test.setPreferredDuration(30)
        #expect(test.durationSeconds == 30 && test.preferredDuration == 30, "idle: applies now")

        typeCorrectly(3, into: test, from: ProcessInfo.processInfo.systemUptime)
        #expect(test.phase == .running)
        test.setPreferredDuration(120)
        #expect(test.durationSeconds == 30, "the running test keeps its length")
        #expect(test.preferredDuration == 120)
        #expect(test.engine.position == 3, "and is not restarted")
        #expect(TypingSessionModel(role: .test, defaults: defaults).durationSeconds == 120, "saved for next launch")

        test.restart()
        #expect(test.durationSeconds == 120, "the next test uses it")
        test.setPreferredDuration(45)
        #expect(test.durationSeconds == 120, "lengths the Test screen does not offer are ignored")
    }

    @Test func priorityReachesTypingMechanics() throws {
        let app = try app()
        app.preferences.trainingPriority = .accuracyFirst
        app.mechanics.priority = app.preferences.trainingPriority.core   // as RootView does on change
        #expect(app.mechanics.priority == .accuracy)
        app.resetSettings()
        #expect(app.mechanics.priority == .balanced)
    }

    // MARK: Feedback

    @Test func mistakesAreReportedForSound() throws {
        let test = TypingSessionModel(role: .test)
        var count = 0
        test.onMistake = { count += 1 }
        let expected = test.engine.target[0]
        _ = test.handle(key(expected == "x" ? "q" : "x", at: 100))
        _ = test.handle(key(String(test.engine.target[1]), at: 100.2))
        #expect(count == 1, "once per wrong character, not for correct ones")
    }

    @Test func soundIsWiredOnlyWhenChosen() throws {
        let app = try app()
        #expect(app.preferences.soundFeedback == .off)
        // The handler is installed on every model; it checks the preference when it fires.
        #expect(app.test.onMistake != nil && app.practice.onMistake != nil)
        #expect(app.muscleMemory.onMistake != nil && app.fingerFocus.onMistake != nil && app.mechanics.onMistake != nil)
    }

    // MARK: Keyboard routing

    @Test func settingsKeysStayInSettings() {
        let settings = NSWindow()
        settings.identifier = KeyboardMonitor.settingsWindowID
        let main = NSWindow()
        #expect(KeyboardMonitor.accepts(settings, scope: .settings))
        #expect(!KeyboardMonitor.accepts(settings, scope: .main), "typing in the preview never reaches a session")
        #expect(KeyboardMonitor.accepts(main, scope: .main))
        #expect(!KeyboardMonitor.accepts(main, scope: .settings))
        #expect(KeyboardMonitor.accepts(nil, scope: .main))
    }

    // MARK: Data

    private func record(into app: AppModel) throws {
        var engine = TypingEngine(target: "the cat sat", configuration: .init(timeLimit: 30, finishesAtEndOfText: true))
        var time = 10.0
        for character in "the cax sat" { _ = engine.insert(character, at: time); time += 0.2 }
        try app.store?.record(engine.session(at: time), kind: .test, timeLimit: 30)
        try app.trainingStore?.record(TrainingEvent(category: .homeRow, stage: .singleKeys, kind: .skip))
    }

    @Test func resetProgressClearsHistoryAndKeepsSettings() throws {
        let defaults = suite()
        let app = try app(defaults: defaults)
        try record(into: app)
        app.preferences.caretStyle = .underline
        app.mechanics.showsKeyboard = false
        let oldTest = app.test
        #expect(app.store?.summaries.count == 1 && app.trainingStore?.events.count == 1)

        try app.resetProgress()
        #expect(app.store?.summaries.isEmpty == true)
        #expect(app.trainingStore?.events.isEmpty == true)
        #expect(app.test !== oldTest, "models are rebuilt from the empty stores")
        #expect(app.test.onMistake != nil, "and reconnected")
        #expect(app.preferences.caretStyle == .underline, "preferences are kept")
        #expect(!app.mechanics.showsKeyboard, "screen settings are kept")
    }

    @Test func resetSettingsKeepsHistory() throws {
        let defaults = suite()
        let app = try app(defaults: defaults)
        try record(into: app)
        app.preferences.typingFontSize = 32
        app.preferences.soundFeedback = .mistakes
        app.preferences.adaptiveRecommendations = false
        app.test.setPreferredDuration(120)
        app.fingerFocus.showsKeyboard = false

        app.resetSettings()
        #expect(app.preferences.typingFontSize == 24)
        #expect(app.preferences.soundFeedback == .off)
        #expect(app.preferences.adaptiveRecommendations)
        #expect(app.test.durationSeconds == 60)
        #expect(app.fingerFocus.showsKeyboard)
        #expect(app.store?.summaries.count == 1, "history is kept")
        #expect(app.trainingStore?.events.count == 1)
        #expect(Preferences(defaults: defaults).typingFontSize == 24, "the reset is saved")
    }

    @Test func exportIsVersionedAndLeavesOutTypedText() throws {
        let app = try app()
        try record(into: app)
        let data = try KeyflowExport(store: app.store, trainingStore: app.trainingStore,
                                     now: Date(timeIntervalSince1970: 0)).json()
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["schemaVersion"] as? Int == 1)
        #expect(json["app"] as? String == "Keyflow")
        #expect(json["exportedAt"] as? String == "1970-01-01T00:00:00Z")
        let sessions = try #require(json["sessions"] as? [[String: Any]])
        #expect(sessions.count == 1)
        #expect(sessions.first?["kind"] as? String == "test")
        #expect(sessions.first?["timeLimitSeconds"] as? Int == 30)
        #expect((sessions.first?["accuracy"] as? Double).map { $0 > 0.8 && $0 < 1 } == true)
        let lessons = try #require(json["lessons"] as? [[String: Any]])
        #expect(lessons.first?["kind"] as? String == "skip")
        for key in ["fingerFocus", "fingerChecks", "typingMechanics"] {
            #expect((json[key] as? [Any])?.isEmpty == true)
        }
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("the cax sat") && !text.contains("the cat sat"), "typed text and passages are not exported")
    }

    @Test func emptyExportStillHasEverySection() throws {
        let data = try KeyflowExport(store: nil, trainingStore: nil).json()
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["schemaVersion", "app", "appVersion", "exportedAt", "sessions", "lessons",
                                   "fingerFocus", "fingerChecks", "typingMechanics", "keyRepetition", "dailyFlow"])
    }

    // MARK: Beta feedback

    @Test func feedbackEmailIsPrefilled() throws {
        let url = try #require(AppInfo.feedbackMailURL(to: "tester@example.com"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "mailto")
        #expect(components.path == "tester@example.com")
        let subject = components.queryItems?.first { $0.name == "subject" }?.value
        let body = components.queryItems?.first { $0.name == "body" }?.value ?? ""
        #expect(subject?.hasPrefix("Keyflow ") == true && subject?.hasSuffix(" feedback") == true)
        #expect(body.contains("What happened") && body.contains(AppInfo.platform), "versions are filled in")
        #expect(!url.absoluteString.contains(" "), "the link is fully encoded")
    }

    @Test func noFeedbackButtonWithoutAnAddress() {
        // The test bundle has no KeyflowFeedbackEmail, as a build without one.
        #expect(AppInfo.feedbackEmail == nil)
        #expect(AppInfo.feedbackMailURL == nil)
    }

    // MARK: Rendering

    @Test(arguments: [CaretStyle.line, .block, .underline])
    func caretStylesAndEmphasisRender(caret: CaretStyle) throws {
        let style = TypingStyle(font: .sfMono, size: 28, caret: caret, caretAnimation: .instant,
                                errorEmphasis: caret == .block ? .strong : .standard)
        let view = TypingSurfaceView(target: Array("The quick brown fox jumps over the lazy dog."),
                                     typed: Array("The quixk"), visibleLines: 2)
            .environment(\.typingStyle, style)
            .padding(24)
            .frame(width: 700, height: 150)
            .background(Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        #expect(image.size == CGSize(width: 700, height: 150))
        guard let directory = ProcessInfo.processInfo.environment["KEYFLOW_SNAPSHOT_DIR"] else { return }
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("settings-caret-\(caret.rawValue).png"))
    }
}
