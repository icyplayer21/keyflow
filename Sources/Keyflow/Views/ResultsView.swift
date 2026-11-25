import KeyflowCore
import SwiftUI

/// Practice results: two headline numbers, details in a quiet row, one action.
struct ResultsView: View {
    let metrics: PerformanceMetrics
    let restart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            HStack(alignment: .top, spacing: DS.Space.xxl) {
                Metric(value: "\(Int(metrics.netWPM.rounded()))", label: "Net WPM", size: 56, weight: .semibold,
                       tint: .accentColor, help: "Correct characters left in your final text ÷ 5, per minute.")
                Metric(value: metrics.accuracy.percentText, label: "Accuracy", size: 56, weight: .semibold,
                       help: "Correct keystrokes ÷ all character keystrokes. Mistakes you fixed with Backspace still count.")
            }

            MetricRow(metrics: [
                Metric(value: "\(Int(metrics.rawWPM.rounded()))", label: "Raw WPM",
                       help: "Every character keystroke, right or wrong, ÷ 5, per minute."),
                Metric(value: "\(metrics.correctCharacters)/\(metrics.incorrectCharacters)", label: "Chars",
                       help: "Correct / incorrect characters in your final text."),
                Metric(value: "\(metrics.incorrectKeystrokes)", label: "Errors",
                       help: "Incorrect keystrokes, including ones you corrected."),
                Metric(value: "\(metrics.backspaces)", label: "Backspaces", help: "Characters removed with Delete."),
                Metric(value: "\(Int(metrics.elapsed.rounded()))s", label: "Time", help: "Measured from your first keystroke."),
            ])

            Button(action: restart) {
                Label("Next", systemImage: "arrow.right")
            }
            .buttonStyle(.keyflowPrimary)
            .help("Return or Tab")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
