import Charts
import KeyflowCore
import SwiftUI

// MARK: - Status styling

extension FingerStatus {
    /// The same restrained hues as the heatmap; every state also has its
    /// own symbol, so colour is never the only signal.
    var tint: Color { heatTint }

    var symbol: String {
        switch self {
        case .strong: "checkmark"
        case .developing: "circle.lefthalf.filled"
        case .needsPractice: "exclamationmark"
        case .insufficientData: "minus"
        }
    }

    /// Short label for the legend and heatmap.
    var shortTitle: String {
        self == .insufficientData ? "Insufficient Data" : title
    }
}

// MARK: - Section

/// Progress → Finger Performance: the hand heatmap and the selected finger's details.
struct FingerPerformanceView: View {
    let intelligence: FingerIntelligenceReport
    var train: ((FingerFocusTarget) -> Void)?
    var check: ((FingerFocusTarget) -> Void)?
    @State private var selection: HandFinger?

    var body: some View {
        let selected = selection ?? defaultSelection

        VStack(alignment: .leading, spacing: DS.Space.l) {
            VStack(spacing: DS.Space.s) {
                HandHeatmap(report: intelligence.report, selection: Binding(get: { selected }, set: { selection = $0 }))
                StatusLegend()
            }
            .frame(maxWidth: .infinity)

            Divider()

            FingerDetailPanel(finger: selected, intelligence: intelligence, train: train, check: check)
        }
    }

    /// The finger most in need of practice, else the left pinky.
    private var defaultSelection: HandFinger {
        HandFinger.keyboardOrder.first { intelligence.report[$0.finger].status == .needsPractice } ?? .leftPinky
    }
}

private struct StatusLegend: View {
    var body: some View {
        HStack(spacing: DS.Space.l) {
            ForEach(FingerStatus.allCases, id: \.self) { status in
                HStack(spacing: 6) {
                    FingerStatusBadge(status: status, size: 14)
                    Text(status.shortTitle)
                }
            }
        }
        .font(DS.Typography.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Legend: Strong, Developing, Needs Practice, Insufficient Data")
    }
}

/// A small round badge with the status symbol.
struct FingerStatusBadge: View {
    let status: FingerStatus
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            Circle().fill(status.tint.opacity(status == .insufficientData ? 0.08 : 0.18))
            Circle().strokeBorder(status.tint.opacity(status == .insufficientData ? 0.45 : 0.75), lineWidth: 1)
            Image(systemName: status.symbol)
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(status.tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Heatmap

/// Both hands, drawn from the SVG artwork, every finger selectable. Arrow
/// keys move the selection when the heatmap has keyboard focus.
struct HandHeatmap: View {
    let report: FingerReport
    @Binding var selection: HandFinger
    @State private var hovered: HandFinger?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.xxl) {
            hand(.left)
            hand(.right)
        }
        .padding(.vertical, DS.Space.xs)
        .padding(.horizontal, DS.Space.m)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.panel)
                .strokeBorder(Color.accentColor.opacity(focused ? 0.45 : 0), lineWidth: 1.5)
        )
        .onKeyPress(.leftArrow) { move(-1) }
        .onKeyPress(.rightArrow) { move(1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Finger heatmap. Use the left and right arrow keys to choose a finger.")
    }

    @ViewBuilder
    private func hand(_ hand: Hand) -> some View {
        VStack(spacing: DS.Space.xxs) {
            if let artwork = HandArtwork.artwork(for: hand) {
                HandIllustration(
                    artwork: artwork,
                    statuses: Dictionary(uniqueKeysWithValues: HandFinger.allCases.map { ($0, report[$0.finger].status) }),
                    selection: selection,
                    select: { selection = $0 },
                    describe: { finger in
                        let estimate = report[finger.finger]
                        return "Estimated \(estimate.status.title), \(estimate.confidence.title.lowercased()) confidence"
                    },
                    hovered: $hovered
                )
                .frame(minHeight: 170, maxHeight: 270)
            } else {
                EmptyNote("The hand illustration could not be loaded.")
            }
            Text(caption(for: hand))
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(height: 14)
        }
        .frame(maxWidth: 260)
    }

    /// "Left Hand", or the finger under the pointer in that hand.
    private func caption(for hand: Hand) -> String {
        if let hovered, hovered.hand == hand {
            return "\(hovered.title) · \(report[hovered.finger].status.shortTitle)"
        }
        return hand == .left ? "Left Hand" : "Right Hand"
    }

    private func move(_ step: Int) -> SwiftUI.KeyPress.Result {
        let order = HandFinger.keyboardOrder
        guard let index = order.firstIndex(of: selection) else { return .ignored }
        selection = order[(index + step + order.count) % order.count]
        return .handled
    }
}

// MARK: - Detail panel

struct FingerDetailPanel: View {
    let finger: HandFinger
    let intelligence: FingerIntelligenceReport
    var train: ((FingerFocusTarget) -> Void)?
    var check: ((FingerFocusTarget) -> Void)?

