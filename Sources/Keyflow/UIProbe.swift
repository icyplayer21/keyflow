import AppKit
import KeyflowCore
import SwiftUI

/// A diagnostic run of the real window, for checking layout without screen
/// recording. Off unless the app is launched with `KEYFLOW_UI_PROBE=<dir>`.
///
/// It types into Practice through the normal key handler, recording at each
/// step where the passage is and a snapshot of the window. Results go to
/// `<dir>/probe.json` and PNGs, then the app quits. Snapshots come from the view hierarchy, so system materials
/// such as Liquid Glass are not captured.
@MainActor
enum UIProbe {
    static let directory: URL? = ProcessInfo.processInfo.environment["KEYFLOW_UI_PROBE"].map { URL(fileURLWithPath: $0) }
    static var isEnabled: Bool { directory != nil }
    private(set) static var passage: CGRect = .zero
    private static var log: [[String: Any]] = []

    static func record(passage frame: CGRect) { passage = frame }

    static func run(_ app: AppModel) {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            app.section = .practice
            try? await Task.sleep(for: .seconds(1))
            step("idle", app)

            type(6, into: app.practice)
            try? await Task.sleep(for: .seconds(1))
            step("typing", app)

            app.restartCurrent()
            try? await Task.sleep(for: .seconds(1))
            step("restarted", app)

            type(4, into: app.practice)
            try? await Task.sleep(for: .seconds(1))
            step("typing-again", app)

            app.restartCurrent()
            app.section = .muscleMemory
            try? await Task.sleep(for: .seconds(1))
            step("learn", app)

            // Typing polish, as really drawn: a finished line fades back, the
            // stats and top bar step back while typing, and a finished lesson
            // passage sweeps before its results.
            app.section = .practice
            try? await Task.sleep(for: .seconds(1))
            type(70, into: app.practice)
            app.topBar.noteTyping(exerciseRunning: app.isExerciseRunning)
            try? await Task.sleep(for: .seconds(0.6))
            live("practice-typing")
            app.topBar.reveal()
            app.restartCurrent()

            app.section = .muscleMemory
            app.learnMode = .lessons
            try? await Task.sleep(for: .seconds(1))
            var time = ProcessInfo.processInfo.systemUptime
            while app.muscleMemory.phase != .finished, app.muscleMemory.engine.position < app.muscleMemory.engine.target.count {
                let next = app.muscleMemory.engine.target[app.muscleMemory.engine.position]
                _ = app.muscleMemory.handle(KeyPress(keyCode: next == " " ? 49 : 0, characters: String(next),
                                                     hasCommandOrControl: false, hasOption: false, timestamp: time))
                time += 0.2
            }
            try? await Task.sleep(for: .seconds(0.18))
            live("lesson-sweep")
            try? await Task.sleep(for: .seconds(0.9))
            live("lesson-results")

            let data = try? JSONSerialization.data(withJSONObject: log, options: [.prettyPrinted, .sortedKeys])
            try? data?.write(to: directory.appending(path: "probe.json"))
            NSApp.terminate(nil)
        }
    }

    private static func type(_ count: Int, into model: TypingSessionModel) {
        var time = ProcessInfo.processInfo.systemUptime
        for _ in 0..<count where model.engine.position < model.engine.target.count {
            let next = model.engine.target[model.engine.position]
            _ = model.handle(KeyPress(keyCode: 0, characters: String(next), hasCommandOrControl: false,
                                      hasOption: false, timestamp: time))
            time += 0.12
        }
    }

    private static func live(_ name: String) {
        let window = NSApp.windows.first { $0.isVisible && $0.canBecomeKey }
        guard let directory, let window, let image = KeyRepetitionProbe.liveImage(of: window.windowNumber) else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
            .write(to: directory.appending(path: "\(name)-live.png"))
    }

    private static func step(_ name: String, _ app: AppModel) {
        let window = NSApp.windows.first { $0.isVisible && $0.contentView != nil && $0.title != "" } ?? NSApp.windows.first
        var entry: [String: Any] = [
            "step": name,
            "passage": [passage.minX, passage.minY, passage.width, passage.height].map { ($0 * 10).rounded() / 10 },
            "practicePhase": "\(app.practice.phase)",
        ]
        if let window { entry["window"] = [window.frame.width, window.frame.height] }
        log.append(entry)

        guard let view = window?.contentView, let directory,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name).png"))
    }
}

