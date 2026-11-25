import KeyflowCore
import SwiftUI

@main
struct KeyflowApp: App {
    @State private var app = UIProbe.isEnabled || InputProbe.isMechanicsProbe || KeyRepetitionProbe.isEnabled || DailyFlowProbe.isEnabled || SettingsProbe.isEnabled || OnboardingProbe.isEnabled
        ? InputProbe.ephemeralApp() : AppModel()

    var body: some Scene {
        Window("Keyflow", id: "main") {
            RootView()
                .environment(app)
                .frame(minWidth: 920, minHeight: 640)
        }
        .defaultSize(width: 1100, height: 740)
        // The navigation bar shares the title bar's strip with the window buttons.
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Session") {
                Button("Restart") { app.restartCurrent() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!app.canRestart || app.journey.isActive)

                if let session = app.activeSession {
                    Divider()
                    if session.role == .practice {
                        Picker("Practice Type", selection: Binding(get: { session.mode }, set: { session.mode = $0 })) {
                            ForEach(PracticeMode.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    Picker("Length", selection: Binding(get: { session.durationSeconds }, set: { session.durationSeconds = $0 })) {
                        ForEach(session.role.durations, id: \.self) { Text(durationLabel($0)).tag($0) }
                    }
                }

                if app.section == .muscleMemory {
                    Divider()
                    Picker("Learn Mode", selection: Binding(get: { app.learnMode }, set: { app.learnMode = $0 })) {
                        ForEach(LearnMode.allCases) { Text($0.title).tag($0) }
                    }
                    switch app.learnMode {
                    case .today:
                        EmptyView()
                    case .dailyFlow:
                        Picker("Session Length", selection: Binding(get: { app.dailyFlow.plan.minutes }, set: { app.dailyFlow.setMinutes($0) })) {
                            ForEach(DailyFlowPlan.lengths, id: \.self) { Text("\($0) Minutes").tag($0) }
                        }
                        .disabled(app.dailyFlow.stage != .start)
                    case .lessons:
                        Picker("Lesson", selection: Binding(get: { app.muscleMemory.category }, set: { app.muscleMemory.select($0) })) {
                            ForEach(TrainingCategory.allCases) { Text($0.title).tag($0) }
                        }
                    case .fingerFocus:
                        Picker("Finger", selection: Binding(get: { app.fingerFocus.target }, set: { app.fingerFocus.select($0) })) {
                            ForEach(FingerFocusTarget.allCases) { Text($0.title).tag($0) }
                        }
                        Picker("Level", selection: Binding(get: { app.fingerFocus.level }, set: { app.fingerFocus.select($0) })) {
                            ForEach(FingerFocusLevel.allCases) { Text("\($0.rawValue). \($0.title)").tag($0) }
                        }
                    case .keyRepetition:
                        Picker("Target Key", selection: Binding(get: { app.keyRepetition.letter }, set: { app.keyRepetition.select($0) })) {
                            ForEach(KeyRepetitionCounter.letters, id: \.self) { Text(String($0).uppercased()).tag($0) }
                        }
                        .disabled(app.keyRepetition.stage != .setup)
                    case .mechanics:
                        Picker("Training Area", selection: Binding(get: { app.mechanics.area }, set: { app.mechanics.select($0) })) {
                            ForEach(MechanicsArea.allCases) { Text($0.title).tag($0) }
                        }
                        Picker("Stage", selection: Binding(get: { app.mechanics.drill }, set: { app.mechanics.select($0) })) {
                            ForEach(app.mechanics.area.drills) { Text("\($0.stage). \($0.title)").tag($0) }
                        }
                    }
                    Button("Next Exercise") { app.nextLearnExercise() }
                        .keyboardShortcut(.rightArrow, modifiers: .command)
                        .disabled(app.journey.isActive || !app.hasNextLearnExercise)
                    Button(app.learnMode == .dailyFlow ? (app.learnShowsKeyboard ? "Turn Hints Off" : "Turn Hints On")
                           : (app.learnShowsKeyboard ? "Hide Keyboard" : "Show Keyboard")) {
                        app.learnShowsKeyboard.toggle()
                    }
                    .keyboardShortcut("k", modifiers: .command)
                    // Key Repetition shows only the letter, and Today has no keyboard.
                    .disabled(app.learnMode == .keyRepetition || app.learnMode == .today)
                }
            }

            // Help ▸ Take a Tour…, in place of the default "Keyflow Help",
            // which only reported that no help book exists.
            CommandGroup(replacing: .help) {
                TakeATourButton(app: app)
            }

            CommandGroup(before: .toolbar) {
                ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                    // The Welcome Journey chooses the section while it is showing.
                    Button(section.title) { app.section = section }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                        .disabled(app.journey.isActive)
                }
                Divider()
                // Top bar or sidebar. Also on the bar itself, its right-click
                // menu and Settings ▸ Appearance.
                Button("Use \(app.preferences.navigation.other.title)") { app.setNavigation(app.preferences.navigation.other) }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                    .disabled(app.journey.isActive)
                if app.preferences.navigation == .sidebar {
                    Button(app.preferences.sidebarHidden ? "Show Sidebar" : "Hide Sidebar") { app.toggleSidebar() }
                        .keyboardShortcut("s", modifiers: [.command, .control])
                        .disabled(app.journey.isActive)
                }
                Divider()
            }
        }

        Settings {
            SettingsView()
                .environment(app)
        }
    }

    private func durationLabel(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) Seconds" : (seconds == 60 ? "1 Minute" : "\(seconds / 60) Minutes")
    }
}

/// Help ▸ Take a Tour…: brings the main window back if it was closed, then
/// asks Full or Quick there.
private struct TakeATourButton: View {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Take a Tour…") {
            openWindow(id: "main")
            app.requestTour()
        }
        .disabled(app.journey.isActive)
    }
}
