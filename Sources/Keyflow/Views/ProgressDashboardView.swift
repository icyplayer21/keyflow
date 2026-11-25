import Charts
import KeyflowCore
import SwiftUI

/// The Progress section: loads history from the stores and shows the report.
struct ProgressDashboardView: View {
    let store: StatisticsStore?
    var trainingStore: TrainingStore?
    var trainFinger: ((FingerFocusTarget) -> Void)?
    var checkFinger: ((FingerFocusTarget) -> Void)?
    var openMechanics: ((MechanicsRecommendation) -> Void)?
    @State private var report: ProgressReport?
    @State private var fingers: FingerIntelligenceReport?

    var body: some View {
        ScrollView {
            Group {
                if let report {
                    ProgressReportView(report: report, training: trainingStore?.events ?? [],
                                       fingerFocus: trainingStore?.fingerFocusEvents ?? [],
                                       fingers: fingers, trainFinger: trainFinger, checkFinger: checkFinger,
                                       mechanics: trainingStore?.mechanicsEvents ?? [], openMechanics: openMechanics,
                                       keyRepetition: trainingStore?.keyRepetitionEvents ?? [],
                                       dailyFlow: trainingStore?.dailyFlowEvents ?? [])
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 120)
                }
            }
            .frame(maxWidth: DS.Layout.pageWidth)
            .padding(.horizontal, DS.Layout.pagePadding)
            .padding(.vertical, DS.Space.xl)
            .frame(maxWidth: .infinity)
        }
        .softScrollEdge()
        .background(.background)
        // Recomputed whenever a session is saved.
        .task(id: store?.summaries.count) {
            report = ProgressAnalyzer.report(for: store?.analyzedSessions() ?? [])
            fingers = FingerIntelligence.build(
                sessions: (store?.fingerObservations() ?? []).map { ($0.summary.date, $0.observations) },
                training: trainingStore?.fingerFocusEvents ?? [],
                assessments: trainingStore?.assessmentEvents ?? []
            )
        }
    }
}

struct ProgressReportView: View {
    let report: ProgressReport
    var training: [TrainingEvent] = []
    var fingerFocus: [FingerFocusEvent] = []
    var fingers: FingerIntelligenceReport?
    var trainFinger: ((FingerFocusTarget) -> Void)?
    var checkFinger: ((FingerFocusTarget) -> Void)?
    var mechanics: [MechanicsEvent] = []
    var openMechanics: ((MechanicsRecommendation) -> Void)?
    var keyRepetition: [KeyRepetitionEvent] = []
    var dailyFlow: [DailyFlowEvent] = []
    var heatmapMetric: KeyboardHeatmapView.Metric = .accuracy

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            SummaryStrip(report: report)

            Divider()

            section("Speed", caption: "Net WPM for each completed test. The dashed line is your personal best.") {
                HistoryChart(tests: report.tests, unit: "Net WPM", best: report.personalBest?.metrics.netWPM) {
                    $0.metrics.netWPM
                }
            }

            Divider()

            HStack(alignment: .top, spacing: DS.Space.xl) {
                section("Accuracy", caption: "Correct keystrokes, including corrected mistakes.") {
                    HistoryChart(tests: report.tests, unit: "Accuracy %", height: 140) { $0.metrics.accuracy * 100 }
                }
                section("Consistency", caption: "How even your pace was within each test.") {
                    HistoryChart(tests: report.tests, unit: "Consistency %", height: 140) { $0.consistency.map { $0 * 100 } }
                }
            }

            Divider()

            section("Weaknesses", caption: weaknessCaption) {
                WeaknessColumns(report: report)
            }

            Divider()

            section("Finger Performance",
                    caption: "Estimated from the keys each finger is assigned in standard touch typing, over your last \(min(report.profile.sessions, FingerIntelligence.window)) sessions. Choose a finger for details.") {
                if let fingers {
                    FingerPerformanceView(intelligence: fingers, train: trainFinger, check: checkFinger)
                } else {
                    ProgressView().controlSize(.small)
                }
            }

            Divider()