extension View {
    /// Reports the typing passage's on-screen frame to `UIProbe` when probing.
    @ViewBuilder
    func probedPassage() -> some View {
        if UIProbe.isEnabled {
            onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { UIProbe.record(passage: $0) }
        } else {
            self
        }
    }
}

/// Diagnostics for Typing Mechanics' input layer. Off unless launched with
/// `KEYFLOW_INPUT_PROBE=<dir>` (scripted check, then quits) or
/// `KEYFLOW_INPUT_LOG=1` (prints what a real keyboard produces; type while
/// the Progress section is shown, where no typing screen takes the keys).
///
/// The scripted check posts real `NSEvent`s into Keyflow's own event queue,
/// so they travel the same path as hardware events: AppKit's queue, the
/// local monitor (`flagsChanged` and `keyDown`), then `ModifierTracker`.
@MainActor
enum InputProbe {
    private static let monitor = KeyboardMonitor()
    private static var tracker = ModifierTracker()

    /// `KEYFLOW_MECHANICS_PROBE=<dir>`: types a Caps Lock drill through the
    /// real Typing Mechanics screen. Uses in-memory storage and no saved
    /// settings, so nothing of yours is touched.
    static var isMechanicsProbe: Bool { ProcessInfo.processInfo.environment["KEYFLOW_MECHANICS_PROBE"] != nil }

    /// Any of the input diagnostics is running.
    static var isActive: Bool {
        let environment = ProcessInfo.processInfo.environment
        return ["KEYFLOW_MECHANICS_PROBE", "KEYFLOW_INPUT_PROBE", "KEYFLOW_INPUT_LOG", "KEYFLOW_REPETITION_PROBE", "KEYFLOW_DAILYFLOW_PROBE"].contains { environment[$0] != nil }
    }

    static func ephemeralApp() -> AppModel {
        AppModel(store: try? StatisticsStore.inMemory(), trainingStore: try? TrainingStore.inMemory(), defaults: nil)
    }

    static func run(_ app: AppModel) {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["KEYFLOW_MECHANICS_PROBE"] {
            mechanics(app, directory: URL(fileURLWithPath: path))
        } else if let path = environment["KEYFLOW_INPUT_PROBE"] {
            scripted(app, directory: URL(fileURLWithPath: path))
        } else if environment["KEYFLOW_INPUT_LOG"] != nil {
            app.section = .progress
            listen(log: true)
            print("Keyflow input log. Layout: \(KeyboardLayoutInfo.current().map { "\($0.name) (\($0.identifier))" } ?? "unknown")")
        }
    }

    private static func listen(log: Bool) {
        monitor.start({ press in
            guard let character = press.printableCharacter else { return false }
            let stroke = tracker.keystroke(character, keyCode: press.keyCode, at: press.timestamp,
                                           isRepeat: press.isRepeat, modifiers: press.modifiers)
            if log { print(describe(stroke)) }
            return false
        }, onModifier: { event in
            tracker.apply(event)
            if log { print("  \(event)") }
        })
    }

    private static func describe(_ stroke: ObservedKeystroke) -> String {
        let lead = stroke.shiftLead.map { String(format: " shift-lead %.0f ms", $0 * 1000) } ?? ""
        return "\(stroke.character)  \(stroke.technique.rawValue)\(lead)\(stroke.isRepeat ? " (repeat)" : "")\(stroke.reconciled ? " (corrected)" : "")"
    }

    private static func scripted(_ app: AppModel, directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            app.section = .progress
            NSApp.activate()
            let window = NSApp.windows.first { $0.isVisible && $0.canBecomeKey }
            window?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(0.5))
            listen(log: false)
            let number = window?.windowNumber ?? 0
            let t0 = ProcessInfo.processInfo.systemUptime
            let shift = ModifierSnapshot.shiftMask
            let L = ModifierSnapshot.leftShiftMask, R = ModifierSnapshot.rightShiftMask, caps = ModifierSnapshot.capsLockMask

