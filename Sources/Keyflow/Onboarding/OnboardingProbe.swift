import AppKit
import KeyflowCore
import SwiftUI

/// A scripted run of the Welcome Journey in the real window. Off unless
/// Keyflow is launched with `KEYFLOW_ONBOARDING_PROBE=<dir>`.
///
/// Uses in-memory history and unsaved preferences (`InputProbe.ephemeralApp`),
/// so nothing of yours is read or changed. The window's saved frame is left
/// alone (autosave is switched off before resizing).
///
/// It walks every step, checks the spotlight and arrow against the target's
/// real frame, resizes the window mid-tour, types the sentence with a
/// mistake and a Delete as real key events, finishes, replays and skips.
/// Results go to `<dir>/onboarding.json` with PNG snapshots; then it quits.
/// Snapshots come from the view hierarchy, so Liquid Glass is not captured.
@MainActor
enum OnboardingProbe {
    static let directory: URL? = ProcessInfo.processInfo.environment["KEYFLOW_ONBOARDING_PROBE"].map { URL(fileURLWithPath: $0) }
    static var isEnabled: Bool { directory != nil }

    /// Reported by the overlay while probing.
    static var overlayFrame: CGRect?
    static var layout: TourLayout?

    private static var log: [[String: Any]] = []
    private static var failures: [String] = []