    var body: some View {
        let estimate = intelligence.estimate(finger.finger)
        let observation = estimate.observation
        let trend = intelligence.trend(finger.finger)

        VStack(alignment: .leading, spacing: DS.Space.l) {
            // Title row
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(finger.title).font(DS.Typography.pageTitle)
                    Text(assignmentText)
                        .font(DS.Typography.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    FingerStatusBadge(status: estimate.status, size: 18)
                    Text(estimate.status.title).font(DS.Typography.bodyEmphasis)
                }
                .accessibilityElement(children: .combine)
            }

            // Estimates
            Grid(alignment: .topLeading, horizontalSpacing: DS.Space.xl, verticalSpacing: DS.Space.m) {
                GridRow {
                    item("Estimated accuracy", accuracyText(estimate))
                    item("Relative speed", speedText(estimate),
                         help: "Compared with your own average for the same kinds of key change (repeated key, same finger, same hand, other hand, space).")
                    item("Data confidence", estimate.confidence.title,
                         help: "From the number of presses and timed key changes behind the estimate.")
                }
                GridRow {
                    item("Most problematic key", problemKeyText(estimate))
                    item("Slowest key change", transitionText(estimate))
                    item("Samples", "\(observation.presses) presses · \(estimate.observation.timingSamples) timed")
                }
                GridRow {
                    item("Mistakes", mistakesText(observation),
                         help: "Each wrong press counts once. Corrected means the final text was right at that spot.")
                    item("Recent trend", trendText(trend),
                         help: "Your last \(FingerTrends.recentSessions) sessions against the ones before. Changes are called only when unlikely to be chance.")
                    item("Training", trainingText)
                }
            }
            .monospacedDigit()

            if trend.points.filter({ $0.accuracy != nil }).count >= 3 {
                FingerTrendCharts(points: trend.points)
            }

            // Baseline and retest
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Eyebrow("Baseline and retest")
                if let comparison = intelligence.comparison(finger.finger) {
                    ComparisonView(comparison: comparison)
                } else if finger.isThumb {
                    Text("Thumbs have no finger check: Space is practised in every Practice session.")
                        .font(DS.Typography.body).foregroundStyle(.secondary)
                } else if intelligence.checks(finger.finger).count == 1 {
                    Text("Baseline taken \(intelligence.checks(finger.finger)[0].date.formatted(date: .abbreviated, time: .omitted)). Train, then retest to compare.")
                        .font(DS.Typography.body).foregroundStyle(.secondary)
                } else {
                    Text("No baseline check yet. Take one before training so a retest has something to compare with.")
                        .font(DS.Typography.body).foregroundStyle(.secondary)
                }
            }