            section("Weakness improvement",
                    caption: "Confirmed weaknesses after each session, judged on the \(ProgressAnalyzer.window) sessions before it.") {
                WeaknessHistoryView(report: report)
            }

            Divider()

            section("Keyboard heatmap",
                    caption: "From your last \(min(report.profile.sessions, ProgressAnalyzer.window)) sessions. Hover a key for its numbers.") {
                KeyboardHeatmapView(profile: report.profile, metric: heatmapMetric)
            }

            Divider()

            section("Daily Flow",
                    caption: "This week beside last week. Without hints is the share of keystrokes made before Keyflow showed the next key; it can't see whether you looked down. Kept out of the typing statistics above.") {
                DailyFlowProgressView(history: DailyFlowHistory(events: dailyFlow))
            }

            Divider()

            section("Learn", caption: "Lessons from Learn. These drills are kept out of the statistics above.") {
                TrainingHistoryView(events: training)
            }

            Divider()

            section("Finger Focus",
                    caption: "Ring finger and pinky drills from Learn. Key accuracy is what Keyflow measured; it cannot see which finger you used.") {
                FingerFocusHistoryView(events: fingerFocus)
            }

            Divider()

            section("Typing Mechanics",
                    caption: "Shift, Caps Lock, case changes and numbers from Learn ▸ Typing Mechanics. Kept out of the typing statistics above.") {
                MechanicsProgressView(history: MechanicsHistory(events: mechanics), open: openMechanics)
            }

            Divider()

            section("Key Repetition",
                    caption: "Single-key sessions from Learn ▸ Key Repetition. Accuracy is correct presses ÷ counted presses. Kept out of WPM and the typing statistics above.") {
                KeyRepetitionHistoryView(history: KeyRepetitionHistory(events: keyRepetition))
            }

            Divider()

            section("Targeted training", caption: "How the skills you train in Focus change between retests.") {
                EmptyNote("Not enough data yet. Focus training sessions are not built yet, so there is nothing to compare.")
            }
        }
        .monospacedDigit()
    }

    private var weaknessCaption: String {
        let sessions = min(report.profile.sessions, ProgressAnalyzer.window)
        return "Measured against your own averages over your last \(sessions) \(sessions == 1 ? "session" : "sessions"). Accuracy and speed are judged separately."
    }

    private func section<Content: View>(_ title: String, caption: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            SectionHeader(title: title, caption: caption)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Summary

private struct SummaryStrip: View {
    let report: ProgressReport

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: DS.Space.l, alignment: .topLeading)],
                  alignment: .leading, spacing: DS.Space.l) {
            item("\(report.tests.count)", "Tests",
                 "\(report.practiceSessions) practice \(report.practiceSessions == 1 ? "session" : "sessions")")
            item(report.personalBest.map { "\(Int($0.metrics.netWPM.rounded()))" } ?? "–", "Personal best",
                 report.personalBest.map { "\($0.timeLimit)s · \($0.date.formatted(date: .abbreviated, time: .omitted))" } ?? "No tests yet",
                 tint: report.personalBest == nil ? .primary : .accentColor)
            item(report.recentWPM.map { "\(Int($0.rounded()))" } ?? "–", "Avg. WPM", recentDetail)
            item(report.recentAccuracy?.percentText ?? "–", "Avg. accuracy", recentDetail)
            item(report.recentConsistency?.percentText ?? "–", "Consistency", recentDetail)
            item(duration(report.totalTime), "Time typing", "All sessions")
        }
    }

    private var recentDetail: String {
        let count = min(report.tests.count, ProgressAnalyzer.recentTests)
        return count == 0 ? "No tests yet" : "Last \(count) \(count == 1 ? "test" : "tests")"
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "\(Int(seconds))s" }
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h \(minutes % 60)m"
    }

    private func item(_ value: String, _ label: String, _ detail: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Metric(value: value, label: label, size: 26, tint: tint)
            Text(detail)
                .font(DS.Typography.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One value per test, in order, with a line per test length.
private struct HistoryChart: View {
    let tests: [SessionSummary]
    let unit: String
    var best: Double?
    var height: CGFloat = 190
    let value: (SessionSummary) -> Double?

    private struct Point: Identifiable {
        let id: Int
        let length: String
        let value: Double
    }

    private var points: [Point] {
        tests.enumerated().compactMap { index, test in
            value(test).map { Point(id: index + 1, length: "\(test.timeLimit)s", value: $0) }
        }
    }

    var body: some View {
        let points = points
        if points.isEmpty {
            EmptyNote()
        } else {
            let low = points.map(\.value).min() ?? 0
            let high = max(points.map(\.value).max() ?? 1, best ?? 0)
            let padding = max(2, (high - low) * 0.15)

            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Test", point.id), y: .value(unit, point.value))
                        .foregroundStyle(by: .value("Length", point.length))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Test", point.id), y: .value(unit, point.value))
                        .foregroundStyle(by: .value("Length", point.length))
                        .symbolSize(18)
                }
                if let best {
                    RuleMark(y: .value("Personal best", best))
                        .foregroundStyle(Color.primary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Best \(Int(best.rounded()))").font(DS.Typography.caption).foregroundStyle(.secondary)
                        }
                }
            }
            .chartForegroundStyleScale(["30s": Color.accentColor, "60s": Color.teal, "120s": Color.secondary])
            .chartXScale(domain: 1...max(2, tests.count))
            .chartYScale(domain: max(0, low - padding)...(high + padding))
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { AxisGridLine(); AxisValueLabel() } }
            .chartXAxisLabel("Test")
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: height)
            .accessibilityLabel("\(unit) for each completed test")
        }
    }
}

