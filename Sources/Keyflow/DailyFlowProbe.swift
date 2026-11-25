import AppKit
import KeyflowCore

/// `KEYFLOW_DAILYFLOW_PROBE=<dir>`: drives Learn ▸ Daily Flow in the real
/// window with posted key events, then writes `dailyflow.json` and snapshots.
/// Uses in-memory storage and no saved settings. Off unless the variable is set.
@MainActor
enum DailyFlowProbe {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["KEYFLOW_DAILYFLOW_PROBE"] != nil }
    private static var checks: [[String: Any]] = []

    private static func check(_ name: String, _ ok: Bool, _ detail: Any = "") {
        checks.append(["name": name, "ok": ok, "detail": "\(detail)"])
    }

    static func run(_ app: AppModel) {
        guard let path = ProcessInfo.processInfo.environment["KEYFLOW_DAILYFLOW_PROBE"] else { return }
        let directory = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            let model = app.dailyFlow
            app.section = .muscleMemory
            if ProcessInfo.processInfo.environment["KEYFLOW_PROBE_LIGHT"] != nil {
                NSApp.appearance = NSAppearance(named: .aqua)
            }
            NSApp.activate()
            let window = NSApp.windows.first { $0.isVisible && $0.canBecomeKey }
            window?.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .seconds(1))
            let number = window?.windowNumber ?? 0
            var t = ProcessInfo.processInfo.systemUptime

            @MainActor func key(_ c: String, code: UInt16 = 0, repeat isRepeat: Bool = false, step: Double = 0.4) {
                t += step
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: t,
                                                windowNumber: number, context: nil, characters: c,
                                                charactersIgnoringModifiers: c, isARepeat: isRepeat, keyCode: code) {
                    NSApp.postEvent(event, atStart: false)
                }
            }
            @MainActor func settle(_ seconds: Double = 0.5) async { try? await Task.sleep(for: .seconds(seconds)) }
            @MainActor func snapshot(_ name: String) {
                guard let view = window?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name).png"))
            }
            // What is really on screen, glass included.
            @MainActor func live(_ name: String) {
                guard let image = KeyRepetitionProbe.liveImage(of: number) else { return }
                let rep = NSBitmapImageRep(cgImage: image)
                try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name)-live.png"))
            }
            @MainActor func typeRest(step: Double = 0.4) async {
                let rest = model.engine.target.dropFirst(model.engine.position)
                for c in rest { key(String(c), code: c == " " ? 49 : 1, step: step) }
                await settle(0.4)
            }

            // Learn ▸ Today, the front door, before any practice.
            check("Learn opens on Today", app.learnMode == .today)
            check("Today has no pick-up rows yet", app.pickUps.isEmpty)
            check("no practice days yet", app.practiceDays.days.isEmpty)
            live("0-today-empty")
            app.learnMode = .dailyFlow
            await settle()

            check("opens on the start screen", model.stage == .start)
            check("default length is 10 minutes", model.plan.minutes == 10, model.plan.minutes)
            check("no new main destination", AppSection.allCases.count == 5)
            check("Daily Flow follows Today in Learn", Array(LearnMode.allCases.prefix(2)) == [.today, .dailyFlow])
            snapshot("1-start")
            key("p", code: 35)
            await settle()
            check("stray letter stays on Daily Flow", app.section == .muscleMemory && app.learnMode == .dailyFlow, app.section.rawValue)

            key("\r", code: 36)
            await settle()
            check("Return starts", model.stage == .flowing)
            check("warm-up comes first", model.segment == .warmUp)
            check("warm-up uses home-row letters", model.engine.target.allSatisfy { " asdfghjkl".contains($0) }, String(model.engine.target))
            check("no hint at first", !model.isHintShowing)
            snapshot("2-flowing")

            // A real pause reveals the hint; the next key hides it.
            let firstKey = model.nextKey
            try? await Task.sleep(for: .seconds(model.hintDelay + 0.5))
            check("pausing shows the next key", model.isHintShowing && model.hintsThisPassage == 1, model.hintsThisPassage)
            snapshot("3-hint")
            t = ProcessInfo.processInfo.systemUptime
            key(String(firstKey ?? "a"), code: 1, step: 0.01)
            await settle(0.2)
            check("pressing a key hides the hint", !model.isHintShowing)
            check("key was typed", model.engine.position == 1, model.engine.position)

            // Held key.
            let before = model.engine.position
            for _ in 0..<30 { key(String(model.nextKey ?? "a"), code: 1, repeat: true, step: 0.03) }
            await settle(0.3)
            check("held key types nothing", model.engine.position == before, model.engine.position)

            // Esc pause.
            key("\u{1b}", code: 53)
            await settle(0.3)
            check("Esc pauses", model.isPaused)
            let paused = model.engine.position
            key("a", code: 0)
            await settle(0.2)
            check("typing while paused is ignored", model.engine.position == paused)
            try? await Task.sleep(for: .seconds(DailyFlowPace.maximumDelay + 0.3))
            check("no hint while paused", !model.isHintShowing)
            key("\u{1b}", code: 53)
            await settle(0.3)

            // Leaving keeps the session.
            let kept = model.engine.position
            app.section = .progress
            await settle()
            check("leaving Learn pauses and keeps the session", model.isPaused && model.stage == .flowing && model.engine.position == kept)
            app.section = .muscleMemory
            await settle()
            key("\u{1b}", code: 53)
            await settle(0.3)
            check("session continues on return", !model.isPaused && model.engine.position == kept)

            // Finish a passage: saved at once, the next begins by itself.
            t = max(t, ProcessInfo.processInfo.systemUptime)
            let firstText = model.engine.target
            await typeRest()
            check("finished passage saved", app.trainingStore?.dailyFlowEvents.count == 1, app.trainingStore?.dailyFlowEvents.count ?? -1)
            check("next passage starts by itself", model.stage == .flowing && model.engine.target != firstText && model.engine.position == 0)
            check("saved hint count", app.trainingStore?.dailyFlowEvents.first?.round.hints == 1,
                  app.trainingStore?.dailyFlowEvents.first?.round.hints ?? -1)

            // End early keeps it.
            model.endEarly()
            await settle()
            if case .complete(let session) = model.stage {
                check("End Session shows the summary", session.totals.passages == 1)
                check("without-hints is a sensible share", (session.totals.withoutHints ?? 0) > 0.8, session.totals.withoutHints ?? -1)
            } else {
                check("End Session shows the summary", false)
            }
            snapshot("4-complete")
            key("p", code: 35)
            await settle(0.3)
            check("extra press stays on the summary", app.section == .muscleMemory && app.learnMode == .dailyFlow)
            key("\r", code: 36)
            await settle()
            check("Return goes back to start", model.stage == .start)
            snapshot("5-start-after")

            // Today after the session: done, and today's dot filled.
            app.learnMode = .today
            await settle()
            check("today counts as practised", app.practiceDays.practised(on: .now))
            check("Today's card is done", model.hasPractisedToday)
            live("7-today-done")
            key("\r", code: 36)
            await settle()
            check("Return on Today opens Daily Flow", app.learnMode == .dailyFlow)
            check("without starting again", model.stage == .start)
            app.learnMode = .today
            await settle()

            app.section = .progress
            await settle(1.2)
            check("other histories untouched",
                  app.trainingStore.map { $0.events.isEmpty && $0.fingerFocusEvents.isEmpty && $0.keyRepetitionEvents.isEmpty } ?? false)
            check("no Practice or Test session created", app.store?.summaries.isEmpty ?? true)
            if let scroll = window?.contentView.flatMap(findScroll), let document = scroll.documentView {
                let y = document.isFlipped ? document.bounds.height * 0.62 : document.bounds.height * 0.38
                document.scroll(NSPoint(x: 0, y: y))
                await settle(0.5)
                snapshot("6-progress")
            }

            // Pick-up rows once other modes have saved practice (in memory only).
            if let store = app.trainingStore {
                let round = RoundResult(text: "fj", accuracy: 1, keystrokes: 10, correctKeystrokes: 10, backspaces: 0, duration: 5)
                try? store.record(TrainingEvent(category: .homeRow, stage: .singleKeys, kind: .round(round)))
                try? store.record(FingerFocusEvent(target: .rightPinky, level: .activation, result: round))
                try? store.record(KeyRepetitionEvent(result: KeyRepetitionResult(letter: "j", goal: 50, correct: 50, incorrect: 0,
                                                                                 mode: .continuous, duration: 30)))
            }
            app.section = .muscleMemory
            app.learnMode = .today
            await settle(0.8)
            check("three pick-up rows", app.pickUps.map(\.id) == ["lessons", "fingerFocus", "keyRepetition"], app.pickUps.map(\.id))
            live("8-today-rows")
            app.pickUp(.keyRepetition("j"))
            await settle()
            check("a row opens its mode", app.learnMode == .keyRepetition && app.keyRepetition.letter == "j")
            app.learnMode = .today
            await settle()

            let output: [String: Any] = [
                "checks": checks,
                "passed": checks.filter { $0["ok"] as? Bool == true }.count,
                "failed": checks.filter { $0["ok"] as? Bool != true }.map { $0["name"] ?? "" },
            ]
            let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
            try? data?.write(to: directory.appending(path: "dailyflow.json"))
            NSApp.terminate(nil)
        }
    }

    private static func findScroll(_ view: NSView) -> NSScrollView? {
        var best: NSScrollView?
        for child in view.subviews {
            if let scroll = child as? NSScrollView, !(scroll.documentView is NSTableView),
               (scroll.documentView?.bounds.height ?? 0) > (best?.documentView?.bounds.height ?? 0) { best = scroll }
            if let found = findScroll(child), (found.documentView?.bounds.height ?? 0) > (best?.documentView?.bounds.height ?? 0) { best = found }
        }
        return best
    }
}
