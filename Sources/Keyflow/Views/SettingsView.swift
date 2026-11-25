import AppKit
import KeyflowCore
import SwiftUI

/// Keyflow ▸ Settings (⌘,): a native Settings window with toolbar tabs.
enum SettingsTab: String, CaseIterable {
    case general, appearance, typing, training, feedback, data, about
}

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var tab = SettingsTab.general

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            AppearanceSettings().tabItem { Label("Appearance", systemImage: "textformat") }.tag(SettingsTab.appearance)
            TypingSettings().tabItem { Label("Typing", systemImage: "keyboard") }.tag(SettingsTab.typing)
            TrainingSettings().tabItem { Label("Training", systemImage: "graduationcap") }.tag(SettingsTab.training)
            FeedbackSettings().tabItem { Label("Feedback", systemImage: "speaker.wave.2") }.tag(SettingsTab.feedback)
            DataSettings().tabItem { Label("Data & Privacy", systemImage: "lock.shield") }.tag(SettingsTab.data)
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }.tag(SettingsTab.about)
        }
        .frame(width: 560)
        .onReceive(NotificationCenter.default.publisher(for: SettingsProbe.showTab)) { note in
            if let next = note.object as? SettingsTab { tab = next }
        }
        .background(SettingsWindowMarker())
        .applying(app.preferences)
        .environment(app.preferences)
    }
}

/// Tags the Settings window so keyboard monitors can tell it apart.
private struct SettingsWindowMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { MarkerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class MarkerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.identifier = KeyboardMonitor.settingsWindowID
        }
    }
}

