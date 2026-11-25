import AppKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app

        // Settings ▸ Appearance ▸ Navigation: a floating bar in the window's
        // top strip, or a sidebar. Both live in one split view, so switching
        // never rebuilds the screen you're on: in top bar mode the sidebar
        // column is simply closed and its button removed.
        // The Welcome Journey points at the sidebar, so a hidden sidebar is
        // shown while the journey is up, and the saved choice returns after.
        let journeyShowing = app.journey.isActive
        let usesTopBar = app.preferences.navigation == .topBar
        NavigationSplitView(columnVisibility: Binding(
            get: { usesTopBar || (app.preferences.sidebarHidden && !journeyShowing) ? .detailOnly : .all },
            set: { visibility in
                guard !usesTopBar, !journeyShowing else { return }
                let hidden = visibility == .detailOnly
                if app.preferences.sidebarHidden != hidden { app.preferences.sidebarHidden = hidden }
            })) {
            AppSidebar(isInUse: !usesTopBar)
                // The sidebar button belongs to the sidebar column, so it is removed here.
                .toolbar(removing: usesTopBar ? .sidebarToggle : nil)
        } detail: {
            VStack(spacing: 0) {
                if let message = app.storageError {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DS.Space.m)
                        .padding(.vertical, DS.Space.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Palette.caution.opacity(0.1))
                    Divider()
                }
                switch app.section {
                case .muscleMemory:
                    LearnView()
                case .practice:
                    PracticeView(model: app.practice)
                case .test:
                    TestView(model: app.test, store: app.store, showProgress: { app.section = .progress },
                             trainFinger: app.trainFinger)
                case .focus:
                    FocusView(store: app.store) { app.section = .test }
                case .progress:
                    ProgressDashboardView(store: app.store, trainingStore: app.trainingStore,
                                          trainFinger: app.trainFinger, checkFinger: app.checkFinger,
                                          openMechanics: app.openMechanics)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(app.section.title)
            // Pages scroll under the top bar; with the sidebar they start below the window buttons.
            .floatingTopBar { if usesTopBar { AppTopBar() } }
            .ignoresSafeArea(.container, edges: usesTopBar ? .top : [])
        }
        .overlay {
            // Under the toolbar too, so the whole window dims evenly.
            if journeyShowing { WelcomeJourneyOverlay().ignoresSafeArea() }
        }
        .applying(app.preferences)
        .environment(app.preferences)
        .onChange(of: app.preferences.trainingPriority) { _, priority in app.mechanics.priority = priority.core }
        .onChange(of: journeyShowing, initial: true) { _, showing in KeyboardMonitor.journeyIsShowing = showing }
        .onChange(of: app.isExerciseRunning) { _, running in if !running { app.topBar.reveal() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            app.topBar.reveal()
        }
        .onAppear {
            let model = app
            KeyboardMonitor.onTypingKey = { model.topBar.noteTyping(exerciseRunning: model.isExerciseRunning) }
            model.topBar.startWatchingMouse()
        }
        .background(MouseMovedEnabler())
        // Help ▸ Take a Tour… and Settings ▸ Replay Tutorial both ask here.
        .alert("Take a Tour", isPresented: Binding(get: { app.journey.isChoosingMode },
                                                   set: { app.journey.isChoosingMode = $0 })) {
            Button("Quick Tour") { app.startTour(.quick) }
            Button("Full Tour") { app.startTour(.full) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(app.tourChoiceMessage)
        }
        .task {
            app.preferences.applyTheme()
            UIProbe.run(app)
            InputProbe.run(app); KeyRepetitionProbe.run(app); DailyFlowProbe.run(app); SettingsProbe.run(app)
            if OnboardingProbe.isEnabled {
                OnboardingProbe.run(app)
            } else if !UIProbe.isEnabled && !InputProbe.isActive && !SettingsProbe.isEnabled {
                app.presentWelcomeJourneyIfNeeded(savedKeys: app.launchDefaultsKeys)
            }
        }
    }
}

/// The five main places, floating at the top of the window. It fades while
/// you type (see `TopBarVisibility`) and keeps its space, so nothing moves.
private struct AppTopBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        GlassGroup(spacing: DS.Space.xs) {
            OptionBar(options: AppSection.allCases, selection: $app.section, style: .glass,
                      tour: (app.journey, { .section($0) }), symbol: { $0.symbol }) { $0.title }
                .topBarSurface()
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Main navigation")
                .contextMenu { NavigationSwitchMenu() }
                // Beside the bar, not in it, so the five sections stay centred.
                .overlay(alignment: .trailing) {
                    NavigationSwitchButton(to: .sidebar)
                        .alignmentGuide(.trailing) { $0[.leading] - DS.Space.xs }
                }
        }
        .opacity(app.topBar.isFaded ? 0 : 1)
        .allowsHitTesting(!app.topBar.isFaded)
        .motion(DS.Motion.standard, value: app.topBar.isFaded)
        // A small gap above, as wide as the gap to the sidebar button, so the bar
        // doesn't press against the window's edge. The window buttons sit a
        // little above its middle.
        .padding(.top, 6)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        // The strip around the bar still moves the window.
        .background {
            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
    }
}

/// The five main places down the left side. On macOS 26 the system draws
/// it as Liquid Glass and handles selection, Reduce Transparency and
/// Increase Contrast; nothing here paints over it.
private struct AppSidebar: View {
    @Environment(AppModel.self) private var app
    /// False while the top bar is in use and this column is closed.
    let isInUse: Bool

    var body: some View {
        @Bindable var app = app
        List(AppSection.allCases, selection: $app.section) { section in
            Label(section.title, systemImage: section.symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .tourTarget(.section(section), in: app.journey, when: isInUse)
                .tag(section)
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Main navigation")
        .contextMenu { NavigationSwitchMenu() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                NavigationSwitchButton(to: .topBar)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.xs)
            .padding(.bottom, DS.Space.xs)
        }
        .navigationSplitViewColumnWidth(min: 150, ideal: 172, max: 220)
    }
}

/// Moves the five sections to the other navigation. The same switch is in
/// the right-click menu, View ▸ Use Sidebar / Use Top Bar (⌥⌘S) and
/// Settings ▸ Appearance.
private struct NavigationSwitchButton: View {
    @Environment(AppModel.self) private var app
    let to: NavigationStyle

    var body: some View {
        let current = to.other
        Group {
            switch to {
            case .sidebar:
                Button { app.setNavigation(to) } label: {
                    Image(systemName: to.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                        .switchButtonSurface()
                }
                .buttonStyle(.plain)
            case .topBar:
                Button { app.setNavigation(to) } label: {
                    Label("Use Top Bar", systemImage: to.symbol)
                }
                .buttonStyle(.quiet)
            }
        }
        .help("Use \(to.title) (⌥⌘S)")
        .accessibilityLabel("Switch to \(to.title.lowercased())")
        .accessibilityValue("Navigation: \(current.title.lowercased())")
        .disabled(app.journey.isActive)
    }
}

/// Right-click on the top bar or the sidebar.
private struct NavigationSwitchMenu: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let other = app.preferences.navigation.other
        Button("Use \(other.title)") { app.setNavigation(other) }
            .disabled(app.journey.isActive)
    }
}

private extension View {
    /// The round switch beside the top bar: glass on macOS 26, material before.
    @ViewBuilder func switchButtonSurface() -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.interactive(), in: Circle())
        } else {
            background(.regularMaterial, in: Circle())
        }
    }
}

/// Windows report plain mouse movement only when asked.
private struct MouseMovedEnabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Reader() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Reader: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.acceptsMouseMovedEvents = true
        }
    }
}