    static func run(_ app: AppModel) {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task { @MainActor in
            func wait(_ seconds: Double = 0.8) async { try? await Task.sleep(for: .seconds(seconds)) }
            await wait(1.5)
            guard let window else { finish(); return }
            window.setFrameAutosaveName("")
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            let originalSize = window.frame.size

            // A new user (no history, no saved keys) sees the welcome.
            app.presentWelcomeJourneyIfNeeded(savedKeys: [])
            await wait()
            expect(app.journey.stage == .welcome, "fresh user sees the welcome")
            expect(app.preferences.onboardingStatus == .notStarted, "status notStarted after presenting")
            snapshot("01-welcome")
            // The first welcome asks top bar or sidebar, and the window follows at once.
            expect(app.journey.isFirstLaunch, "the first welcome offers the navigation choice")
            app.setNavigation(.sidebar)
            await wait()
            expect(app.preferences.navigation == .sidebar, "choosing Sidebar on the welcome switches")
            snapshot("01b-welcome-sidebar")
            app.setNavigation(.topBar)
            await wait()
            expect(app.preferences.navigation == .topBar, "choosing Top Bar on the welcome switches back")

            app.journeyNext()
            expect(app.preferences.onboardingStatus == .inProgress, "status inProgress after Start Journey")
            for index in TourStep.all.indices {
                await wait()
                let step = TourStep.all[index]
                expect(app.section == step.section, "step \(index + 1) shows \(step.section.title)")
                checkStep("step-\(index + 1)", step, app)
                snapshot(String(format: "%02d-step-%d-%@", index + 2, index + 1, step.title.replacingOccurrences(of: " ", with: "-")))

                if index == 1 {
                    // Typing during the tour reaches nothing behind it.
                    post("a", keyCode: 0)
                    await wait(0.4)
                    expect(app.practice.phase == .idle && app.practice.engine.position == 0, "typing during the tour leaves Practice alone")
                }
                if index == 2 {
                    window.setContentSize(NSSize(width: 960, height: 660))
                    await wait()
                    checkStep("step-3-resized-small", step, app)
                    snapshot("04b-step-3-resized")
                    window.setContentSize(NSSize(width: 1400, height: 860))
                    await wait()
                    checkStep("step-3-resized-large", step, app)
                    window.setContentSize(window.contentRect(forFrameRect: NSRect(origin: .zero, size: originalSize)).size)
                    await wait()
                }
                if index == TourStep.all.count - 1 {
                    // This tab is centred, so it moves with the window: the arrow must follow.
                    let before = app.journey.targetFrames[step.target]
                    window.setContentSize(NSSize(width: 940, height: 640))
                    await wait()
                    expect(app.journey.targetFrames[step.target] != before, "Typing Mechanics tab moved with the resize")
                    checkStep("step-6-resized-small", step, app)
                    snapshot("07b-step-6-resized")
                    window.setContentSize(window.contentRect(forFrameRect: NSRect(origin: .zero, size: originalSize)).size)
                    await wait()
                    checkStep("step-6-restored", step, app)
                }
                app.journeyNext()
            }

            await wait()
            expect(app.journey.stage == .typing, "the tour leads to the first typing exercise")
            snapshot("08-typing-start")
            type("My typing journey starts herr")
            await wait(0.6)
            expect(app.journey.hasMistakeShowing, "a mistake shows in red")
            expect(app.journey.stage == .typing, "a mistake is not a failure")
            snapshot("09-typing-mistake")
            post("\u{7F}", keyCode: KeyPress.delete)
            await wait(0.3)
            expect(String(app.journey.engine.typed) == "My typing journey starts her", "Delete removes the mistake")
            type("e.")
            await wait()
            let completed: Bool = if case .complete = app.journey.stage { true } else { false }
            expect(completed, "typing the sentence correctly completes it")
            expect(app.preferences.onboardingStatus == .completed, "status completed")
            let hasSummary: Bool = if case .complete(let summary) = app.journey.stage { summary != nil } else { false }
            expect(hasSummary, "the Full Tour completion shows time and accuracy")
            expect(app.practice.engine.position == 0 && app.test.engine.position == 0 && app.muscleMemory.engine.position == 0
                   && app.fingerFocus.engine.position == 0 && app.mechanics.engine.position == 0,
                   "no typing reached Practice, Test or Learn")
            expect((app.store?.summaries.isEmpty ?? true) && (app.trainingStore?.events.isEmpty ?? true),
                   "the exercise saved no session or training record")
            snapshot("10-complete")

            app.finishJourney(startLearning: true)
            await wait()
            expect(!app.journey.isActive && app.section == .muscleMemory, "Start Learning opens Learn")
            post("x", keyCode: 7)
            await wait(0.4)
            expect(app.muscleMemory.engine.position == 1, "typing reaches Learn again after the journey")
            app.muscleMemory.restart()
            snapshot("11-after")

            // A returning user: the saved status must survive every replay.
            app.preferences.onboardingStatus = .skipped

            // Help ▸ Take a Tour…, chosen from the real menu bar, in Dark appearance.
            app.preferences.theme = .dark
            app.section = .progress
            await wait(0.4)
            expect(clickMenu("Help", "Take a Tour…"), "Help ▸ Take a Tour… is in the menu bar and enabled")
            await wait()
            expect(app.journey.isChoosingMode && !app.journey.isActive, "Take a Tour asks Full or Quick first")
            let choice = alertText()
            entryNote("chooserText", choice)
            expect(choice.contains("Quick Tour") && choice.contains("Full Tour") && choice.contains("Cancel"),
                   "the choice offers Quick Tour, Full Tour and Cancel")
            snapshot("12-take-a-tour-choice")
            expect(clickAlertButton("Quick Tour"), "chose Quick Tour")
            await wait()
            expect(app.journey.mode == .quick && app.journey.stage == .tour(0), "Quick Tour starts on Learn, with no welcome")
            expect(!app.journey.canGoBack, "nothing before the first Quick Tour step")
            for index in TourStep.all.indices {
                await wait()
                checkStep("quick-step-\(index + 1)", TourStep.all[index], app)
                if index == 0 { snapshot("13-quick-step-1-dark") }
                if index == TourStep.all.count - 1 { snapshot("14-quick-step-6-dark") }
                app.journeyNext()
            }
            await wait()
            expect(app.journey.stage == .complete(nil), "Quick Tour ends with no typing exercise")
            snapshot("15-quick-complete-dark")
            app.finishJourney(startLearning: false)
            await wait()
            expect(app.section == .progress && !app.journey.isActive, "Back to Keyflow returns to Progress")
            expect(app.preferences.onboardingStatus == .skipped, "a Quick Tour leaves the saved status alone")
            app.preferences.theme = .system

            // A running Practice: the choice warns, and Cancel keeps it running.
            app.section = .practice
            await wait(0.5)
            type("the")
            await wait(0.4)
            let typedBefore = app.practice.engine.position
            expect(app.practice.phase == .running, "a Practice session is running")
            app.requestTour()          // what Settings ▸ Replay Tutorial calls
            await wait()
            let warning = alertText()
            expect(warning.contains("Practice session in progress will end"), "the choice warns about the running Practice")
            snapshot("16-choice-with-running-practice")
            expect(clickAlertButton("Cancel"), "chose Cancel")
            await wait()
            expect(!app.journey.isActive && app.practice.phase == .running && app.practice.engine.position == typedBefore,
                   "Cancel leaves the session exactly as it was")
            app.requestTour()
            await wait()
            expect(clickAlertButton("Full Tour"), "chose Full Tour")
            await wait()
            expect(app.journey.stage == .welcome && app.journey.mode == .full, "a replayed Full Tour starts at the welcome")
            expect(app.practice.phase == .idle && (app.store?.summaries.isEmpty ?? true),
                   "continuing ended the Practice without saving it")
            app.startJourney()
            expect(app.preferences.onboardingStatus == .skipped, "starting a replay does not mark it in progress")
            await wait()
            app.skipJourney()
            await wait()
            expect(app.preferences.onboardingStatus == .skipped, "skipping a replay leaves the saved status alone")
            expect(app.section == .practice, "skipping returns to the section the tour started from")

            expect(!app.topBar.isFaded, "the top bar is showing after the journey")

            // The same tour in sidebar mode, starting with the sidebar hidden:
            // the tour shows it, points at it, says so, and hides it again after.
            app.setNavigation(.sidebar)
            app.preferences.sidebarHidden = true
            app.section = .focus
            await wait()
            expect(TourStep.all[0].location(.sidebar) == "Learn, in the sidebar", "the tour says \"in the sidebar\"")
            app.startTour(.quick)
            for index in TourStep.all.indices {
                await wait()
                let step = TourStep.all[index]
                checkStep("sidebar-step-\(index + 1)", step, app)
                if index == 0 || index == TourStep.all.count - 1 {
                    snapshot(String(format: "20-sidebar-step-%d", index + 1))
                }
                app.journeyNext()
            }
            await wait()
            app.finishJourney(startLearning: false)
            await wait()
            expect(app.preferences.sidebarHidden && app.preferences.navigation == .sidebar,
                   "the sidebar goes back to hidden after the tour")
            expect(app.section == .focus, "the sidebar tour returns to where it started")
            app.preferences.sidebarHidden = false
            app.setNavigation(.topBar)

            finish()
        }
    }