            // Why
            if !estimate.reasons.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow("Why \(estimate.status == .insufficientData ? "no estimate yet" : "this status")")
                    ForEach(estimate.reasons, id: \.self) { reason in
                        Text("· \(reason)").font(DS.Typography.body).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // Actions
            HStack(spacing: DS.Space.xs) {
                if let target = finger.trainingTarget {
                    Button { train?(target) } label: { Label("Start Finger Training", systemImage: "hand.point.up.left") }
                        .buttonStyle(.keyflowPrimary)
                        .disabled(train == nil)
                    Button { check?(target) } label: {
                        Label(intelligence.checks(finger.finger).isEmpty ? "Baseline Check" : "Retest This Finger",
                              systemImage: "gauge.with.needle")
                    }
                    .buttonStyle(.quiet)
                    .disabled(check == nil)
                } else {
                    Text("Thumbs press only Space, so Finger Focus has no thumb drills. Practice sessions train Space timing.")
                        .font(DS.Typography.body)
                        .foregroundStyle(.secondary)
                }
            }

            Text("All figures are estimates based on standard US QWERTY finger assignments. Keyflow cannot see which finger you actually use. This is a practice aid, not a medical or scientific measure of dexterity.")
                .font(DS.Typography.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Text

    private var assignmentText: String {
        if finger.isThumb {
            return "Space bar, shared by both thumbs: this estimate covers both."
        }
        let keys = finger.assignedKeys.map { TrainingKeyboardView.name(of: $0) }.joined(separator: " ")
        return "Standard assignment: \(keys)"
    }

    private var trainingText: String {
        let rounds = intelligence.trainingRounds(finger.finger)
        guard !finger.isThumb else { return "No thumb drills" }
        let steady = intelligence.steadyLevels(finger.finger)
        return "\(rounds) Finger Focus \(rounds == 1 ? "round" : "rounds") · \(steady) of \(FingerFocusLevel.allCases.count) levels steady"
    }

    private func item(_ label: String, _ value: String, help: String = "") -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Eyebrow(label)
            Text(value)
                .font(DS.Typography.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(help)
        .accessibilityElement(children: .combine)
    }

    private func accuracyText(_ estimate: FingerEstimate) -> String {
        guard let accuracy = estimate.accuracy, let range = estimate.accuracyRange else { return "Not enough data yet" }
        if estimate.confidence <= .low {
            return "About \(Int((accuracy * 100).rounded()))% (likely \(Int((range.lowerBound * 100).rounded()))–\(Int((range.upperBound * 100).rounded()))%)"
        }
        return "\(Int((accuracy * 100).rounded()))%"
    }

    private func speedText(_ estimate: FingerEstimate) -> String {
        guard let ratio = estimate.relativeLatency, let range = estimate.latencyRange else { return "Not enough timing data yet" }
        if range.contains(1) { return "Close to your average" }
        if estimate.confidence <= .low { return ratio > 1 ? "Slower than your average" : "Faster than your average" }
        return FingerFormat.relativeSpeed(ratio)
    }

    private func problemKeyText(_ estimate: FingerEstimate) -> String {
        guard let issue = estimate.problemKey else {
            return estimate.status == .insufficientData ? "Not enough data yet" : "None stands out"
        }
        return "\(TrainingKeyboardView.name(of: issue.key)) · \(issue.count.errors) of \(issue.count.attempts) presses wrong"
    }

    private func transitionText(_ estimate: FingerEstimate) -> String {
        guard let slow = estimate.slowTransition else {
            return estimate.status == .insufficientData ? "Not enough data yet" : "None stands out"
        }
        let names = slow.transition.map { TrainingKeyboardView.name(of: $0) }.joined(separator: " → ")
        let percent = Int(((slow.ratio - 1) * 100 / 5).rounded()) * 5
        return "\(names) · about \(percent)% slower than similar key changes (\(slow.samples) times)"
    }

    private func mistakesText(_ observation: FingerObservation) -> String {
        guard observation.presses > 0 else { return "Not enough data yet" }
        let positions = observation.correctedErrors + observation.uncorrectedErrors
        return "\(observation.incorrect) wrong \(observation.incorrect == 1 ? "press" : "presses") at \(positions) \(positions == 1 ? "spot" : "spots"): \(observation.correctedErrors) corrected, \(observation.uncorrectedErrors) left"
    }

    private func trendText(_ trend: FingerTrend) -> String {
        if trend.accuracy == .insufficientData, trend.latency == .insufficientData { return "Not enough data yet" }
        return "Accuracy: \(trend.accuracy.title.lowercased()) · Speed: \(trend.latency.title.lowercased())"
    }
}

/// Per-session accuracy and relative latency for one finger.
private struct FingerTrendCharts: View {
    let points: [FingerTrendPoint]

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.xl) {
            chart(title: "Accuracy by session", values: points.compactMap { p in p.accuracy.map { (p.index, $0 * 100) } },
                  unit: "%", reference: nil)
            chart(title: "Time vs your average (1 = average)",
                  values: points.compactMap { p in p.relativeLatency.map { (p.index, $0) } }, unit: "×", reference: 1)
        }
    }

    private func chart(title: String, values: [(Int, Double)], unit: String, reference: Double?) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Eyebrow(title)
            if values.count < 3 {
                EmptyNote()
            } else {
                Chart {
                    ForEach(values, id: \.0) { index, value in
                        LineMark(x: .value("Session", index), y: .value(unit, value))
                            .foregroundStyle(Color.accentColor)
                        PointMark(x: .value("Session", index), y: .value(unit, value))
                            .foregroundStyle(Color.accentColor)
                            .symbolSize(14)
                    }
                    if let reference {
                        RuleMark(y: .value("Average", reference))
                            .foregroundStyle(Color.primary.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis(.hidden)
                .frame(height: 90)
                .accessibilityLabel(title)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
