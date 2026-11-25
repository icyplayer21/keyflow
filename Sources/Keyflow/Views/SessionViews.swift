import KeyflowCore
import SwiftUI

/// Countdown, live stats and the passage. Shared by Practice and Test.
struct TypingAreaView: View {
    let model: TypingSessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            LiveStatsView(model: model)
            TypingSurfaceView(target: model.engine.target, typed: model.engine.typed, isIdle: model.phase == .idle)
                .probedPassage()
        }
    }
}

struct DurationPicker: View {
    @Bindable var model: TypingSessionModel
    var font: Font = DS.Typography.bodyEmphasis

    var body: some View {
        OptionBar(options: model.role.durations, selection: $model.durationSeconds, font: font) { Self.label($0) }
            .help("Session length")
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Session length")
    }

    static func label(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m"
    }
}

/// The line above the passage: time left in accent while running, then
/// small, muted WPM and accuracy that never compete with the text.
struct LiveStatsView: View {
    let model: TypingSessionModel

    var body: some View {
        let running = model.phase == .running
        let metrics = model.metrics
        let seconds = running ? Int(model.remaining.rounded(.up)) : model.durationSeconds

        HStack(alignment: .firstTextBaseline, spacing: DS.Space.l) {
            Text(clock(seconds))
                .font(DS.Typography.metric(22))
                .foregroundStyle(running ? Color.accentColor : Color.secondary)
                .contentTransition(.numericText(countsDown: true))
                .motion(DS.Motion.standard, value: seconds)
                .accessibilityLabel("Time remaining")
                .accessibilityValue("\(seconds) seconds")

            if running {
                inline(metrics.elapsed >= 1 ? "\(Int(metrics.netWPM.rounded()))" : "–", "wpm")
                inline(metrics.totalKeystrokes > 0 ? metrics.accuracy.percentText : "–", "acc")
            } else {
                Text("Start typing to begin")
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 30, alignment: .bottomLeading)
        .stepsBackWhileTyping()
    }

    private func clock(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds)" }
        let remainder = seconds % 60
        return "\(seconds / 60):\(remainder < 10 ? "0" : "")\(remainder)"
    }

    // The first second is too noisy to be worth showing.
    private func inline(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(DS.Typography.metric(15)).foregroundStyle(.secondary)
            Text(label).font(DS.Typography.metric(11)).foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Saved" / "could not save" line under a results screen.
struct SaveStatusView: View {
    let model: TypingSessionModel

    var body: some View {
        if let error = model.saveError {
            Label("This session could not be saved: \(error)", systemImage: "exclamationmark.triangle")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.error)
        } else if model.result?.wasSaved == true {
            Label("Saved to your history", systemImage: "checkmark")
                .font(DS.Typography.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

extension Double {
    /// A 0...1 fraction as a whole percentage, floored so that anything short
    /// of perfect never reads as 100%.
    var percentText: String { "\(Int((self * 100).rounded(.down)))%" }
    /// Seconds as whole milliseconds.
    var millisecondsText: String { "\(Int((self * 1000).rounded())) ms" }
}