            @MainActor func flags(_ keyCode: UInt16, _ raw: UInt, _ dt: Double) {
                post(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: .init(rawValue: raw),
                                      timestamp: t0 + dt, windowNumber: number, context: nil, characters: "",
                                      charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode))
            }
            @MainActor func key(_ c: String, _ raw: UInt, _ dt: Double, keyCode: UInt16, repeat isRepeat: Bool = false) {
                post(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .init(rawValue: raw),
                                      timestamp: t0 + dt, windowNumber: number, context: nil, characters: c,
                                      charactersIgnoringModifiers: c.lowercased(), isARepeat: isRepeat, keyCode: keyCode))
            }
            // "Pa": right-hand P with Left Shift (opposite hand), then a.
            flags(56, shift | L, 0.00); key("P", shift | L, 0.12, keyCode: 35); flags(56, 0, 0.18); key("a", 0, 0.30, keyCode: 0)
            // " NASA i": Caps Lock on, four capitals, off, lower case.
            key(" ", 0, 0.45, keyCode: 49)
            flags(57, caps, 0.60); for (i, c) in "NASA".enumerated() { key(String(c), caps, 0.75 + Double(i) * 0.1, keyCode: 45) }
            flags(57, 0, 1.25); key("i", 0, 1.40, keyCode: 34)
            // "!" with Right Shift, held long enough to repeat.
            flags(60, shift | R, 1.60); key("!", shift | R, 1.70, keyCode: 18); key("!", shift | R, 2.20, keyCode: 18, repeat: true); flags(60, 0, 2.30)
            // "Q" with Shift already down before typing began is covered by unit tests; here, a capital with no modifier.
            key("Q", 0, 2.50, keyCode: 12)

            try? await Task.sleep(for: .seconds(1))
            monitor.stop()
            let layout = KeyboardLayoutInfo.current()
            let result: [String: Any] = [
                "layout": layout?.identifier ?? "unknown",
                "layoutUSCompatible": layout?.isUSCompatible ?? false,
                "modifierEvents": tracker.modifierEvents.map { "\($0)".replacingOccurrences(of: "\(t0)", with: "t0") },
                "keystrokes": tracker.keystrokes.map { s in
                    ["char": String(s.character), "technique": s.technique.rawValue,
                     "shiftLeadMs": s.shiftLead.map { ($0 * 1000).rounded() } as Any,
                     "capsOnAfterT0Ms": s.capsLockOnAt.map { (($0 - t0) * 1000).rounded() } as Any,
                     "repeat": s.isRepeat, "corrected": s.reconciled] as [String: Any]
                },
            ]
            let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try? data?.write(to: directory.appending(path: "input.json"))
            NSApp.terminate(nil)
        }
    }

    private static func mechanics(_ app: AppModel, directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            app.section = .muscleMemory
            app.learnMode = .mechanics
            app.mechanics.select(.capsMixedCase)
            NSApp.activate()
            let window = NSApp.windows.first { $0.isVisible && $0.canBecomeKey }
            window?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(1))
            let number = window?.windowNumber ?? 0
            let text = Array(app.mechanics.text)
            let caps = ModifierSnapshot.capsLockMask, shift = ModifierSnapshot.shiftMask, L = ModifierSnapshot.leftShiftMask
            var t = ProcessInfo.processInfo.systemUptime
            var capsOn = false
            var guidance: [[String: Any]] = []
            for (i, c) in text.enumerated() {
                let upper = CaseRequirement.of(c) == .uppercaseLetter
                let run = upper && MechanicsDrill.uppercaseRun(around: i, in: text).count >= 2
                // Caps Lock for words in capitals, off before anything else; Left Shift for single capitals.
                if run != capsOn, c.isLetter || c == " " || c == "." {
                    capsOn = run
                    t += 0.07
                    post(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: .init(rawValue: capsOn ? caps : 0),
                                          timestamp: t, windowNumber: number, context: nil, characters: "",
                                          charactersIgnoringModifiers: "", isARepeat: false, keyCode: 57))
                }
                let single = upper && !run
                t += 0.14
                if single {
                    post(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: .init(rawValue: shift | L),
                                          timestamp: t - 0.09, windowNumber: number, context: nil, characters: "",
                                          charactersIgnoringModifiers: "", isARepeat: false, keyCode: 56))
                }
                let flags: UInt = (capsOn ? caps : 0) | (single ? shift | L : 0)
                post(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .init(rawValue: flags), timestamp: t,
                                      windowNumber: number, context: nil, characters: String(c),
                                      charactersIgnoringModifiers: String(c).lowercased(), isARepeat: false, keyCode: 0))
                if single {
                    post(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: .init(rawValue: capsOn ? caps : 0),
                                          timestamp: t + 0.03, windowNumber: number, context: nil, characters: "",
                                          charactersIgnoringModifiers: "", isARepeat: false, keyCode: 56))
                }
                if i == 1 {
                    // Let the queue drain, then read what the screen shows mid-word.
                    try? await Task.sleep(for: .seconds(0.4))
                    guidance.append(["afterTyping": String(text[0...1]), "capsLockIndicatorOn": app.mechanics.capsLockOn,
                                     "next": String(app.mechanics.nextKey ?? " "), "capsLockNeedsToggle": app.mechanics.capsLockNeedsToggle])
                }
            }
            try? await Task.sleep(for: .seconds(1.5))
            let result = app.mechanics.summary?.result

            // Capitalisation Lab: both halves of a comparison through the real window.
            app.mechanics.select(.capitalisationLab)
            try? await Task.sleep(for: .seconds(0.5))
            var labHalves: [[String: Any]] = []
            for _ in 0..<2 {
                let useCaps = app.mechanics.drill == .labCapsLockOnly
                let passage = Array(app.mechanics.text)
                var capsNow = false
                for c in passage {
                    let upper = CaseRequirement.of(c) == .uppercaseLetter
                    if useCaps, upper != capsNow, c.isLetter || c == " " {
                        capsNow = upper
                        t += 0.08
                        post(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: .init(rawValue: capsNow ? caps : 0),
                                              timestamp: t, windowNumber: number, context: nil, characters: "",
                                              charactersIgnoringModifiers: "", isARepeat: false, keyCode: 57))
                    }
                    let held = !useCaps && upper
                    t += 0.14
                    if held {
                        post(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: .init(rawValue: shift | L),
                                              timestamp: t - 0.08, windowNumber: number, context: nil, characters: "",
                                              charactersIgnoringModifiers: "", isARepeat: false, keyCode: 56))
                    }
                    post(NSEvent.keyEvent(with: .keyDown, location: .zero,
                                          modifierFlags: .init(rawValue: (capsNow ? caps : 0) | (held ? shift | L : 0)), timestamp: t,
                                          windowNumber: number, context: nil, characters: String(c),
                                          charactersIgnoringModifiers: String(c).lowercased(), isARepeat: false, keyCode: 0))
                    if held {
                        post(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: .init(rawValue: 0),
                                              timestamp: t + 0.02, windowNumber: number, context: nil, characters: "",
                                              charactersIgnoringModifiers: "", isARepeat: false, keyCode: 56))
                    }
                }
                try? await Task.sleep(for: .seconds(1.5))
                let half = app.mechanics.summary?.result
                labHalves.append(["drill": app.mechanics.drill.rawValue, "order": half?.comparisonOrder ?? -1,
                                  "technique": half?.techniqueAccuracy ?? -1, "segments": half?.segments?.count ?? -1,
                                  "primary": app.mechanics.primaryActionTitle])
                if app.mechanics.pending != nil {
                    // Return, as the user would press it.
                    post(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: t + 0.5,
                                          windowNumber: number, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                                          isARepeat: false, keyCode: 36))
                    t += 1
                    try? await Task.sleep(for: .seconds(0.8))
                }
            }
            if let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "lab-window.png"))
            }
            let labComparison = app.mechanics.summary?.comparison

            // Numbers & Symbols: Mixed Text with Shift for symbols, numbers reached 120 ms late.
            app.mechanics.select(.mixedText)
            try? await Task.sleep(for: .seconds(0.5))
            let mixed = Array(app.mechanics.text)
            for (i, c) in mixed.enumerated() {
                let shifted = CaseRequirement.of(c) != .plain
                t += 0.14 + (c.isNumber && (i == 0 || !mixed[i - 1].isNumber) ? 0.12 : 0)
                if shifted {
                    post(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: .init(rawValue: shift | L),
                                          timestamp: t - 0.08, windowNumber: number, context: nil, characters: "",
                                          charactersIgnoringModifiers: "", isARepeat: false, keyCode: 56))
                }
                post(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .init(rawValue: shifted ? shift | L : 0),
                                      timestamp: t, windowNumber: number, context: nil, characters: String(c),
                                      charactersIgnoringModifiers: String(c), isARepeat: false, keyCode: 0))
                if shifted {
                    post(NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: .init(rawValue: 0),
                                          timestamp: t + 0.02, windowNumber: number, context: nil, characters: "",
                                          charactersIgnoringModifiers: "", isARepeat: false, keyCode: 56))
                }
            }
            try? await Task.sleep(for: .seconds(1.5))
            let numbers = app.mechanics.summary?.result
            if let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "numbers-window.png"))
            }
            let output: [String: Any] = [
                "lab": labHalves,
                "labComparisonComplete": labComparison != nil,
                "labSamePassage": labComparison.map { $0.shift.text == $0.capsLock.text } ?? false,
                "overhead": Dictionary(uniqueKeysWithValues: app.mechanics.overhead.map { method, estimate in
                    (method.rawValue, ["runs": estimate.runs, "observedMs": estimate.observedMs ?? -1,
                                       "baselineMs": estimate.baselineMs ?? -1, "overheadMs": estimate.overheadMs ?? -1] as [String: Any])
                }),
                "window": [window?.frame.width ?? 0, window?.frame.height ?? 0],
                "numbers": [
                    "text": numbers?.text ?? "", "characters": numbers?.characterAccuracy ?? -1,
                    "technique": numbers?.techniqueAccuracy ?? -1, "checked": numbers?.techniqueChecked ?? -1,
                    "intoDigits": (numbers?.transitions ?? [:]).filter { $0.key.hasPrefix("intoDigit") }.mapValues(\.values),
                    "withinDigits": numbers?.samples(.withinDigits).values ?? [],
                    "lowerAcrossSpace": numbers?.samples(.lowerAcrossSpace).median ?? -1,
                    "shiftLeadMs": numbers?.shiftLead.values ?? [],
                    "layout": app.mechanics.layout?.identifier ?? "none", "judgesSymbols": app.mechanics.judgesSymbols,
                ] as [String: Any],
                "text": String(text),
                "finished": app.mechanics.phase == .finished,
                "guidance": guidance,
                "characterAccuracy": result?.characterAccuracy ?? -1,
                "techniqueAccuracy": result?.techniqueAccuracy ?? -1,
                "techniqueChecked": result?.techniqueChecked ?? -1,
                "techniques": result?.techniques ?? [:],
                "capsLockLeadMs": result?.capsLockLead.values ?? [],
                "shiftLeadMs": result?.shiftLead.values ?? [],
                "transitions": (result?.transitions ?? [:]).mapValues(\.values),
                "savedRounds": app.trainingStore?.mechanicsEvents.count ?? -1,
                "tips": app.mechanics.summary?.tips.map(\.title) ?? [],
            ]
            let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            try? data?.write(to: directory.appending(path: "mechanics.json"))
            NSApp.terminate(nil)
        }
    }

    private static func post(_ event: NSEvent?) {
        if let event { NSApp.postEvent(event, atStart: false) }
    }
}

