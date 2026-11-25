import AppKit
import SwiftUI
import Testing
@testable import Keyflow
import KeyflowCore

/// Renders the main screens off-screen. Always checks that rendering yields a
/// real image; when `KEYFLOW_SNAPSHOT_DIR` is set, also writes PNGs there for
/// visual review (light and dark).
///
/// AppKit-backed controls (segmented pickers, the text editor) cannot be drawn
/// off-screen and appear as yellow placeholders in these images.
@MainActor
@Suite struct SnapshotRenderTests {
    private func render(_ view: some View, name: String, scheme: ColorScheme, height: CGFloat = 560) throws {
        try render(view, name: name, scheme: scheme, size: CGSize(width: 900, height: height))
    }

    private func render(_ view: some View, name: String, scheme: ColorScheme, size: CGSize) throws {
        let height = size.height
        let content = view
            .frame(width: size.width, height: height)
            .background(scheme == .dark ? Color(white: 0.12) : Color.white)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        #expect(image.size.width == size.width && image.size.height == height)

        guard let directory = ProcessInfo.processInfo.environment["KEYFLOW_SNAPSHOT_DIR"] else { return }
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let suffix = scheme == .dark ? "dark" : "light"
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name)-\(suffix).png"))
    }

    /// Types `count` characters with a varying rhythm and a few mistakes.
    private func play(_ count: Int, into model: TypingSessionModel) {
        // Real uptime, so a stray clock tick during rendering cannot end the session.
        var time = ProcessInfo.processInfo.systemUptime - 12
        for index in 0..<count {
            let expected = model.engine.target[model.engine.position]
            let wrong = index % 23 == 12 || (expected == "h" && index % 3 == 0)
            _ = model.handle(key(wrong ? "x" : String(expected), at: time))
            if wrong, index % 2 == 0 {
                time += 0.15
                _ = model.handle(key("\u{7F}", code: KeyPress.delete, at: time))
                time += 0.12
                _ = model.handle(key(String(expected), at: time))
            }
            time += expected == "t" || expected == "y" ? 0.14 : 0.07 + Double(index % 4) * 0.012
        }
    }

    private func finish(_ model: TypingSessionModel) {
        _ = model.handle(key("a", at: ProcessInfo.processInfo.systemUptime + 400))
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func idlePractice(scheme: ColorScheme) throws {
        let model = TypingSessionModel(role: .practice, durationSeconds: 30, seed: 7)
        try render(PracticeView(model: model), name: "practice-idle", scheme: scheme)
    }

    @Test(arguments: [PracticeMode.sentences, .punctuation, .numbersSymbols])
    func runningPractice(mode: PracticeMode) throws {
        let model = TypingSessionModel(role: .practice, durationSeconds: 30, mode: mode, seed: 7)
        play(95, into: model)
        #expect(model.phase == .running)
        try render(PracticeView(model: model), name: "practice-\(mode.rawValue)", scheme: .light)
        model.restart()
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func practiceResults(scheme: ColorScheme) throws {
        let store = try StatisticsStore.inMemory()
        let model = TypingSessionModel(role: .practice, store: store, durationSeconds: 30, seed: 7)
        play(95, into: model)
        finish(model)
        #expect(model.phase == .finished)
        try render(PracticeView(model: model), name: "practice-results", scheme: scheme)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func idleTest(scheme: ColorScheme) throws {
        let store = try StatisticsStore.inMemory()
        let model = TypingSessionModel(role: .test, store: store, durationSeconds: 30, seed: 7)
        play(120, into: model)
        finish(model)
        model.restart()
        try render(TestView(model: model, store: store), name: "test-idle", scheme: scheme)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func testResults(scheme: ColorScheme) throws {
        let store = try StatisticsStore.inMemory()
        let model = TypingSessionModel(role: .test, store: store, durationSeconds: 30, seed: 7)
        play(60, into: model)
        finish(model)
        model.restart()
        play(140, into: model)
        finish(model)
        let result = try #require(model.result)
        #expect(result.isPersonalBest)
        try render(TestResultsView(model: model, result: result).padding(40),
                   name: "test-results", scheme: scheme, height: 1080)
    }

    @Test func emptyTestResultsShowNotEnoughData() throws {
        let model = TypingSessionModel(role: .test, durationSeconds: 30, seed: 7)
        _ = model.handle(key(String(model.engine.target[0]), at: ProcessInfo.processInfo.systemUptime - 1))
        finish(model)
        let result = try #require(model.result)
        #expect(result.analysis.slowestBigrams().isEmpty)
        #expect(result.analysis.mistypedWords.isEmpty)
        try render(TestResultsView(model: model, result: result).padding(40),
                   name: "test-results-empty", scheme: .light, height: 1080)
    }

    // MARK: Progress dashboard

    /// A scripted history: 36 sessions that speed up over time, with a slow
    /// "th", an often-missed "v", and an early problem with "b" that stops.
    private func history() -> [AnalyzedSession] {
        (0..<36).map { index in
            var supply = TextSupply(mode: .sentences, seed: UInt64(index))
            let limit = [30, 60, 30, 120][index % 4]
            var engine = TypingEngine(target: supply.next(atLeast: 3_000), configuration: .init(timeLimit: Double(limit)))
            let pace = 0.11 - Double(index) * 0.0012 + Double(index % 5) * 0.004
            var time = 0.0
            var previous: Character = " "
            var count = 0
            while time < Double(limit) - 1 {
                let expected = engine.target[engine.position]
                let lower = Character(expected.lowercased())
                time += (previous == "t" && lower == "h") ? pace * 2.6 : pace * (count % 7 == 0 ? 1.5 : 1)
                let wrong = (lower == "v" && count % 2 == 0) || (lower == "b" && index < 5) || count % 61 == 60
                engine.insert(wrong ? "#" : expected, at: time)
                previous = lower
                count += 1
            }
            engine.tick(at: 10_000)
            let session = engine.session(at: 10_000)
            let kind: SessionKind = index % 6 == 5 ? .practice(.sentences) : .test
            return AnalyzedSession(
                summary: SessionSummary(
                    id: UUID(), date: Date(timeIntervalSince1970: 1_760_000_000 + Double(index) * 43_200), kind: kind,
                    timeLimit: limit, metrics: PerformanceCalculator.metrics(for: session),
                    consistency: SessionAnalyzer.consistency(of: session)),
                analysis: SessionAnalyzer.analyze(session))
        }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func progressDashboard(scheme: ColorScheme) throws {
        let report = ProgressAnalyzer.report(for: history())
        #expect(report.weaknesses.hasEnoughData)
        #expect(report.weaknesses.accuracy.contains { $0.id == "accuracy.key.v" })
        #expect(report.weaknesses.speed.contains { $0.id == "speed.combination.th" })
        #expect(report.formerWeaknesses.contains { $0.id == "accuracy.key.b" })
        try render(ProgressReportView(report: report, heatmapMetric: scheme == .light ? .accuracy : .speed).padding(40),
                   name: "progress", scheme: scheme, height: 2250)
    }

    @Test func emptyProgressDashboardSaysNotEnoughData() throws {
        try render(ProgressReportView(report: ProgressAnalyzer.report(for: [])).padding(40),
                   name: "progress-empty", scheme: .light, height: 1150)
    }

    @Test func dashboardLoadsFromTheStore() throws {
        let store = try StatisticsStore.inMemory()
        let model = TypingSessionModel(role: .test, store: store, durationSeconds: 30, seed: 7)
        play(120, into: model)
        finish(model)
        let report = ProgressAnalyzer.report(for: store.analyzedSessions())
        #expect(report.tests.count == 1)
        #expect(report.personalBest?.id == store.summaries.first?.id)
        #expect(!report.weaknesses.hasEnoughData)
    }

    // MARK: Muscle Memory

    @Test(arguments: [ColorScheme.light, .dark])
    func muscleMemoryMidRound(scheme: ColorScheme) throws {
        let model = MuscleMemoryModel(seed: 3)
        var time = 100.0
        for index in 0..<14 {
            let expected = model.nextKey!
            _ = model.handle(key(index == 13 ? "x" : String(expected), at: time))
            time += 0.2
        }
        #expect(model.lastMiss != nil)
        try render(MuscleMemoryView(model: model), name: "muscle-memory", scheme: scheme, height: 700)
    }

    @Test func muscleMemoryRoundComplete() throws {
        let model = MuscleMemoryModel(seed: 4)
        model.select(.homeRow)
        var time = 100.0
        while model.phase != .finished, let expected = model.nextKey {
            _ = model.handle(key(String(expected), at: time))
            time += 0.15
        }
        #expect(model.summary?.result.isQualifying == true)
        try render(MuscleMemoryView(model: model), name: "muscle-memory-complete", scheme: .light, height: 700)
    }

    @Test func muscleMemoryWordsWithFingerGuide() throws {
        let store = try TrainingStore.inMemory()
        for stage in [TrainingStage.singleKeys, .transitions, .patterns] {
            try store.record(TrainingEvent(category: .topRow, stage: stage, kind: .skip))
        }
        let model = MuscleMemoryModel(store: store, seed: 5)
        model.select(.topRow)
        #expect(model.stage == .words)
        try render(MuscleMemoryView(model: model), name: "muscle-memory-words", scheme: .light, height: 700)
    }

    // MARK: UI 2.0

    @Test func focusRecommendations() throws {
        let report = ProgressAnalyzer.report(for: history())
        #expect(!report.weaknesses.all.isEmpty)
        try render(FocusReportView(report: report).padding(40), name: "focus", scheme: .light, height: 900)
        try render(FocusReportView(report: ProgressAnalyzer.report(for: [])).padding(40),
                   name: "focus-empty", scheme: .dark, height: 600)
    }

    @Test func learnHistoryInProgress() throws {
        var events: [TrainingEvent] = []
        for minute in 0..<3 {
            events.append(TrainingEvent(date: Date(timeIntervalSince1970: Double(minute) * 60), category: .homeRow, stage: .singleKeys,
                                        kind: .round(RoundResult(text: "fj", accuracy: [0.9, 0.97, 0.99][minute], keystrokes: 60,
                                                                 correctKeystrokes: 58, backspaces: 0, duration: 20,
                                                                 keys: ["k": ErrorCount(attempts: 20, errors: 3)]))))
        }
        events.append(TrainingEvent(date: Date(timeIntervalSince1970: 400), category: .homeRow, stage: .transitions, kind: .skip))
        try render(TrainingHistoryView(events: events).padding(40), name: "learn-history", scheme: .light, height: 420)
    }

    /// The smallest window: 920 wide minus the sidebar leaves about 720.
    @Test(arguments: ["practice", "test", "learn"])
    func smallestWindow(screen: String) throws {
        let size = CGSize(width: 720, height: 600)
        switch screen {
        case "practice":
            let model = TypingSessionModel(role: .practice, durationSeconds: 30, seed: 7)
            try render(PracticeView(model: model), name: "small-practice", scheme: .light, size: size)
        case "test":
            let model = TypingSessionModel(role: .test, durationSeconds: 60, seed: 7)
            try render(TestView(model: model, store: nil), name: "small-test", scheme: .dark, size: size)
        default:
            let model = MuscleMemoryModel(seed: 3)
            try render(MuscleMemoryView(model: model), name: "small-learn", scheme: .light, size: size)
        }
    }

    // MARK: Finger Focus

    private func fingerFocusModel(_ store: TrainingStore? = nil, seed: UInt64 = 3) -> FingerFocusModel {
        FingerFocusModel(store: store, seed: seed)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func fingerFocusMidRound(scheme: ColorScheme) throws {
        let model = fingerFocusModel()
        model.select(.bothPinkies)
        model.select(.coordination)
        var time = 100.0
        for index in 0..<11 {
            let expected = model.nextKey!
            _ = model.handle(key(index == 10 ? "k" : String(expected), at: time))
            time += 0.2
        }
        #expect(model.lastMiss != nil)
        try render(FingerFocusView(model: model), name: "finger-focus", scheme: scheme, size: CGSize(width: 900, height: 690))
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func fingerFocusRoundCompleteWithRecommendation(scheme: ColorScheme) throws {
        let store = try TrainingStore.inMemory()
        let model = fingerFocusModel(store)
        model.select(.leftPinky)
        model.restSeconds = 20
        for round in 0..<2 {
            var time = 100.0
            var index = 0
            while model.phase != .finished, let expected = model.nextKey {
                _ = model.handle(key(expected == "z" && index % 2 == 0 ? "x" : String(expected), at: time))
                time += 0.15
                index += 1
            }
            if round == 0 { model.performPrimaryAction() }
        }
        #expect(!model.recommendations.isEmpty)
        #expect(model.restRemaining == 20)
        try render(FingerFocusView(model: model), name: "finger-focus-complete", scheme: scheme,
                   size: CGSize(width: 900, height: 690))
    }

    @Test func fingerFocusSmallestWindowAndWords() throws {
        let model = fingerFocusModel()
        model.select(.rightRing)
        model.select(.words)
        try render(FingerFocusView(model: model), name: "small-finger-focus", scheme: .light,
                   size: CGSize(width: 720, height: 550))
    }

    @Test func fingerFocusHistory() throws {
        var events: [FingerFocusEvent] = []
        for minute in 0..<5 {
            events.append(FingerFocusEvent(date: Date(timeIntervalSince1970: Double(minute) * 60), target: .rightPinky,
                                           level: minute < 3 ? .activation : .coordination,
                                           result: RoundResult(text: ";p", accuracy: [0.96, 0.97, 0.99, 0.9, 0.95][minute],
                                                               keystrokes: 60, correctKeystrokes: 57, backspaces: 0, duration: 20,
                                                               keys: [";": ErrorCount(attempts: 20, errors: 1),
                                                                      "p": ErrorCount(attempts: 20, errors: 3)])))
        }
        try render(FingerFocusHistoryView(events: events).padding(40), name: "finger-focus-history", scheme: .light, height: 200)
        try render(FingerFocusHistoryView(events: []).padding(40), name: "finger-focus-history-empty", scheme: .dark, height: 120)
    }

    // MARK: Finger Intelligence

    /// Sessions where the right pinky is slow and error-prone and the left
    /// ring a little slow; everything else steady.
    private func fingerHistory(sessions: Int) -> [TypingSession] {
        let text = "the quick brown fox jumps over the lazy dog; people prop up pale apples. slow wax sways past sixty swans "
        return (0..<sessions).map { index in
            var engine = TypingEngine(target: String(repeating: text, count: 3), configuration: .init(timeLimit: nil, finishesAtEndOfText: true))
            var time = 0.0
            var position = 0
            while engine.phase != .finished, position < engine.target.count {
                let expected = engine.target[position]
                let finger = FingerMap.finger(for: expected)
                let wobble = Double((position * 7 + index) % 5) * 0.012
                time += (finger == .rightPinky ? 0.26 : finger == .leftRing ? 0.19 : 0.15) + wobble
                if finger == .rightPinky, (position + index) % 6 == 0 {
                    engine.insert("o", at: time)
                    time += 0.2
                    if position % 4 != 0 { engine.backspace(at: time); time += 0.15 } else { position += 1; continue }
                }
                engine.insert(expected, at: time)
                position += 1
            }
            return engine.session(at: time + 0.1)
        }
    }

    private func fingerIntelligence(sessions: Int) throws -> (FingerIntelligenceReport, StatisticsStore) {
        let store = try StatisticsStore.inMemory()
        for (index, session) in fingerHistory(sessions: sessions).enumerated() {
            try store.record(session, kind: index.isMultiple(of: 3) ? .test : .practice(.commonWords), timeLimit: 60,
                             date: Date(timeIntervalSince1970: Double(index) * 3_600))
        }
        let report = FingerIntelligence.build(sessions: store.fingerObservations().map { ($0.summary.date, $0.observations) })
        return (report, store)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func fingerPerformance(scheme: ColorScheme) throws {
        let (report, _) = try fingerIntelligence(sessions: 12)
        #expect(report.report[.rightPinky].status == .needsPractice)
        try render(FingerPerformanceView(intelligence: report, train: { _ in }, check: { _ in })
                    .frame(maxWidth: DS.Layout.pageWidth).padding(40),
                   name: "finger-performance", scheme: scheme, height: 1100)
    }

    @Test func fingerPerformanceWithoutData() throws {
        let report = FingerIntelligence.build(sessions: [])
        #expect(Finger.allCases.allSatisfy { report.report[$0].status == .insufficientData })
        try render(FingerPerformanceView(intelligence: report).padding(40), name: "finger-performance-empty",
                   scheme: .light, height: 900)
    }

    /// The narrowest Progress column: 720 wide minus page padding.
    @Test func fingerHeatmapAtTheSmallestWidth() throws {
        let (report, _) = try fingerIntelligence(sessions: 12)
        let heatmap = HandHeatmap(report: report.report, selection: .constant(.leftRing))
        try render(heatmap.frame(width: 640), name: "finger-heatmap-narrow", scheme: .dark, size: CGSize(width: 640, height: 320))
    }

    @Test func fingerInsightsAfterATest() throws {
        let (report, store) = try fingerIntelligence(sessions: 12)
        let progress = ProgressAnalyzer.report(for: store.analyzedSessions())
        let insights = FingerInsightsSection.FingerInsights(
            recommendations: FingerRecommender.recommendations(report: report.report, weaknesses: progress.weaknesses),
            weaknesses: progress.weaknesses, report: report.report)
        #expect(insights.recommendations.first?.finger == .rightPinky)
        try render(FingerInsightsList(insights: insights, trainFinger: { _ in }).padding(40),
                   name: "finger-insights", scheme: .light, height: 300)
    }

    @Test func fingerCheckComplete() throws {
        let store = try TrainingStore.inMemory()
        let model = FingerFocusModel(store: store, seed: 9)
        for round in 0..<2 {
            model.startCheck()
            var time = 100.0
            var index = 0
            while model.phase != .finished, let expected = model.nextKey {
                let slow = "aqz".contains(expected) ? (round == 0 ? 0.35 : 0.2) : 0.15
                _ = model.handle(key(round == 0 && expected == "a" && index % 3 == 0 ? "s" : String(expected), at: time))
                time += slow
                index += 1
            }
            if round == 0 { model.performPrimaryAction() }
        }
        #expect(model.checkSummary?.comparison != nil)
        try render(FingerFocusView(model: model), name: "finger-check", scheme: .light, size: CGSize(width: 900, height: 690))
    }

    // MARK: Typing Mechanics

    @Test(arguments: [ColorScheme.light, .dark])
    func typingMechanicsCapsLockMidRound(scheme: ColorScheme) throws {
        let model = TypingMechanicsModel(seed: 4)
        model.select(.capsMixedCase)
        model.handleModifier(.capsLock(on: true, at: 1))
        var time = 1.2
        for _ in 0..<2 {
            let next = model.nextKey!
            _ = model.handle(KeyPress(keyCode: 0, characters: String(next), hasCommandOrControl: false, hasOption: false,
                                      timestamp: time, modifiers: ModifierSnapshot(capsLock: true)))
            time += 0.15
        }
        try render(TypingMechanicsView(model: model), name: "mechanics-caps", scheme: scheme, size: CGSize(width: 900, height: 690))
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func keyboardModifierStates(scheme: ColorScheme) throws {
        let keyboard = TrainingKeyboardView(exerciseKeys: Set("nasa"), nextKey: "A", miss: nil, keySize: 36,
                                            modifiers: .init(capsLockOn: true, heldShift: .right, recommendedShift: .right))
        try render(keyboard.padding(30), name: "keyboard-modifiers", scheme: scheme, size: CGSize(width: 760, height: 260))
    }

    @Test func typingMechanicsShiftGuidance() throws {
        let model = TypingMechanicsModel(seed: 2)
        model.select(.capitalisedSentences)
        model.handleModifier(.shiftDown(.left, at: 1))
        try render(TypingMechanicsView(model: model), name: "mechanics-shift", scheme: .light, size: CGSize(width: 900, height: 690))
        try render(TypingMechanicsView(model: model), name: "mechanics-small", scheme: .light, size: CGSize(width: 720, height: 550))
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func typingMechanicsResults(scheme: ColorScheme) throws {
        let model = TypingMechanicsModel(seed: 5)
        model.select(.capitalisedSentences)
        var time = 100.0
        var index = 0
        while model.phase != .finished, let next = model.nextKey {
            let upper = next.isUppercase
            // Capitals a little slow, a few with Caps Lock, one wrong key.
            time += upper ? 0.32 : 0.15
            let modifiers = upper ? (index % 3 == 0 ? ModifierSnapshot(capsLock: true) : ModifierSnapshot(rightShift: true))
                                  : ModifierSnapshot()
            if upper, modifiers.shift { model.handleModifier(.shiftDown(.right, at: time - 0.09)) }
            let typed: Character = index == 9 ? "x" : next
            _ = model.handle(KeyPress(keyCode: 0, characters: String(typed), hasCommandOrControl: false, hasOption: false,
                                      timestamp: time, modifiers: modifiers))
            if upper, modifiers.shift { model.handleModifier(.shiftUp(.right, at: time + 0.02)) }
            index += 1
        }
        #expect(model.summary != nil)
        try render(TypingMechanicsView(model: model), name: "mechanics-results", scheme: scheme, size: CGSize(width: 900, height: 1150))
    }

    // MARK: Capitalisation Lab

    private func labRound(_ model: TypingMechanicsModel, capsLock: Bool, slowCaps: Bool) {
        var time = 100.0
        var capsOn = false
        while model.phase != .finished, let next = model.nextKey {
            let upper = CaseRequirement.of(next) == .uppercaseLetter
            if capsLock, upper != capsOn, next.isLetter || next == " " {
                capsOn = upper
                time += slowCaps ? 0.18 : 0.08
                model.handleModifier(.capsLock(on: capsOn, at: time - 0.05))
            }
            var modifiers = ModifierSnapshot(capsLock: capsOn)
            if !capsLock, upper {
                time += 0.06
                model.handleModifier(.shiftDown(.right, at: time - 0.08))
                modifiers = ModifierSnapshot(rightShift: true)
            }
            _ = model.handle(KeyPress(keyCode: 0, characters: String(next), hasCommandOrControl: false, hasOption: false,
                                      timestamp: time, modifiers: modifiers))
            if modifiers.shift { model.handleModifier(.shiftUp(.right, at: time + 0.02)) }
            time += 0.15
        }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func labComparison(scheme: ColorScheme) throws {
        let model = TypingMechanicsModel(seed: 11)
        model.select(.capitalisationLab)
        labRound(model, capsLock: false, slowCaps: false)
        try render(TypingMechanicsView(model: model), name: "lab-half", scheme: scheme, size: CGSize(width: 900, height: 690))
        model.performPrimaryAction()
        labRound(model, capsLock: true, slowCaps: true)
        #expect(model.summary?.comparison != nil)
        try render(TypingMechanicsView(model: model), name: "lab-comparison", scheme: scheme, size: CGSize(width: 900, height: 1400))
    }

    @Test func labFreeChoiceAndSmallWindow() throws {
        let model = TypingMechanicsModel(seed: 15)
        model.select(.labFreeChoice)
        try render(TypingMechanicsView(model: model), name: "lab-small", scheme: .light, size: CGSize(width: 720, height: 550))
        labRound(model, capsLock: true, slowCaps: false)
        try render(TypingMechanicsView(model: model), name: "lab-free", scheme: .light, size: CGSize(width: 900, height: 1150))
    }

    // MARK: Numbers & Symbols

    @Test(arguments: [ColorScheme.light, .dark])
    func numbersAndSymbols(scheme: ColorScheme) throws {
        let model = TypingMechanicsModel(seed: 41, layout: { KeyboardLayoutInfo(identifier: "com.apple.keylayout.US", name: "U.S.") })
        model.select(.mixedText)
        var time = 1.0
        for _ in 0..<5 {
            let next = model.nextKey!
            _ = model.handle(KeyPress(keyCode: 0, characters: String(next), hasCommandOrControl: false, hasOption: false,
                                      timestamp: time, modifiers: next.isUppercase ? ModifierSnapshot(rightShift: true) : ModifierSnapshot()))
            time += 0.15
        }
        try render(TypingMechanicsView(model: model), name: "numbers-mid", scheme: scheme, size: CGSize(width: 900, height: 740))
    }

    @Test func numbersResultsAndForeignLayout() throws {
        let model = TypingMechanicsModel(seed: 42, layout: { KeyboardLayoutInfo(identifier: "com.apple.keylayout.US", name: "U.S.") })
        model.select(.mixedText)
        var time = 1.0
        var index = 0
        while model.phase != .finished, let next = model.nextKey {
            let shifted = CaseRequirement.of(next) != .plain
            time += next.isNumber ? 0.28 : 0.15
            if shifted { model.handleModifier(.shiftDown(.left, at: time - 0.09)) }
            let typed: Character = index % 17 == 5 && next.isNumber ? "0" : next
            _ = model.handle(KeyPress(keyCode: 0, characters: String(typed), hasCommandOrControl: false, hasOption: false,
                                      timestamp: time, modifiers: shifted ? ModifierSnapshot(leftShift: true) : ModifierSnapshot()))
            if shifted { model.handleModifier(.shiftUp(.left, at: time + 0.02)) }
            index += 1
        }
        try render(TypingMechanicsView(model: model), name: "numbers-results", scheme: .light, size: CGSize(width: 900, height: 1100))

        let foreign = TypingMechanicsModel(seed: 43, layout: { KeyboardLayoutInfo(identifier: "com.apple.keylayout.German", name: "German") })
        foreign.select(.shiftedSymbols)
        try render(TypingMechanicsView(model: foreign), name: "numbers-german", scheme: .light, size: CGSize(width: 720, height: 600))
    }

    // MARK: Recommendations

    @Test(arguments: [ColorScheme.light, .dark])
    func mechanicsRecommendations(scheme: ColorScheme) throws {
        let store = try TrainingStore.inMemory()
        let model = TypingMechanicsModel(store: store, seed: 61)
        model.select(.labShiftOnly)
        for round in 0..<2 {
            var time = 100.0
            while model.phase != .finished, let next = model.nextKey {
                let upper = next.isUppercase
                let position = model.engine.position
                let runStart = upper && (position == 0 || !model.engine.target[position - 1].isUppercase)
                let runEnd = position > 0 && model.engine.target[position - 1].isUppercase && !upper
                time += runStart ? 0.35 : (runEnd ? 0.3 : 0.15)
                if upper { model.handleModifier(.shiftDown(.left, at: time - 0.08)) }
                _ = model.handle(KeyPress(keyCode: 0, characters: String(next), hasCommandOrControl: false, hasOption: false,
                                          timestamp: time, modifiers: upper ? ModifierSnapshot(leftShift: true) : ModifierSnapshot()))
                if upper { model.handleModifier(.shiftUp(.left, at: time + 0.01)) }
            }
            if round == 0 { model.restart() }
        }
        #expect(model.recommendations.count >= 2)
        try render(TypingMechanicsView(model: model), name: "recommend-results", scheme: scheme, size: CGSize(width: 900, height: 1400))
        model.select(.numbersSymbols)
        try render(TypingMechanicsView(model: model), name: "recommend-idle", scheme: scheme, size: CGSize(width: 900, height: 740))
    }

    // MARK: Typing Mechanics in Progress

    @Test(arguments: [ColorScheme.light, .dark])
    func mechanicsProgress(scheme: ColorScheme) throws {
        let store = try TrainingStore.inMemory()
        let model = TypingMechanicsModel(store: store, seed: 71)
        model.select(.capitalisationLab)
        for _ in 0..<8 {
            let caps = model.drill == .labCapsLockOnly
            var time = 100.0
            var capsOn = false
            while model.phase != .finished, let next = model.nextKey {
                let upper = next.isUppercase
                let position = model.engine.position
                let runStart = upper && (position == 0 || !model.engine.target[position - 1].isUppercase)
                if caps, upper != capsOn, next.isLetter || next == " " {
                    capsOn = upper
                    time += 0.08 + Double(position % 3) * 0.02
                    model.handleModifier(.capsLock(on: capsOn, at: time - 0.03))
                }
                time += 0.15 + (!caps && upper ? 0.06 + Double(position % 3) * 0.01 : 0) + (runStart ? 0.02 : 0)
                let modifiers = caps ? ModifierSnapshot(capsLock: capsOn) : (upper ? ModifierSnapshot(rightShift: true) : ModifierSnapshot())
                if !caps, upper { model.handleModifier(.shiftDown(.right, at: time - 0.08)) }
                _ = model.handle(KeyPress(keyCode: 0, characters: String(next), hasCommandOrControl: false, hasOption: false,
                                          timestamp: time, modifiers: modifiers))
                if !caps, upper { model.handleModifier(.shiftUp(.right, at: time + 0.01)) }
            }
            model.performPrimaryAction()
        }
        let history = MechanicsHistory(events: store.mechanicsEvents)
        #expect(history.comparisonsDone == 4)
        try render(MechanicsProgressView(history: history, open: { _ in }).frame(maxWidth: DS.Layout.pageWidth).padding(40),
                   name: "mechanics-progress", scheme: scheme, size: CGSize(width: 1000, height: 1400))
        try render(MechanicsProgressView(history: MechanicsHistory(events: [])).padding(40),
                   name: "mechanics-progress-empty", scheme: scheme, size: CGSize(width: 1000, height: 200))
    }
}
