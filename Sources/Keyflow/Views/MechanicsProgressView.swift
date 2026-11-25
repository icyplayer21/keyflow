import Charts
import KeyflowCore
import SwiftUI

/// Progress ▸ Typing Mechanics: concise history, Capitalisation Overhead,
/// the personal Shift vs Caps Lock comparison, and what to practise next.
struct MechanicsProgressView: View {
    let history: MechanicsHistory
    var open: ((MechanicsRecommendation) -> Void)?
    @Environment(Preferences.self) private var preferences: Preferences?

    var body: some View {
        if history.rounds == 0 {
            EmptyNote("No Typing Mechanics rounds yet. Open Learn ▸ Typing Mechanics to start with Shift Control.")
        } else {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                MetricRow(metrics: [
                    Metric(value: "\(history.rounds)", label: "Rounds"),
                    Metric(value: history.recentCharacterAccuracy?.percentText ?? "–", label: "Characters",
                           help: "Last \(MechanicsHistory.recentRounds) rounds"),
                    Metric(value: history.recentTechniqueAccuracy?.percentText ?? "–", label: "Technique",
                           help: "Last \(MechanicsHistory.recentRounds) rounds, where a method was required"),
                    Metric(value: "\(history.steadyStages) of \(history.stages)", label: "Stages steady"),
                ])

                HStack(alignment: .top, spacing: DS.Space.xl) {
                    AccuracyHistoryChart(points: Array(history.points.suffix(60)))
                    OverheadHistoryChart(points: history.overheadPoints.filter { $0.index > history.rounds - 60 })
                }

                OverheadPanel(estimates: history.overhead)

                MethodComparisonView(history: history)

                if preferences?.adaptiveRecommendations ?? true, !history.recommendations.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Eyebrow("Recommended practice")
                        ForEach(history.recommendations) { recommendation in
                            HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                                Image(systemName: "scope").foregroundStyle(Color.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recommendation.title).font(DS.Typography.bodyEmphasis)
                                    Text(recommendation.evidence).font(DS.Typography.body).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: DS.Space.s)
                                if let open {
                                    Button("Open \(recommendation.area.title)") { open(recommendation) }
                                        .buttonStyle(.quiet)
                                }
                            }
                        }
                    }
                }
            }
            .monospacedDigit()
        }
    }
}

/// Character and technique accuracy for each round.
private struct AccuracyHistoryChart: View {
    let points: [MechanicsHistory.RoundPoint]

    /// Up to 100%, from a little below the lowest value (and no higher than 80%).
    private var floor: Double {
        let lowest = points.flatMap { [$0.characterAccuracy, $0.techniqueAccuracy ?? 1] }.min() ?? 1
        return min(80, ((lowest * 100 - 5) / 10).rounded(.down) * 10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Eyebrow("Accuracy by round")
            if points.count < 3 {
                EmptyNote()
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("Round", point.index), y: .value("Accuracy", point.characterAccuracy * 100),
                                 series: .value("Kind", "Characters"))
                            .foregroundStyle(by: .value("Kind", "Characters"))
                            .symbol(by: .value("Kind", "Characters"))
                        if let technique = point.techniqueAccuracy {
                            LineMark(x: .value("Round", point.index), y: .value("Accuracy", technique * 100),
                                     series: .value("Kind", "Technique"))
                                .foregroundStyle(by: .value("Kind", "Technique"))
                                .symbol(by: .value("Kind", "Technique"))
                        }
                    }
                }
                .chartForegroundStyleScale(["Characters": Color.accentColor, "Technique": Color.secondary])
                .chartYScale(domain: floor...100)
                .chartYAxisLabel("%")
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 130)
                .accessibilityLabel("Character and technique accuracy for each Typing Mechanics round")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Each round's own median overhead per run, per method.