    // MARK: Checks

    private static func checkStep(_ name: String, _ step: TourStep, _ app: AppModel) {
        var entry: [String: Any] = ["check": name, "target": "\(step.target)"]
        guard let overlay = overlayFrame, let frame = app.journey.targetFrames[step.target], let layout else {
            failures.append("\(name): no layout (overlay \(overlayFrame != nil), target \(app.journey.targetFrames[step.target] != nil), layout \(layout != nil))")
            log.append(entry)
            return
        }
        let target = TourLayout.local(frame, in: overlay)
        entry["targetFrame"] = rect(target)
        entry["spotlight"] = rect(layout.spotlight)
        entry["popover"] = rect(layout.popover)
        entry["arrowEnd"] = [layout.arrowEnd.x, layout.arrowEnd.y]
        entry["side"] = "\(layout.side)"
        entry["overlay"] = rect(overlay)

        expect(layout.spotlight.contains(target), "\(name): spotlight covers the target")
        expect(!layout.popover.intersects(layout.spotlight), "\(name): panel does not cover the target")
        let bounds = CGRect(origin: .zero, size: overlay.size)
        expect(bounds.contains(layout.popover), "\(name): panel inside the window")
        let around = layout.spotlight.insetBy(dx: -(TourLayout.arrowClearance + 1), dy: -(TourLayout.arrowClearance + 1))
        expect(around.contains(layout.arrowEnd) && !layout.spotlight.contains(layout.arrowEnd),
               "\(name): arrow ends just outside the target")

        // A main section is in the window's top strip, with its panel below,
        // or down the left side in sidebar mode.
        if case .section(let section) = step.target {
            if app.preferences.navigation == .topBar {
                expect(target.midY < 60, "\(name): the \(section.title) tab is in the top bar")
                expect(layout.side == .below, "\(name): panel sits below the \(section.title) tab")
            } else {
                expect(target.maxX < 260 && target.midY > 30, "\(name): \(section.title) is in the sidebar")
            }
        }
        log.append(entry)
    }