/// A check of Settings in the real app. Off unless launched with
/// `KEYFLOW_SETTINGS_PROBE=<dir>`; uses in-memory storage and unsaved
/// preferences, so nothing of yours is touched.
///
/// It presses ⌘, through the main menu, opens every tab, types into the
/// Appearance preview with real `NSEvent`s, checks the keys never reach the
/// Practice session behind it, switches the theme, and writes `settings.json`
/// and a PNG per step, then quits.
@MainActor
enum SettingsProbe {
    static let directory: URL? = ProcessInfo.processInfo.environment["KEYFLOW_SETTINGS_PROBE"].map { URL(fileURLWithPath: $0) }
    static var isEnabled: Bool { directory != nil }
    static let showTab = Notification.Name("keyflow.settingsProbe.showTab")
    static var previewTyped = 0
    private static var log: [String: Any] = [:]

    static func run(_ app: AppModel) {
        guard let directory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            NSApp.activate()
            app.section = .practice
            guard let main = NSApp.windows.first(where: { $0.isVisible && $0.identifier != KeyboardMonitor.settingsWindowID }) else {
                finish(directory); return
            }
            main.makeKeyAndOrderFront(nil)

            // ⌘, as the keyboard sends it, through the main menu.
            let item = NSApp.mainMenu?.items.first?.submenu?.items.first {
                $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command
            }
            log["menuItem"] = item?.title ?? "missing"
            let commaKey = key(",", code: 43, flags: .command, window: main)
            log["shortcutHandled"] = NSApp.mainMenu?.performKeyEquivalent(with: commaKey) ?? false
            try? await Task.sleep(for: .seconds(1.2))

            guard let settings = NSApp.windows.first(where: { $0.identifier == KeyboardMonitor.settingsWindowID }) else {
                log["settingsWindow"] = "not found"; finish(directory); return
            }
            log["settingsWindow"] = ["title": settings.title, "visible": settings.isVisible,
                                     "size": [settings.frame.width, settings.frame.height]]
            var tabs: [String: Any] = [:]
            for tab in SettingsTab.allCases {
                NotificationCenter.default.post(name: showTab, object: tab)
                try? await Task.sleep(for: .seconds(0.7))
                tabs[tab.rawValue] = ["title": settings.title, "height": settings.frame.height]
                snapshot(settings, "settings-\(tab.rawValue)", directory)
            }
            log["tabs"] = tabs

            // Type into the preview: "Tx" (the x is a mistake).
            NotificationCenter.default.post(name: showTab, object: SettingsTab.appearance)
            try? await Task.sleep(for: .seconds(0.7))
            settings.makeKeyAndOrderFront(nil)
            let practiceBefore = app.practice.engine.typed.count
            for (character, code) in [("T", UInt16(17)), ("x", UInt16(7))] {
                NSApp.postEvent(key(character, code: code, flags: character == "T" ? .shift : [], window: settings), atStart: false)
            }
            try? await Task.sleep(for: .seconds(0.8))
            log["previewTyped"] = previewTyped
            log["practiceTypedWhileInSettings"] = app.practice.engine.typed.count - practiceBefore
            snapshot(settings, "settings-preview-typed", directory)

            // Settings change the main window live.
            app.preferences.caretStyle = .block
            app.preferences.typingFontSize = 32
            app.preferences.theme = .dark
            try? await Task.sleep(for: .seconds(0.8))
            log["darkAppearance"] = [settings.effectiveAppearance.name.rawValue, main.effectiveAppearance.name.rawValue]
            snapshot(settings, "settings-appearance-dark", directory)

            // The main window still takes its own keys once it is key again.
            main.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(0.4))
            let next = String(app.practice.engine.target[0])
            NSApp.postEvent(key(next, code: 0, flags: [], window: main), atStart: false)
            try? await Task.sleep(for: .seconds(0.6))
            log["practiceTypedInMain"] = app.practice.engine.typed.count
            log["previewTypedAfterMain"] = previewTyped
            snapshot(main, "main-block-caret-32pt-dark", directory)
            app.restartCurrent()
            app.preferences.theme = .system
            finish(directory)
        }
    }

    private static func key(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags, window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                         timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters.lowercased(),
                         isARepeat: false, keyCode: code)!
    }

    private static func snapshot(_ window: NSWindow, _ name: String, _ directory: URL) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name).png"))
    }

    private static func finish(_ directory: URL) {
        let data = try? JSONSerialization.data(withJSONObject: log, options: [.prettyPrinted, .sortedKeys])
        try? data?.write(to: directory.appending(path: "settings.json"))
        NSApp.terminate(nil)
    }
}