/// A caption under a control.
private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(Preferences.self) private var preferences
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section {
                Picker("Open at launch", selection: $preferences.startupSection) {
                    ForEach(AppSection.allCases) { Text($0.title).tag($0) }
                }
                .disabled(preferences.restoresLastSection)
                Toggle("Reopen the last section", isOn: $preferences.restoresLastSection)
                Note("When on, Keyflow opens where you left off and this takes precedence over “Open at launch”. A typing session in progress is not restored; it starts fresh.")
            }
            Section {
                LabeledContent("Tutorial") {
                    Button("Replay Tutorial") { replay() }
                        .disabled(app.journey.isActive)
                }
                Note("A tour of Keyflow’s features. It is also in the Help menu, as Take a Tour. Your history and settings are kept.")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The same tour as Help ▸ Take a Tour…: Settings closes and the main
    /// window asks Full or Quick (and about any running session).
    private func replay() {
        openWindow(id: "main")
        NSApp.windows.first { $0.identifier == KeyboardMonitor.settingsWindowID }?.close()
        app.requestTour()
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(Preferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section {
                Picker("Theme", selection: $preferences.theme) {
                    ForEach(Theme.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Navigation", selection: Binding(get: { preferences.navigation }, set: { app.setNavigation($0) })) {
                    ForEach(NavigationStyle.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                .help("Also on the bar itself, its right-click menu and View ▸ Use \(preferences.navigation.other.title) (⌥⌘S).")
            } footer: {
                Text(preferences.navigation == .topBar
                     ? "The top bar steps aside while you type and comes back when you pause or move the mouse."
                     : "The sidebar stays put while you type. Hide it with ⌃⌘S.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Typing passage") {
                Picker("Font", selection: $preferences.typingFont) {
                    ForEach(TypingFontChoice.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("Size") {
                    HStack {
                        Slider(value: $preferences.typingFontSize, in: Preferences.fontSizes, step: 1)
                            .frame(width: 200)
                        Text("\(Int(preferences.typingFontSize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Picker("Caret", selection: $preferences.caretStyle) {
                    ForEach(CaretStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("Caret movement", selection: $preferences.caretAnimation) {
                    ForEach(CaretAnimation.allCases) { Text($0.title).tag($0) }
                }
                if reduceMotion {
                    Note("Reduce Motion is on in System Settings, so the caret always moves instantly.")
                }
                Picker("Width", selection: $preferences.typingWidth) {
                    ForEach(TypingWidth.allCases) { Text($0.title).tag($0) }
                }
                Note("The widest the passage gets; narrower windows still fit it to the space available.")
            }
            Section("Preview") {
                TypingPreview()
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A short passage drawn by the same renderer as every typing screen. Click
/// in it and type; it starts over when finished.
private struct TypingPreview: View {
    private static let sample = "The quick brown fox jumps over the lazy dog."
    @State private var engine = TypingEngine(target: sample, configuration: .init(timeLimit: nil, finishesAtEndOfText: false))
    @State private var keyboard = KeyboardMonitor(scope: .settings)
    @State private var active = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TypingSurfaceView(target: engine.target, typed: engine.typed, visibleLines: 2, isIdle: engine.typed.isEmpty)
                .contentShape(Rectangle())
                .accessibilityHint("Type here to try the typing settings")
            HStack {
                Text("Type here to try it. A mistake shows how errors look.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { reset() }.controlSize(.small)
            }
        }
        .onAppear {
            keyboard.start { press in
                if press.keyCode == KeyPress.delete { _ = engine.backspace(at: press.timestamp); return true }
                if press.keyCode == KeyPress.tab || press.keyCode == KeyPress.escape { reset(); return true }
                guard !press.hasCommandOrControl, let character = press.printableCharacter else { return false }
                if engine.typed.count >= engine.target.count { reset() }
                engine.insert(character, at: press.timestamp)
                return true
            }
        }
        .onDisappear { keyboard.stop() }
        .onChange(of: engine.typed.count) { _, count in
            if SettingsProbe.isEnabled { SettingsProbe.previewTyped = count }
        }
    }

    private func reset() {
        engine = TypingEngine(target: Self.sample, configuration: .init(timeLimit: nil, finishesAtEndOfText: false))
    }
}

// MARK: - Typing

private struct TypingSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(Preferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        let layout = KeyboardLayoutInfo.current()
        Form {
            Section {
                LabeledContent("Keyboard layout", value: preferences.keyboardLayout.title)
                Note("Exercises and finger guidance are written for US QWERTY, the only layout supported so far. In use now: \(layout?.name ?? "unknown")\(layout.map { $0.isUSCompatible ? ", which matches." : ", which does not match: Shift for symbols is not judged in Typing Mechanics." } ?? ".")")
                LabeledContent("Mistakes", value: "Kept until deleted")
                Note("A wrong character stays in your text, marked red, until you delete it with Delete (⌥Delete removes a word). This is the only mode Keyflow has.")
            }
            Section("Virtual keyboard") {
                Toggle("Lessons", isOn: Binding(get: { app.muscleMemory.showsKeyboard }, set: { app.muscleMemory.showsKeyboard = $0 }))
                Toggle("Finger Focus", isOn: Binding(get: { app.fingerFocus.showsKeyboard }, set: { app.fingerFocus.showsKeyboard = $0 }))
                Toggle("Typing Mechanics", isOn: Binding(get: { app.mechanics.showsKeyboard }, set: { app.mechanics.showsKeyboard = $0 }))
                Note("The same switch as ⌘K on each screen. In the first lesson stage, the finger guide stays even without the keyboard.")
            }
            Section("Typing Mechanics") {
                Toggle("Shift and Caps Lock guidance", isOn: $preferences.modifierGuidance)
                Note("Highlights which Shift to use and when to switch Caps Lock. Turning it off hides the hints only: technique is still checked and reported.")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Training

private struct TrainingSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(Preferences.self) private var preferences

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section {
                Picker("Test length", selection: Binding(get: { app.test.preferredDuration },
                                                        set: { app.test.setPreferredDuration($0) })) {
                    ForEach(TypingSessionModel.Role.test.durations, id: \.self) { Text("\($0) seconds").tag($0) }
                }
                Note("The same setting as the length picker on the Test screen. A test in progress keeps its length; the next one uses this.")
            }
            Section("Recommendations") {
                Toggle("Suggest what to practise", isOn: $preferences.adaptiveRecommendations)
                Picker("Put first", selection: $preferences.trainingPriority) {
                    ForEach(TrainingPriority.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!preferences.adaptiveRecommendations)
                Note("Suggestions appear in Typing Mechanics, in Progress, and as finger suggestions after a test. Turning them off only hides them; your history is kept. “Put first” orders Typing Mechanics suggestions toward mistakes (Accuracy First) or slow key changes (Speed First); it never changes how anything is measured.")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Feedback

private struct FeedbackSettings: View {
    @Environment(Preferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section {
                LabeledContent("Sound") {
                    HStack {
                        Picker("Sound", selection: $preferences.soundFeedback) {
                            ForEach(SoundFeedback.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button("Play") { FeedbackSound.mistake() }.controlSize(.small)
                    }
                }
                Note("A short, quiet sound when you type a wrong character.")
                Picker("Mistakes", selection: $preferences.errorEmphasis) {
                    ForEach(ErrorEmphasis.allCases) { Text($0.title).tag($0) }
                }
                Note("Mistakes are always red. Strong adds a tint behind them as well.")
                Toggle("Decorative animations", isOn: $preferences.decorativeAnimations)
                Note(reduceMotion
                     ? "Reduce Motion is on in System Settings, so these animations are off whatever this says."
                     : "Fades and transitions between states. Turning them off keeps every piece of feedback, just without movement.")
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Data & Privacy

private struct DataSettings: View {
    @Environment(AppModel.self) private var app
    @State private var exporting = false
    @State private var exportDocument: ExportDocument?
    @State private var message: String?
    @State private var confirmingProgressReset = false
    @State private var confirmingSettingsReset = false

    var body: some View {
        let sessions = app.store?.summaries ?? []
        let tests = sessions.filter { $0.kind == .test }.count
        let training = app.trainingStore
        let learnRecords = (training?.events.count ?? 0) + (training?.fingerFocusEvents.count ?? 0)
            + (training?.assessmentEvents.count ?? 0) + (training?.mechanicsEvents.count ?? 0)

        Form {
            Section("Your data") {
                LabeledContent("Tests", value: "\(tests)")
                LabeledContent("Practice sessions", value: "\(sessions.count - tests)")
                LabeledContent("Learn records", value: "\(learnRecords)")
                Note("Learn records: lesson rounds (\(training?.events.count ?? 0)), Finger Focus rounds (\(training?.fingerFocusEvents.count ?? 0)) and checks (\(training?.assessmentEvents.count ?? 0)), Typing Mechanics rounds (\(training?.mechanicsEvents.count ?? 0)).")
                LabeledContent("Stored in") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([StatisticsStore.defaultURL.deletingLastPathComponent()])
                    }
                    .controlSize(.small)
                }
            }
            Section("Export") {
                LabeledContent("Training data as JSON") {
                    Button("Export…") { export() }
                }
                Note("Results and timing summaries for every session and Learn round, with a schema version. Keystroke logs and what you typed are not included.")
                if let message { Note(message) }
            }
            Section("Reset") {
                LabeledContent("Training history") {
                    Button("Reset Progress…", role: .destructive) { confirmingProgressReset = true }
                }
                Note("Deletes every saved test and practice session and all Learn progress. Settings are kept.")
                LabeledContent("Preferences") {
                    Button("Reset Settings…") { confirmingSettingsReset = true }
                }
                Note("Restores every setting on these pages to its default. Training history is kept.")
            }
            Section("Privacy") {
                Text("Keyflow processes your typing on this Mac. It contains no networking code and no third-party libraries, so your sessions and progress are not sent anywhere. They are stored in your Library folder and are included in your own backups, such as Time Machine.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json,
                      defaultFilename: "Keyflow Export \(Date.now.formatted(.iso8601.year().month().day()))") { result in
            switch result {
            case .success(let url): message = "Exported to \(url.lastPathComponent)."
            case .failure(let error): message = "Export failed: \(error.localizedDescription)"
            }
        }
        .alert("Reset all progress?", isPresented: $confirmingProgressReset) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All Progress", role: .destructive) {
                do {
                    try app.resetProgress()
                    message = "Progress reset."
                } catch {
                    message = "Reset failed: \(error.localizedDescription)"
                }
            }
        } message: {
            Text("This permanently deletes \(sessions.count) sessions and \(learnRecords) Learn records: test and practice history, lessons, Finger Focus rounds and checks, and Typing Mechanics rounds. Settings are kept. This cannot be undone; export first if you want a copy.")
        }
        .alert("Reset all settings?", isPresented: $confirmingSettingsReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset Settings") { app.resetSettings() }
        } message: {
            Text("Every setting returns to its default. Your training history is not affected.")
        }
    }

    private func export() {
        do {
            exportDocument = ExportDocument(data: try KeyflowExport(store: app.store, trainingStore: app.trainingStore).json())
            exporting = true
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - About

private struct AboutSettings: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                LabeledContent("Application", value: AppInfo.name)
                LabeledContent("Version", value: AppInfo.displayVersion)
                LabeledContent("Build", value: AppInfo.build)
                LabeledContent("Platform", value: AppInfo.platform)
            }
            // Shown only when this build was given a feedback address.
            if let feedback = AppInfo.feedbackMailURL {
                Section("Beta") {
                    LabeledContent("Found a problem or have an idea?") {
                        Button("Send Beta Feedback…") { openURL(feedback) }
                    }
                    Note("Opens an email in your mail app with your Keyflow and macOS versions filled in. Bugs, UI issues, typing accuracy problems, feature suggestions and installation trouble are all welcome.")
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}