// MARK: - Weaknesses

private struct WeaknessColumns: View {
    let report: ProgressReport

    var body: some View {
        if !report.weaknesses.hasEnoughData {
            EmptyNote("Not enough data yet. Weaknesses are reported after \(report.weaknesses.keystrokesNeeded) keystrokes; you have typed \(report.weaknesses.keystrokes).")
        } else {
            HStack(alignment: .top, spacing: DS.Space.xl) {
                column("Accuracy", weaknesses: report.weaknesses.accuracy,
                       empty: "Nothing stands out from your usual error rate.")
                column("Speed", weaknesses: report.weaknesses.speed,
                       empty: "Nothing is reliably slower than your usual pace.")
            }
        }
    }

    private func column(_ title: String, weaknesses: [Weakness], empty: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Eyebrow(title)
            if weaknesses.isEmpty {
                EmptyNote(empty)
            } else {
                ForEach(weaknesses.prefix(8)) { weakness in
                    WeaknessRow(weakness: weakness, since: report.firstFlagged[weakness.id])
                }
                if weaknesses.count > 8 {
                    Text("and \(weaknesses.count - 8) more").font(DS.Typography.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct WeaknessRow: View {
    let weakness: Weakness
    var since: Date?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
            Text(Self.label(for: weakness))
                .font(DS.Typography.code)
                .frame(minWidth: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(headline).font(DS.Typography.body).lineLimit(1).minimumScaleFactor(0.85)
                Text(evidence).font(DS.Typography.caption).foregroundStyle(.secondary).lineLimit(1)
                if let since {
                    Text("First flagged \(since.formatted(date: .abbreviated, time: .omitted))")
                        .font(DS.Typography.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.xs)
            Text(String(format: "%.1f×", weakness.severity))
                .font(DS.Typography.metric(12))
                .foregroundStyle(weakness.dimension == .accuracy ? DS.Palette.error : DS.Palette.caution)
                .help("Compared with your own average")
        }
        .accessibilityElement(children: .combine)
    }

    /// Spaces are invisible in a pair, so they are drawn as "␣".
    static func label(for weakness: Weakness) -> String {
        switch weakness.category {
        case .key: weakness.item == " " ? "space" : weakness.item
        case .word: weakness.item
        case .combination, .transition: weakness.item.replacingOccurrences(of: " ", with: "␣")
        }
    }

    static func kind(of weakness: Weakness) -> String {
        switch weakness.category {
        case .key: "Key"
        case .combination: "Letter combination"
        case .word: "Word"
        case .transition: "Transition"
        }
    }

    private var headline: String {
        switch weakness.dimension {
        case .accuracy: "\(percent(weakness.value)) errors · usually \(percent(weakness.baseline))"
        case .speed: "\(weakness.value.millisecondsText) · usually \(weakness.baseline.millisecondsText)"
        }
    }

    private var evidence: String {
        weakness.dimension == .accuracy
            ? "\(Self.kind(of: weakness)) · \(weakness.errors) wrong in \(weakness.samples) attempts"
            : "\(Self.kind(of: weakness)) · \(weakness.samples) timed samples"
    }

    private func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }
}

private struct WeaknessHistoryView: View {
    let report: ProgressReport

    private struct Point: Identifiable {
        let index: Int
        let series: String
        let count: Int
        var id: String { "\(series)\(index)" }
    }

    var body: some View {
        if report.weaknessHistory.isEmpty {
            EmptyNote()
        } else {
            let points = report.weaknessHistory.flatMap {
                [Point(index: $0.index, series: "Accuracy", count: $0.accuracy),
                 Point(index: $0.index, series: "Speed", count: $0.speed)]
            }
            VStack(alignment: .leading, spacing: DS.Space.l) {
                Chart(points) { point in
                    LineMark(x: .value("Session", point.index), y: .value("Confirmed weaknesses", point.count))
                        .foregroundStyle(by: .value("Kind", point.series))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.stepEnd)
                }
                .chartForegroundStyleScale(["Accuracy": DS.Palette.error, "Speed": DS.Palette.caution])
                .chartXScale(domain: 1...max(2, report.weaknessHistory.last?.index ?? 2))
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisGridLine(); AxisValueLabel() } }
                .chartXAxisLabel("Session")
                .chartLegend(position: .top, alignment: .leading)
                .frame(height: 140)
                .accessibilityLabel("Number of confirmed weaknesses after each session")

                if !report.formerWeaknesses.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Eyebrow("No longer flagged")
                        Text("Confirmed earlier, not now. This can mean improvement, or too little recent typing of that item to judge.")
                            .font(DS.Typography.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(report.formerWeaknesses.prefix(8)) { former in
                            HStack(spacing: DS.Space.s) {
                                Text(WeaknessRow.label(for: former.weakness)).font(DS.Typography.code)
                                    .frame(minWidth: 52, alignment: .leading)
                                Text(former.weakness.dimension == .accuracy ? "accuracy" : "speed")
                                    .font(DS.Typography.body).foregroundStyle(.secondary)
                                Spacer()
                                Text("last flagged \(former.lastFlagged.formatted(date: .abbreviated, time: .omitted))")
                                    .font(DS.Typography.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Learn history

/// Lesson progress per category, accuracy over recent rounds, and keys to watch.
struct TrainingHistoryView: View {
    let events: [TrainingEvent]

    var body: some View {
        let tracker = MasteryTracker(events: events)
        let rounds = events.compactMap(\.round)

        if events.isEmpty {
            EmptyNote("No lessons yet. Start with Home Row in Learn.")
        } else {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                Grid(alignment: .leading, horizontalSpacing: DS.Space.l, verticalSpacing: DS.Space.xs) {
                    ForEach(TrainingCategory.allCases) { category in
                        GridRow {
                            Text(category.title).font(DS.Typography.body)
                            HStack(spacing: 6) {
                                ForEach(TrainingStage.allCases) { stage in
                                    let state = LessonState(status: tracker.status(category, stage),
                                                            progress: tracker.progress(category, stage))
                                    Image(systemName: state.symbol)
                                        .font(.system(size: 11))
                                        .foregroundStyle(state.tint)
                                        .help("Stage \(stage.rawValue), \(stage.title): \(state.label)")
                                }
                            }
                            Text("\(tracker.masteredStages(category)) of \(TrainingStage.allCases.count) mastered")
                                .font(DS.Typography.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                if rounds.count >= 2 {
                    AccuracyTrend(rounds: Array(rounds.suffix(60)))
                }

                let watch = tracker.mistypedKeys()
                if !watch.isEmpty {
                    HStack(spacing: DS.Space.s) {
                        Eyebrow("Keys to watch")
                        ForEach(watch, id: \.key) { item in
                            HStack(spacing: 3) {
                                Text(String(item.key).uppercased()).font(DS.Typography.code)
                                Text("\(item.count.errors)/\(item.count.attempts)")
                                    .font(DS.Typography.metric(11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Per finger: level progress, rounds, and recent accuracy on its keys.
struct FingerFocusHistoryView: View {
    let events: [FingerFocusEvent]

    var body: some View {
        let tracker = FingerFocusTracker(events: events)
        let practised = FingerFocusTarget.allCases.filter { tracker.rounds($0) > 0 }

        if practised.isEmpty {
            EmptyNote("No Finger Focus rounds yet. Choose a finger under Learn → Finger Focus.")
        } else {
            Grid(alignment: .leading, horizontalSpacing: DS.Space.l, verticalSpacing: DS.Space.xs) {
                ForEach(practised) { target in
                    GridRow {
                        Text(target.title).font(DS.Typography.body)
                        HStack(spacing: 6) {
                            ForEach(FingerFocusLevel.allCases) { level in
                                let progress = tracker.progress(target, level)
                                let state: LessonState = progress.isSteady ? .mastered
                                    : (progress.rounds > 0 ? .inProgress(qualifying: progress.qualifyingRounds) : .notStarted)
                                Image(systemName: state.symbol)
                                    .font(.system(size: 11))
                                    .foregroundStyle(state.tint)
                                    .help("Level \(level.rawValue), \(level.title): \(progress.isSteady ? "Steady" : state.label)")
                            }
                        }
                        Text("\(tracker.rounds(target)) \(tracker.rounds(target) == 1 ? "round" : "rounds")")
                            .font(DS.Typography.caption).foregroundStyle(.secondary)
                        HStack(spacing: DS.Space.s) {
                            ForEach(tracker.keyStats(target), id: \.key) { stat in
                                HStack(spacing: 3) {
                                    Text(String(stat.key).uppercased()).font(DS.Typography.code)
                                    Text(stat.accuracy?.percentText ?? "–")
                                        .font(DS.Typography.metric(11)).foregroundStyle(.secondary)
                                }
                                .help("\(stat.count.errors) errors in \(stat.count.attempts) presses over the last \(FingerFocusTracker.recentRounds) rounds")
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Per key: sessions, correct repetitions, overall accuracy and when it was
/// last practised. Counts only; no score is derived from them.
struct KeyRepetitionHistoryView: View {
    let history: KeyRepetitionHistory

    var body: some View {
        if history.keys.isEmpty {
            EmptyNote("No Key Repetition sessions yet. Choose a key under Learn → Key Repetition.")
        } else {
            Grid(alignment: .leading, horizontalSpacing: DS.Space.l, verticalSpacing: DS.Space.xs) {
                GridRow {
                    ForEach(["Key", "Sessions", "Repetitions", "Accuracy", "Last practised"], id: \.self) {
                        Text($0).font(DS.Typography.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(history.keys) { stats in
                    GridRow {
                        Text(String(stats.letter).uppercased()).font(DS.Typography.code)
                        Text("\(stats.sessions)")
                        Text("\(stats.repetitions)")
                            .help("\(stats.mistakes) incorrect \(stats.mistakes == 1 ? "press" : "presses")")
                        Text(stats.accuracy.percentText)
                        Text(stats.lastPractised.formatted(date: .abbreviated, time: .omitted))
                            .foregroundStyle(.secondary)
                    }
                    .font(DS.Typography.body)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct AccuracyTrend: View {
    let rounds: [RoundResult]

    var body: some View {
        let lowest = rounds.map { $0.accuracy * 100 }.min() ?? 80

        Chart {
            ForEach(Array(rounds.enumerated()), id: \.offset) { index, round in
                LineMark(x: .value("Round", index + 1), y: .value("Accuracy %", round.accuracy * 100))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            RuleMark(y: .value("Mastery bar", MasteryTracker.requiredAccuracy * 100))
                .foregroundStyle(DS.Palette.success.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("95% counts toward mastery").font(DS.Typography.caption).foregroundStyle(.secondary)
                }
        }
        .chartYScale(domain: max(0, min(lowest, 90) - 5)...100)
        .chartXAxisLabel("Recent rounds")
        .frame(height: 120)
        .accessibilityLabel("Accuracy of recent Learn rounds")
    }
}

// MARK: - Heatmap

struct KeyboardHeatmapView: View {
    enum Metric: String, CaseIterable, Identifiable {
        case accuracy = "Errors", speed = "Speed"
        var id: Self { self }
    }

    /// A key needs this many attempts (or timed presses) before it is coloured.
    static let minimumAttempts = 10

    let profile: TypingProfile
    @State private var metric: Metric

    init(profile: TypingProfile, metric: Metric = .accuracy) {
        self.profile = profile
        _metric = State(initialValue: metric)
    }

    private let keySize: CGFloat = 40
    private let gap: CGFloat = 5

    var body: some View {
        let rows = KeyboardLayout.heat(for: profile)
        let values = rows.joined().compactMap(value(of:))

        VStack(alignment: .leading, spacing: DS.Space.m) {
            OptionBar(options: Metric.allCases, selection: $metric) { $0.rawValue }

            if values.isEmpty {
                EmptyNote()
            } else {
                let low = values.min() ?? 0, high = values.max() ?? 1

                VStack(alignment: .leading, spacing: gap) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(spacing: gap) {
                            ForEach(row) { heat in
                                keyView(heat, low: low, high: high)
                            }
                        }
                        .padding(.leading, KeyboardLayout.rowOffsets[index] * (keySize + gap))
                    }
                }

                HStack(spacing: DS.Space.xs) {
                    Text(metric == .accuracy ? "Fewer errors" : "Faster")
                    LinearGradient(colors: [tint.opacity(0.06), tint.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 100, height: 6)
                        .clipShape(Capsule())
                    Text(metric == .accuracy ? "More errors" : "Slower")
                    Text("·  Keys typed fewer than \(Self.minimumAttempts) times are left blank.")
                }
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var tint: Color { metric == .accuracy ? DS.Palette.error : DS.Palette.caution }

    private func value(of heat: KeyHeat) -> Double? {
        switch metric {
        case .accuracy: heat.attempts >= Self.minimumAttempts ? heat.errorRate : nil
        case .speed: heat.latencySamples >= Self.minimumAttempts ? heat.meanLatency : nil
        }
    }

    private func keyView(_ heat: KeyHeat, low: Double, high: Double) -> some View {
        let value = value(of: heat)
        let intensity = value.map { high > low ? ($0 - low) / (high - low) : 0 }
        let width = heat.key.base == " " ? KeyboardLayout.spaceBarWidth * (keySize + gap) - gap : keySize

        return VStack(spacing: 1) {
            Text(heat.key.base == " " ? "space" : String(heat.key.base).uppercased())
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(value == nil ? .tertiary : .primary)
            Text(value.map(valueText) ?? " ")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(width: width, height: keySize)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.key)
                .fill(intensity.map { tint.opacity(0.06 + 0.64 * $0) } ?? Color.primary.opacity(0.025))
        )
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.key).strokeBorder(DS.Palette.hairline))
        .help(tooltip(heat))
        .accessibilityElement()
        .accessibilityLabel(tooltip(heat))
    }

    private func valueText(_ value: Double) -> String {
        metric == .accuracy ? String(format: "%.0f%%", value * 100) : "\(Int((value * 1000).rounded()))"
    }

    private func tooltip(_ heat: KeyHeat) -> String {
        let name = heat.key.shifted.map { "\(heat.key.label) \($0)" } ?? heat.key.label
        guard heat.attempts > 0 else { return "\(name): not typed yet" }
        var text = "\(name): \(heat.errors) wrong in \(heat.attempts) attempts"
        if let rate = heat.errorRate { text += String(format: " (%.1f%%)", rate * 100) }
        if let latency = heat.meanLatency { text += ", \(latency.millisecondsText) average" }
        return text
    }
}
