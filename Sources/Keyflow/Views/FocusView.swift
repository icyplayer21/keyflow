import KeyflowCore
import SwiftUI

/// Focus: what to train, and why. Recommendations come straight from the
/// weakness analysis used by Progress.
struct FocusView: View {
    let store: StatisticsStore?
    var takeTest: (() -> Void)?
    @State private var report: ProgressReport?

    var body: some View {
        ScrollView {
            FocusReportView(report: report, takeTest: takeTest)
                .frame(maxWidth: DS.Layout.readingWidth, alignment: .leading)
                .padding(.horizontal, DS.Layout.pagePadding)
                .padding(.vertical, DS.Space.xl)
                .frame(maxWidth: .infinity)
        }
        .softScrollEdge()
        .background(.background)
        .task(id: store?.summaries.count) {
            report = ProgressAnalyzer.report(for: store?.analyzedSessions() ?? [])
        }
    }
}

/// The Focus page for a given report; `nil` while it is still loading.
struct FocusReportView: View {
    let report: ProgressReport?
    var takeTest: (() -> Void)?

    var body: some View {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("Focus").font(DS.Typography.pageTitle)
                    Text("Targeted practice for what you find hardest, based on your own tests and practice sessions.")
                        .font(DS.Typography.body)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: DS.Space.m) {
                    SectionHeader(title: "Recommended",
                                  caption: "Chosen automatically. Each one is measurably worse than your own average, not just a one-off slip.")
                    if let report {
                        recommendations(report)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: DS.Space.m) {
                    SectionHeader(title: "Manual",
                                  caption: "Pick your own keys, letter combinations or words, and choose accuracy or speed.")
                    EmptyNote("Manual training is not built yet. Neither is starting a session from a recommendation above.")
                }
            }
    }

    @ViewBuilder
    private func recommendations(_ report: ProgressReport) -> some View {
        let weaknesses = report.weaknesses
        if !weaknesses.hasEnoughData {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                EmptyNote("Not enough data yet. Recommendations appear after \(weaknesses.keystrokesNeeded) keystrokes of tests and practice; you have typed \(weaknesses.keystrokes).")
                if let takeTest {
                    Button(action: takeTest) { Label("Take a Test", systemImage: "stopwatch") }
                        .buttonStyle(.keyflowPrimary)
                }
            }
        } else if weaknesses.all.isEmpty {
            EmptyNote("Nothing stands out right now. Your keys, letter pairs and words all sit close to your own average.")
        } else {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                group("Accuracy", weaknesses.accuracy.prefix(3))
                group("Speed", weaknesses.speed.prefix(3))
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ weaknesses: ArraySlice<Weakness>) -> some View {
        if !weaknesses.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Eyebrow(title)
                ForEach(Array(weaknesses)) { weakness in
                    RecommendationRow(weakness: weakness)
                }
            }
        }
    }
}

/// One recommendation with a plain-language reason.
private struct RecommendationRow: View {
    let weakness: Weakness

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
            Text(WeaknessRow.label(for: weakness))
                .font(DS.Typography.metric(17))
                .frame(minWidth: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(WeaknessRow.kind(of: weakness)).font(DS.Typography.bodyEmphasis)
                Text(reason)
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var reason: String {
        let times = String(format: "%.1f×", weakness.severity)
        switch weakness.dimension {
        case .accuracy:
            return "Why: you mistype it \(percent(weakness.value)) of the time — \(times) your usual \(percent(weakness.baseline)). Based on \(weakness.samples) attempts."
        case .speed:
            return "Why: it takes \(weakness.value.millisecondsText) on average — \(times) your usual \(weakness.baseline.millisecondsText). Based on \(weakness.samples) timed samples."
        }
    }

    private func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }
}
