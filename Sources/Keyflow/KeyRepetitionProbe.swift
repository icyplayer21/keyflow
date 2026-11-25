import AppKit
import KeyflowCore
import SwiftUI

/// `KEYFLOW_REPETITION_PROBE=<dir>`: drives Learn ▸ Key Repetition in the
/// real window with posted key events (the same path real typing takes
/// through the local key monitor), then writes `repetition.json` and window
/// snapshots to `<dir>`. Uses in-memory storage and no saved settings, so
/// nothing of the user's is touched. Off unless the variable is set.
@MainActor
enum KeyRepetitionProbe {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["KEYFLOW_REPETITION_PROBE"] != nil }

    private static var checks: [[String: Any]] = []

    private static func check(_ name: String, _ ok: Bool, _ detail: Any = "") {
        checks.append(["name": name, "ok": ok, "detail": "\(detail)"])
    }

    static func run(_ app: AppModel) {
        guard let path = ProcessInfo.processInfo.environment["KEYFLOW_REPETITION_PROBE"] else { return }
        let directory = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            let model = { app.keyRepetition }
            app.section = .muscleMemory
            app.learnMode = .keyRepetition
            // KEYFLOW_PROBE_LIGHT: run in light mode, whatever the system is set to.
            if ProcessInfo.processInfo.environment["KEYFLOW_PROBE_LIGHT"] != nil {
                NSApp.appearance = NSAppearance(named: .aqua)
            }
            NSApp.activate()
            let window = NSApp.windows.first { $0.isVisible && $0.canBecomeKey }
            window?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(1))
            let number = window?.windowNumber ?? 0
            var t = ProcessInfo.processInfo.systemUptime

            @MainActor func key(_ c: String, code: UInt16 = 0, flags: NSEvent.ModifierFlags = [], repeat isRepeat: Bool = false) {
                t += 0.12
                post(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: t,
                                      windowNumber: number, context: nil, characters: c,
                                      charactersIgnoringModifiers: c.lowercased(), isARepeat: isRepeat, keyCode: code))
            }
            /// S with modifiers, as the keyboard sends it (key code 1).
            @MainActor func shortcutS(_ flags: NSEvent.ModifierFlags) {
                t += 0.12
                let characters = flags.contains(.control) ? "\u{13}" : (flags.contains(.option) ? "ß" : "s")
                post(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: t,
                                      windowNumber: number, context: nil, characters: characters,
                                      charactersIgnoringModifiers: "s", isARepeat: false, keyCode: 1))
            }
            @MainActor func modifier(_ code: UInt16, _ flags: NSEvent.ModifierFlags) {
                t += 0.05
                post(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: flags, timestamp: t,
                                      windowNumber: number, context: nil, characters: "",
                                      charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
            }
            @MainActor func settle(_ seconds: Double = 0.6) async { try? await Task.sleep(for: .seconds(seconds)) }
            @MainActor func snapshot(_ name: String) {
                guard let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name).png"))
                // The window as the system composited it, which is the only view that includes Liquid Glass.
                if let image = liveImage(of: number),
                   let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                    try? png.write(to: directory.appending(path: "\(name)-live.png"))
                }
            }

            // 1. Setup: the screen shows the default key; typing a letter chooses it.
            check("opens in setup", model().stage == .setup)
            check("default goal is 50", model().goal == 50, model().goal)
            check("no new main destination", AppSection.allCases.count == 5)
            let viewMenu = NSApp.mainMenu?.items.first { $0.title == "View" }?.submenu
            let shortcuts = AppSection.allCases.enumerated().map { index, section in
                viewMenu?.items.first { $0.title == section.title }?.keyEquivalent == "\(index + 1)"
            }
            check("View menu keeps ⌘1 to ⌘5", shortcuts.allSatisfy { $0 }, shortcuts)
            /// The View menu as it is when opened: SwiftUI refreshes a menu's items as it opens.
            @MainActor func menuItem(_ title: String) -> NSMenuItem? {
                let menu = NSApp.mainMenu?.items.first { $0.title == "View" }?.submenu
                if let menu { menu.delegate?.menuNeedsUpdate?(menu); menu.update() }
                return menu?.items.first { $0.title == title }
            }
            @MainActor func viewTitles() -> [String] {
                (NSApp.mainMenu?.items.first { $0.title == "View" }?.submenu?.items ?? []).map(\.title)
            }
            @MainActor func sidebarWidth() -> CGFloat {
                guard let split = window.flatMap({ findSplit($0.contentView) }), let column = split.arrangedSubviews.first,
                      split.arrangedSubviews.count > 1, !split.isSubviewCollapsed(column) else { return 0 }
                return column.frame.width
            }
            check("starts with the top bar", app.preferences.navigation == .topBar)
            check("View ▸ Use Sidebar is ⌥⌘S", menuItem("Use Sidebar").map { $0.keyEquivalent == "s" && $0.keyEquivalentModifierMask == [.command, .option] } ?? false)
            check("no Hide Sidebar command in top bar mode", menuItem("Hide Sidebar") == nil && menuItem("Show Sidebar") == nil)
            check("sidebar closed in top bar mode", sidebarWidth() == 0, sidebarWidth())
            snapshot("1-setup")
            key("p", code: 35)
            await settle()
            check("typing P in setup chooses P", model().letter == "p", model().letter)
            check("recommended finger for P", model().fingerName == "Right pinky", model().fingerName)
            model().setGoal(25)
            await settle(0.3)
            snapshot("2-setup-p-25")

            // 2. Return starts.
            key("\r", code: 36)
            await settle()
            check("Return starts training", model().stage == .training)
            snapshot("3-training-start")

            // 3. Ten presses, a wrong key, a held key, Shift and Caps Lock alone, space.
            for _ in 0..<10 { key("p", code: 35) }
            key("o", code: 31)
            key("p", code: 35)
            for _ in 0..<40 { key("p", code: 35, repeat: true) }   // held: auto-repeat
            modifier(56, .shift); modifier(56, [])                  // Shift alone
            modifier(57, .capsLock)                                 // Caps Lock on
            key("P", code: 35, flags: .capsLock)                    // capital P with Caps Lock
            modifier(57, [])
            modifier(56, .shift); key("P", code: 35, flags: .shift); modifier(56, [])  // Shift+P
            key(" ", code: 49)
            await settle()
            check("separate presses counted once each", model().counter.correct == 13, model().counter.correct)
            check("wrong key is one error", model().counter.incorrect == 1, model().counter.incorrect)
            check("auto-repeat ignored", model().counter.attempts == 14, model().counter.attempts)
            check("feedback names the typed key", model().recent.contains { $0.typed == "o" })
            check("top bar fades while typing", app.topBar.isFaded)
            snapshot("4-training-mid")

            // 4. Esc pauses; presses while paused don't count; Esc resumes.
            key("\u{1b}", code: 53)
            await settle(0.3)
            check("Esc pauses", model().isPaused)
            check("top bar returns on pause", !app.topBar.isFaded)
            for _ in 0..<3 { key("p", code: 35) }
            await settle(0.3)
            check("presses while paused ignored", model().counter.correct == 13, model().counter.correct)
            snapshot("5-paused")
            key("\u{1b}", code: 53)
            await settle(0.3)
            check("Esc resumes", !model().isPaused)

            // 5. Going to another section keeps the session (paused), coming back continues it.
            app.section = .practice
            await settle()
            check("leaving Learn pauses, keeps progress", model().isPaused && model().counter.correct == 13 && model().stage == .training,
                  "\(model().isPaused) \(model().counter.correct)")
            app.section = .muscleMemory
            await settle()
            check("session still there on return", model().stage == .training && model().counter.correct == 13)
            key("\u{1b}", code: 53)
            await settle(0.3)

            // 6. Focus loss pauses.
            NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
            await settle(0.3)
            check("app losing focus pauses", model().isPaused)
            key("\u{1b}", code: 53)
            await settle(0.3)

            // 7. Finish exactly at the goal.
            for _ in 0..<6 { key("p", code: 35) }
            await settle(0.8)
            snapshot("5b-growing-19")
            for _ in 0..<5 { key("p", code: 35) }
            await settle()
            snapshot("5c-near-goal")
            check("not finished one short of the goal", model().stage == .training && model().counter.remaining == 1,
                  model().counter.remaining)
            key("p", code: 35)
            await settle()
            check("explosion plays after the goal", model().showsBurst)
            // Window snapshots can't capture a live Canvas, so its frames are rendered directly.
            let burstArea = window?.contentView?.bounds.size ?? CGSize(width: 1000, height: 700)
            let burstFont = KeyRepetitionGrowth.endFontSize(area: burstArea, metrics: .of("P"))
            let burstArt = KeyRepetitionLetterArt.make(letter: "P", fontSize: burstFont, dark: true, scale: 2, seed: 7)
            let burstSparks = KeyRepetitionParticle.make(count: 46, seed: 7)
            check("letter shatters into about 150 pieces", (100...240).contains(burstArt?.pieces.count ?? 0), burstArt?.pieces.count ?? 0)
            var renderMs: [Double] = []
            for moment in [0.0, 0.09, 0.15, 0.19, 0.3, 0.55, 0.9] {
                let frame = KeyRepetitionBurstFrame(letter: "P", area: burstArea, art: burstArt, sparks: burstSparks, time: moment)
                    .frame(width: burstArea.width, height: burstArea.height)
                    .background(Color(white: 0.12))
                    .environment(\.colorScheme, .dark)
                let renderer = ImageRenderer(content: frame)
                renderer.scale = 2
                let before = ProcessInfo.processInfo.systemUptime
                let image = renderer.cgImage
                renderMs.append((ProcessInfo.processInfo.systemUptime - before) * 1000)
                if let image, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                    try? png.write(to: directory.appending(path: "burst-\(Int(moment * 100)).png"))
                }
            }
            check("explosion frames rendered", renderMs.count == 7, renderMs.map { Int($0) })
            let smallFont = KeyRepetitionGrowth.fontSize(progress: 0.5, area: burstArea, metrics: .of("P"))
            let smallArt = KeyRepetitionLetterArt.make(letter: "P", fontSize: smallFont, dark: true, scale: 2, seed: 7, power: 0.5)
            let smallFrame = KeyRepetitionBurstFrame(letter: "P", area: burstArea, art: smallArt,
                                                     sparks: KeyRepetitionParticle.make(count: 29, seed: 7), time: 0.3, power: 0.5)
                .frame(width: burstArea.width, height: burstArea.height)
                .background(Color(white: 0.12))
                .environment(\.colorScheme, .dark)
            let smallRenderer = ImageRenderer(content: smallFrame)
            smallRenderer.scale = 2
            if let image = smallRenderer.cgImage, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try? png.write(to: directory.appending(path: "burst-small.png"))
            }
            try? await Task.sleep(for: .seconds(KeyRepetitionBurstView.duration + 0.4))
            check("explosion hands over to the results", !model().showsBurst)
            var first: KeyRepetitionEvent?
            if case .complete(let event) = model().stage { first = event }
            check("finishes at exactly 25", first?.result.correct == 25, first?.result.correct ?? -1)
            check("errors carried to result", first?.result.incorrect == 1)
            check("accuracy = correct ÷ attempts", first.map { abs($0.result.accuracy - 25.0 / 26.0) < 1e-9 } ?? false,
                  first?.result.accuracy ?? -1)
            check("duration excludes pauses (positive, finite)", (first?.result.duration ?? -1) > 0, first?.result.duration ?? -1)
            check("saved once", app.trainingStore?.keyRepetitionEvents.count == 1)
            key("p", code: 35)
            await settle(0.3)
            check("presses after completion change nothing", app.trainingStore?.keyRepetitionEvents.count == 1)
            check("extra press stays on Key Repetition (nothing else in the window reacts)",
                  app.section == .muscleMemory && app.learnMode == .keyRepetition, app.section.rawValue)
            snapshot("6-complete")

            // 8. Return repeats; Return to Home mode.
            key("\r", code: 36)
            await settle()
            check("Return repeats with the same key", model().stage == .training && model().counter.letter == "p")

            // Slowing down: the letter drains, the count does not, Esc freezes it.
            t = ProcessInfo.processInfo.systemUptime
            for _ in 0..<6 { key("p", code: 35) }
            await settle(0.2)
            let full = model().letterLevel()
            await settle(2.6)
            let drained = model().letterLevel()
            check("stopping shrinks the letter", drained < full, "\(full) -> \(drained)")
            check("shrinking keeps the count", model().counter.correct == 6, model().counter.correct)
            check("top bar returns after a pause in typing", !app.topBar.isFaded)
            snapshot("5d-shrinking")
            key("\u{1b}", code: 53)
            await settle(0.2)
            let frozen = model().letterLevel()
            await settle(0.6)
            check("pause freezes the letter", model().isPaused && model().letterLevel() == frozen, "\(frozen)")
            key("\u{1b}", code: 53)
            await settle(0.1)
            let beforePress = model().letterLevel()
            t = ProcessInfo.processInfo.systemUptime
            key("p", code: 35)
            await settle(0.05)
            check("top bar fades again on the next press", app.topBar.isFaded)
            // A real mouse-move event through AppKit's queue.
            for x in [200.0, 260.0] {
                post(NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: x, y: 200), modifierFlags: [],
                                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: number, context: nil,
                                        eventNumber: 0, clickCount: 0, pressure: 0))
            }
            await settle(0.2)
            check("moving the mouse brings the top bar back", !app.topBar.isFaded)
            check("a correct press wins size back", model().letterLevel() > beforePress && model().counter.correct == 7,
                  "\(beforePress) -> \(model().letterLevel())")

            model().exit()
            model().mode = .returnToHome
            model().select("a")
            model().setGoal(5)
            model().start()
            await settle(0.3)
            key("a", code: 0)
            await settle(0.4)
            snapshot("7-return-home")
            for _ in 0..<4 { key("a", code: 0) }
            await settle()
            model().finishBurst()
            var second: KeyRepetitionEvent?
            if case .complete(let event) = model().stage { second = event }
            check("Return to Home session saved with its mode", second?.result.mode == .returnToHome && second?.result.letter == "a")
            check("two sessions stored", app.trainingStore?.keyRepetitionEvents.count == 2)

            // 9. Progress shows the per-key table; other histories unaffected.
            app.section = .progress
            await settle(1.2)
            snapshot("8-progress")
            let history = KeyRepetitionHistory(events: app.trainingStore?.keyRepetitionEvents ?? [])
            check("history has P and A", Set(history.keys.map(\.letter)) == ["p", "a"])
            check("other Learn history untouched",
                  app.trainingStore.map { $0.events.isEmpty && $0.fingerFocusEvents.isEmpty && $0.mechanicsEvents.isEmpty } ?? false)
            check("no typing sessions created", app.store?.summaries.isEmpty ?? true)

            // The deepest navigation in the app, to review its levels.
            app.section = .muscleMemory
            app.learnMode = .mechanics
            await settle(0.9)
            snapshot("9-mechanics")

            // 10. Switching to the sidebar mid-exercise keeps the exercise.
            app.learnMode = .keyRepetition
            model().exit()
            model().mode = .continuous
            model().select("f")
            model().setGoal(50)
            model().start()
            await settle(0.3)
            t = ProcessInfo.processInfo.systemUptime
            for _ in 0..<3 { key("f", code: 3) }
            await settle(0.3)
            app.setNavigation(.sidebar)
            await settle(0.9)
            check("switched to the sidebar", app.preferences.navigation == .sidebar)
            check("sidebar is showing", sidebarWidth() > 100, sidebarWidth())
            check("switching keeps the exercise", model().stage == .training && model().counter.correct == 3
                  && app.section == .muscleMemory && app.learnMode == .keyRepetition, model().counter.correct)
            check("top bar is back on screen to switch from", !app.topBar.isFaded)
            for _ in 0..<2 { key("f", code: 3) }
            await settle(0.3)
            check("typing still counts in sidebar mode", model().counter.correct == 5, model().counter.correct)
            check("View ▸ Use Top Bar is ⌥⌘S", menuItem("Use Top Bar")?.keyEquivalentModifierMask == [.command, .option], viewTitles())
            check("View ▸ Hide Sidebar is ⌃⌘S", menuItem("Hide Sidebar").map { $0.keyEquivalent == "s" && $0.keyEquivalentModifierMask == [.command, .control] } ?? false)
            snapshot("10-sidebar-training")
            // The real shortcut, as a key press: ⌃⌘S.
            shortcutS([.command, .control])
            await settle(0.9)
            check("⌃⌘S hides the sidebar", app.preferences.sidebarHidden && sidebarWidth() == 0, sidebarWidth())
            check("hiding it keeps the exercise", model().stage == .training && model().counter.correct == 5)
            snapshot("11-sidebar-hidden")
            app.toggleSidebar()
            await settle(0.9)
            check("⌃⌘S shows it again", !app.preferences.sidebarHidden && sidebarWidth() > 100, sidebarWidth())
            app.section = .progress
            await settle(1.2)
            snapshot("12-sidebar-progress")
            app.section = .muscleMemory
            app.learnMode = .mechanics
            await settle(0.9)
            snapshot("13-sidebar-mechanics")
            app.learnMode = .keyRepetition
            await settle(0.4)
            // ⌥⌘S, as a key press.
            shortcutS([.command, .option])
            await settle(0.9)
            check("back to the top bar", app.preferences.navigation == .topBar && sidebarWidth() == 0, sidebarWidth())
            check("the exercise survived both switches", model().stage == .training && model().counter.correct == 5)
            check("View ▸ Use Sidebar again", menuItem("Use Sidebar") != nil && menuItem("Hide Sidebar") == nil)
            snapshot("14-top-bar-again")
            model().exit()

            let output: [String: Any] = [
                "checks": checks,
                "passed": checks.filter { $0["ok"] as? Bool == true }.count,
                "failed": checks.filter { $0["ok"] as? Bool != true }.map { $0["name"] ?? "" },
                "window": [window?.frame.width ?? 0, window?.frame.height ?? 0],
            ]
            let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            try? data?.write(to: directory.appending(path: "repetition.json"))
            NSApp.terminate(nil)
        }
    }

    private static func findSplit(_ view: NSView?) -> NSSplitView? {
        guard let view else { return nil }
        if let split = view as? NSSplitView { return split }
        for child in view.subviews { if let found = findSplit(child) { return found } }
        return nil
    }

    /// This app's own window from the window server. Looked up at run time
    /// because the call is hidden from newer SDKs; nil if the system refuses.
    static func liveImage(of windowNumber: Int) -> CGImage? {
        typealias Capture = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let capture = unsafeBitCast(symbol, to: Capture.self)
        return capture(.null, 8, UInt32(windowNumber), 1 | 8)?.takeRetainedValue()
    }

    private static func post(_ event: NSEvent?) {
        if let event { NSApp.postEvent(event, atStart: false) }
    }
}
