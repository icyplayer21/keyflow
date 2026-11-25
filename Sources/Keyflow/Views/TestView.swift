import Charts
import KeyflowCore
import SwiftUI

struct TestView: View {
    @Bindable var model: TypingSessionModel
    let store: StatisticsStore?
    var showProgress: (() -> Void)?
    var trainFinger: ((FingerFocusTarget) -> Void)?
    @State private var keyboard = KeyboardMonitor()
    @Environment(\.typingWidth) private var typingWidth

    var body: some View {
        let running = model.phase == .running

        Group {
            if model.phase == .finished, let result = model.result {
                ScrollView {
                    TestResultsView(model: model, result: result, showProgress: showProgress,
                                    store: store, trainFinger: trainFinger)
                        .frame(maxWidth: DS.Layout.readingWidth)
                        .padding(.horizontal, DS.Layout.pagePadding)
                        .padding(.vertical, DS.Space.xl)
                        .frame(maxWidth: .infinity)
                }
                .softScrollEdge()
                .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    VStack(spacing: DS.Space.xs) {
                        Eyebrow("Test length")
                        DurationPicker(model: model, font: .system(size: 15, weight: .medium))
                    }
                    .padding(.top, DS.Space.l)
                    .opacity(running ? 0 : 1)
                    .allowsHitTesting(!running)
                    .motion(DS.Motion.standard, value: running)

                    Spacer(minLength: DS.Space.l)

                    VStack(alignment: .leading, spacing: DS.Space.l) {
                        TypingAreaView(model: model)
                        HistoryLine(model: model, store: store)
                            .opacity(running ? 0 : 1)
                            .motion(DS.Motion.standard, value: running)
                    }
                    .frame(maxWidth: typingWidth)
                    .padding(.horizontal, DS.Layout.pagePadding)

                    Spacer(minLength: DS.Space.l)

                    HStack(spacing: DS.Space.m) {
                        RestartButton(action: model.restart)
                        ShortcutHints()
                    }
                    .frame(height: 28)
                    .padding(.bottom, DS.Space.l)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .motion(DS.Motion.standard, value: model.phase)
        .onAppear { keyboard.start { model.handle($0) } }
        .onDisappear { keyboard.stop() }
    }
}

/// One line of context from saved history, shown before a test starts.
private struct HistoryLine: View {
    let model: TypingSessionModel
    let store: StatisticsStore?

    var body: some View {
        let count = store?.summaries(of: .test).count ?? 0
        let best = store?.personalBest(of: .test, timeLimit: model.durationSeconds)
        let saved = "\(count) \(count == 1 ? "test" : "tests") saved"

        Group {
            if let best {
                Text("Best at \(model.durationSeconds)s: \(Int(best.metrics.netWPM.rounded())) WPM, \(best.metrics.accuracy.percentText) accuracy  ·  \(saved)")
            } else if count > 0 {
                Text("No \(model.durationSeconds)s test yet  ·  \(saved)")
            } else {
                Text("Your first test starts your history. The clock starts with your first keystroke.")
            }
        }
        .font(DS.Typography.body)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
}

struct TestResultsView: View {
    let model: TypingSessionModel
    let result: TypingSessionModel.Result
    var showProgress: (() -> Void)?
    var store: StatisticsStore?
    var trainFinger: ((FingerFocusTarget) -> Void)?
    @Environment(Preferences.self) private var preferences: Preferences?

    private var metrics: PerformanceMetrics { result.metrics }
    private var analysis: SessionAnalysis { result.analysis }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                if result.isPersonalBest {
                    Label("New personal best for \(model.durationSeconds) seconds", systemImage: "trophy")
                        .font(DS.Typography.bodyEmphasis)
                        .foregroundStyle(Color.accentColor)
                }

                HStack(alignment: .top, spacing: DS.Space.xxl) {
                    Metric(value: "\(Int(metrics.netWPM.rounded()))", label: "Net WPM", size: 64, weight: .semibold, tint: .accentColor)
                    Metric(value: metrics.accuracy.percentText, label: "Accuracy", size: 64, weight: .semibold)
                }

                MetricRow(metrics: [
                    Metric(value: "\(Int(metrics.rawWPM.rounded()))", label: "Raw WPM"),
                    Metric(value: analysis.consistency?.percentText ?? "–", label: "Consistency"),
                    Metric(value: "\(metrics.incorrectKeystrokes)", label: "Errors"),
                    Metric(value: String(format: "%.1f", analysis.errorsPerMinute), label: "Errors/min"),
                    Metric(value: analysis.meanLatency.map { "\(Int(($0 * 1000).rounded()))" } ?? "–", label: "Latency ms"),
                    Metric(value: "\(metrics.backspaces)", label: "Backspaces"),
                ])
            }

            HStack(spacing: DS.Space.xs) {
                Button(action: model.restart) {
                    Label("Next Test", systemImage: "arrow.right")
                }
                .buttonStyle(.keyflowPrimary)
                .help("Return or Tab")
                if let showProgress {
                    Button(action: showProgress) {
                        Label("View Progress", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .buttonStyle(.quietGlass)
                }
                Spacer()
                SaveStatusView(model: model)
            }

            Divider()

            SpeedChart(timeline: analysis.wpmTimeline, average: metrics.rawWPM)

            Divider()

            VStack(alignment: .leading, spacing: DS.Space.l) {
                SectionHeader(title: "What to look at",
                              caption: "From this test alone. One test is not enough to call something a weakness; Progress tracks that across tests.")
                Grid(alignment: .topLeading, horizontalSpacing: DS.Space.xl, verticalSpacing: DS.Space.l) {
                    GridRow {
                        InsightList(title: "Mistyped words", caption: "With a wrong keystroke",
                                    rows: analysis.mistypedWords.prefix(5).map { word in
                                        (word.word, word.mistakes == 1 ? "once" : "\(word.mistakes)×")
                                    })
                        InsightList(title: "Most missed keys", caption: "Errors of attempts",
                                    rows: analysis.mostMissedKeys().map { key in
                                        (keyLabel(key.character), "\(key.errors) of \(key.attempts)")
                                    })
                    }
                    GridRow {
                        InsightList(title: "Slowest letter pairs", caption: "Typed twice or more",
                                    rows: analysis.slowestBigrams().map { pair in
                                        (pair.bigram, relative(pair.meanLatency, to: analysis.meanBigramLatency))
                                    })
                        InsightList(title: "Slowest keys", caption: "Typed three times or more",
                                    rows: analysis.slowestKeys().map { key in
                                        (keyLabel(key.character), relative(key.meanLatency ?? 0, to: analysis.meanLatency))
                                    })
                    }
                }
            }

            if let store, preferences?.adaptiveRecommendations ?? true {
                Divider()
                FingerInsightsSection(store: store, trainFinger: trainFinger)
            }

            Divider()

            MetricDefinitionsView()
        }
        .monospacedDigit()
    }

    private func keyLabel(_ character: Character) -> String {
        character == " " ? "space" : String(character)
    }

    /// "182 ms  +38%": a latency and how far it sits above the baseline.
    private func relative(_ latency: TimeInterval, to baseline: TimeInterval?) -> String {
        guard let baseline, baseline > 0 else { return latency.millisecondsText }
        let percent = Int(((latency / baseline - 1) * 100).rounded())
        return "\(latency.millisecondsText)  +\(percent)%"
    }
}

/// Raw speed across the test, smoothed over three seconds.
private struct SpeedChart: View {
    let timeline: [Double]
    let average: Double

    private var points: [(second: Int, wpm: Double)] {
        timeline.indices.map { index in
            let window = timeline[max(0, index - 1)...min(timeline.count - 1, index + 1)]
            return (index + 1, window.reduce(0, +) / Double(window.count))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            SectionHeader(title: "Speed during the test", caption: "Raw WPM each second; the dashed line is your average.")
            if timeline.count < 3 {
                EmptyNote()
            } else {
                Chart {
                    ForEach(points, id: \.second) { point in
                        AreaMark(x: .value("Second", point.second), y: .value("Raw WPM", point.wpm))
                            .foregroundStyle(Color.accentColor.opacity(0.08))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Second", point.second), y: .value("Raw WPM", point.wpm))
                            .foregroundStyle(Color.accentColor)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            .interpolationMethod(.monotone)
                    }
                    RuleMark(y: .value("Average", average))
                        .foregroundStyle(Color.primary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartXScale(domain: 1...max(2, timeline.count))
                .chartXAxisLabel("Seconds")
                .frame(height: 140)
                .accessibilityLabel("Raw words per minute for each second of the test")
            }
        }
    }
}

/// A titled list of label/value rows. No card: whitespace does the separating.
struct InsightList: View {
    let title: String
    let caption: String
    let rows: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(DS.Typography.bodyEmphasis)
                Spacer()
                Text(caption).font(DS.Typography.caption).foregroundStyle(.tertiary)
            }
            if rows.isEmpty {
                EmptyNote()
            } else {
                VStack(spacing: 5) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack {
                            Text(row.label).font(DS.Typography.code)
                            Spacer()
                            Text(row.value).font(DS.Typography.metric(12, weight: .regular)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Plain-language definitions of every number on the results screen.
private struct MetricDefinitionsView: View {
    @State private var expanded = false

    private static let definitions: [(String, String)] = [
        ("Net WPM", "Correct characters left in your final text, divided by 5, per minute. A word is always 5 characters, spaces included."),
        ("Raw WPM", "Every character keystroke, right or wrong and even if later deleted, divided by 5, per minute."),
        ("Accuracy", "Correct keystrokes divided by all character keystrokes. A mistake you fix with Backspace still counts as a mistake."),
        ("Backspace", "Removes a character from your text, which lowers net WPM, but is never itself counted as a keystroke."),
        ("Consistency", "How even your pace was: 100% minus the variation in keystrokes per second (standard deviation divided by the mean)."),
        ("Errors/min", "Incorrect keystrokes per minute of the test."),
        ("Latency", "Time from one keystroke to the next. Gaps after a Backspace or longer than 2 seconds are treated as corrections or pauses and left out."),
        ("Letter pairs", "Time between two letters of the same word typed correctly one after the other."),
        ("Time", "Measured on a monotonic clock from your first keystroke. Keys pressed after the limit are not counted."),
    ]

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Grid(alignment: .topLeading, horizontalSpacing: DS.Space.m, verticalSpacing: DS.Space.xs) {
                ForEach(Self.definitions, id: \.0) { name, text in
                    GridRow {
                        Text(name).font(DS.Typography.bodyEmphasis)
                        Text(text).font(DS.Typography.body).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, DS.Space.s)
        } label: {
            Text("How these are measured").font(DS.Typography.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// After a test: which fingers the confirmed weak keys and transitions
/// belong to, from your whole recent history including this test.
struct FingerInsightsSection: View {
    let store: StatisticsStore
    var trainFinger: ((FingerFocusTarget) -> Void)?
    @State private var insights: FingerInsights?

    struct FingerInsights {
        let recommendations: [FingerRecommendation]
        let weaknesses: WeaknessReport
        let report: FingerReport
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            SectionHeader(title: "Finger insights",
                          caption: "Weak keys and key changes mapped to the finger standard touch typing assigns them. Estimates only: Keyflow cannot see which finger you use.")
            if let insights {
                FingerInsightsList(insights: insights, trainFinger: trainFinger)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: store.summaries.count) {
            let progress = ProgressAnalyzer.report(for: store.analyzedSessions())
            let fingers = FingerIntelligence.build(sessions: store.fingerObservations().map { ($0.summary.date, $0.observations) })
            insights = FingerInsights(
                recommendations: FingerRecommender.recommendations(report: fingers.report, weaknesses: progress.weaknesses),
                weaknesses: progress.weaknesses,
                report: fingers.report
            )
        }
    }
}

struct FingerInsightsList: View {
    let insights: FingerInsightsSection.FingerInsights
    var trainFinger: ((FingerFocusTarget) -> Void)?

    var body: some View {
        if insights.recommendations.isEmpty {
            if !insights.weaknesses.hasEnoughData {
                EmptyNote("Not enough data yet. Finger insights start after about \(insights.weaknesses.keystrokesNeeded) keystrokes; you have \(insights.weaknesses.keystrokes).")
            } else {
                EmptyNote("No finger stands out. None of your confirmed weaknesses point to one finger.")
            }
        } else {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                ForEach(insights.recommendations) { recommendation in
                    row(recommendation)
                }
            }
        }
    }

    private func row(_ recommendation: FingerRecommendation) -> some View {
        let estimate = insights.report[recommendation.finger]

        return HStack(alignment: .top, spacing: DS.Space.s) {
            FingerStatusBadge(status: recommendation.status, size: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DS.Space.xs) {
                    Text(title(recommendation.finger)).font(DS.Typography.bodyEmphasis)
                    Text(recommendation.status.title).font(DS.Typography.caption).foregroundStyle(.secondary)
                }
                ForEach(recommendation.weaknesses.prefix(3)) { weakness in
                    Text(describe(weakness)).font(DS.Typography.body).foregroundStyle(.secondary)
                }
                if recommendation.weaknesses.isEmpty, let reason = estimate.reasons.first {
                    Text(reason).font(DS.Typography.body).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let target = recommendation.target, let trainFinger {
                Button { trainFinger(target) } label: { Label("Train", systemImage: "hand.point.up.left") }
                    .buttonStyle(.quiet)
                    .help("Open Finger Focus for this finger")
            } else if recommendation.target == nil {
                Text("Practise Space timing in Practice").font(DS.Typography.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func title(_ finger: Finger) -> String {
        finger == .thumb ? "Thumbs (Space)" : finger.title.prefix(1).uppercased() + finger.title.dropFirst()
    }

    private func describe(_ weakness: Weakness) -> String {
        let item = weakness.item.count == 2
            ? weakness.item.map { TrainingKeyboardView.name(of: $0) }.joined(separator: " → ")
            : TrainingKeyboardView.name(of: Character(weakness.item))
        switch weakness.dimension {
        case .accuracy:
            return "\(item) · wrong \(weakness.errors) of \(weakness.samples) times, against \(Int((weakness.baseline * 100).rounded()))% usually"
        case .speed:
            return "\(item) · about \(Int(((weakness.severity - 1) * 100 / 5).rounded()) * 5)% slower than your average"
        }
    }
}