    private static func expect(_ condition: Bool, _ what: String) {
        log.append(["expect": what, "passed": condition])
        if !condition { failures.append(what) }
    }

    private static func entryNote(_ key: String, _ value: Any) { log.append([key: value]) }

    /// Chooses a menu item from the real menu bar, as a click would.
    private static func clickMenu(_ menu: String, _ item: String) -> Bool {
        guard let submenu = NSApp.mainMenu?.items.first(where: { $0.title == menu })?.submenu else { return false }
        submenu.update()
        guard let index = submenu.items.firstIndex(where: { $0.title == item }), submenu.items[index].isEnabled else { return false }
        submenu.performActionForItem(at: index)
        return true
    }

    /// The alert sheet on the main window, if one is showing.
    private static var alertSheet: NSWindow? { window?.attachedSheet }

    private static func allViews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(allViews) }

    /// Every label and button title in the alert.
    private static func alertText() -> String {
        guard let content = alertSheet?.contentView else { return "" }
        return allViews(content).compactMap { view -> String? in
            if let button = view as? NSButton { return button.title }
            if let field = view as? NSTextField { return field.stringValue }
            return nil
        }.joined(separator: " | ")
    }

    private static func clickAlertButton(_ title: String) -> Bool {
        guard let content = alertSheet?.contentView,
              let button = allViews(content).compactMap({ $0 as? NSButton }).first(where: { $0.title == title }) else { return false }
        button.performClick(nil)
        return true
    }

    private static func rect(_ r: CGRect) -> [Double] {
        [r.minX, r.minY, r.width, r.height].map { (Double($0) * 10).rounded() / 10 }
    }

    // MARK: Window

    private static var window: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.identifier != KeyboardMonitor.settingsWindowID && $0.contentView != nil && $0.title != "" }
    }

    /// Real key-down events through AppKit's queue and the local monitors.
    private static func post(_ characters: String, keyCode: UInt16) {
        guard let window else { return }
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                     windowNumber: window.windowNumber, context: nil, characters: characters,
                                     charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
        if let event { NSApp.postEvent(event, atStart: false) }
    }

    private static func type(_ text: String) {
        for character in text { post(String(character), keyCode: character == " " ? 49 : 0) }
    }

    private static func snapshot(_ name: String) {
        guard let view = window?.contentView, let directory,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name).png"))
        if let number = view.window?.windowNumber, let image = KeyRepetitionProbe.liveImage(of: number),
           let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            try? png.write(to: directory.appending(path: "live-" + "\(name).png"))
        }
    }

    private static func finish() {
        log.append(["failures": failures, "passed": failures.isEmpty])
        if let directory, let data = try? JSONSerialization.data(withJSONObject: log, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appending(path: "onboarding.json"))
        }
        NSApp.terminate(nil)
    }
}