private struct OverheadHistoryChart: View {
    let points: [MechanicsHistory.OverheadPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Eyebrow("Overhead by round (median per run)")
            if points.count < 3 {
                EmptyNote("Not enough data yet: rounds need \(MechanicsHistory.pointRuns) or more timed runs of capitals.")
            } else {
                Chart {
                    RuleMark(y: .value("No overhead", 0))
                        .foregroundStyle(Color.primary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    ForEach(points) { point in
                        PointMark(x: .value("Round", point.index), y: .value("ms", point.overheadMs))
                            .foregroundStyle(by: .value("Method", point.method.title))
                            .symbol(by: .value("Method", point.method.title))
                    }
                }
                .chartForegroundStyleScale(["Shift": Color.accentColor, "Caps Lock": DS.Palette.caution])
                .chartYAxisLabel("ms")
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 130)
                .accessibilityLabel("Capitalisation overhead for each round, by method")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shift vs Caps Lock by length of capitals, from Lab comparisons only.
private struct MethodComparisonView: View {
    let history: MechanicsHistory

    private struct Bar: Identifiable {
        let group: SegmentLength
        let method: String
        let estimate: CapitalisationOverhead.Estimate
        var id: String { "\(group.rawValue)-\(method)" }
    }

    var body: some View {
        let bars = history.methodComparison.flatMap { comparison -> [Bar] in
            [Bar(group: comparison.group, method: "Shift", estimate: comparison.shift),
             Bar(group: comparison.group, method: "Caps Lock", estimate: comparison.capsLock)]
        }
        .filter(\.estimate.isSufficient)

        VStack(alignment: .leading, spacing: DS.Space.s) {
            Eyebrow("Shift vs Caps Lock by length of capitals")
            Text(history.methodSummary).font(DS.Typography.bodyEmphasis)
                .fixedSize(horizontal: false, vertical: true)

            if !bars.isEmpty {
                Chart(bars) { bar in
                    if let range = bar.estimate.range {
                        RuleMark(x: .value("Letters", bar.group.title),
                                 yStart: .value("Low", range.lowerBound), yEnd: .value("High", range.upperBound))
                            .foregroundStyle(by: .value("Method", bar.method))
                            .position(by: .value("Method", bar.method))
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .opacity(0.45)
                    }
                    PointMark(x: .value("Letters", bar.group.title), y: .value("Overhead", bar.estimate.overheadMs ?? 0))
                        .foregroundStyle(by: .value("Method", bar.method))
                        .symbol(by: .value("Method", bar.method))
                        .position(by: .value("Method", bar.method))
                }
                .chartXScale(domain: SegmentLength.allCases.map(\.title))
                .chartForegroundStyleScale(["Shift": Color.accentColor, "Caps Lock": DS.Palette.caution])
                .chartXAxisLabel("Letters in a row in capitals")
                .chartYAxisLabel("Overhead per run, ms")
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 170)
                .accessibilityLabel("Median capitalisation overhead by length of capitals, Shift against Caps Lock, with 95% ranges")
            }

            Grid(alignment: .leading, horizontalSpacing: DS.Space.l, verticalSpacing: 3) {
                GridRow {
                    Text("Letters").font(DS.Typography.caption).foregroundStyle(.secondary)
                    Text("Shift").font(DS.Typography.caption).foregroundStyle(.secondary)
                    Text("Caps Lock").font(DS.Typography.caption).foregroundStyle(.secondary)
                    Text("So far").font(DS.Typography.caption).foregroundStyle(.secondary)
                }
                ForEach(history.methodComparison) { row in
                    GridRow {
                        Text(row.group.title).font(DS.Typography.code)
                        Text(cell(row.shift)).font(DS.Typography.body)
                        Text(cell(row.capsLock)).font(DS.Typography.body)
                        Text(verdict(row.verdict)).font(DS.Typography.body).foregroundStyle(.secondary)
                    }
                }
            }
            Text("From \(history.comparisonsDone) Lab \(history.comparisonsDone == 1 ? "comparison" : "comparisons"): the same passages with each method, alternating which comes first. A method counts as faster only when the 95% ranges do not overlap.")
                .font(DS.Typography.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cell(_ estimate: CapitalisationOverhead.Estimate) -> String {
        guard let overhead = estimate.overheadMs else {
            return "\(estimate.runs) of \(CapitalisationOverhead.minimumRuns) runs"
        }
        return "\(OverheadFormat.signed(overhead)) (\(estimate.runs))"
    }

    private func verdict(_ verdict: MethodComparison.Verdict) -> String {
        switch verdict {
        case .shiftFaster: "Shift faster"
        case .capsLockFaster: "Caps Lock faster"
        case .noClearDifference: "No clear difference"
        case .insufficient: "Not enough data yet"
        }
    }
}
