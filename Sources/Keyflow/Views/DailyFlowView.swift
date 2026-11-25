import AppKit
import KeyflowCore
import SwiftUI

/// Learn ▸ Daily Flow: one guided session, with the next key shown only
/// after a pause.
struct DailyFlowView: View {
    @Bindable var model: DailyFlowModel
    /// Pauses the session while the tutorial is showing over it.
    var isCovered = false
    @State private var keyboard = KeyboardMonitor()

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 640
            Group {
                switch model.stage {
                case .start: DailyFlowStart(model: model, compact: compact)
                case .flowing: DailyFlowSession(model: model, compact: compact)
                case .complete(let session): DailyFlowComplete(model: model, session: session)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .motion(DS.Motion.standard, value: stageKind)
        .background(.background)
        .onAppear {
            keyboard.start { model.handle($0) }
            if model.stage == .start { model.refreshFocus() }
        }
        // Leaving pauses the session; it is never thrown away.
        .onDisappear { keyboard.stop(); model.pause() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            model.pause()
        }
        .onChange(of: isCovered) { _, covered in if covered { model.pause() } }
    }

    private var stageKind: Int {
        switch model.stage {
        case .start: 0
        case .flowing: 1
        case .complete: 2
        }
    }
}

// MARK: - Start

private struct DailyFlowStart: View {
    @Bindable var model: DailyFlowModel
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? DS.Space.m : DS.Space.l) {
            VStack(spacing: DS.Space.xxs) {
                Text("Daily Flow")
                    .font(DS.Typography.pageTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("One short session a day. Go slowly enough that you don't need to look down. Accuracy first; speed follows.")
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 500)

            OptionBar(options: DailyFlowPlan.lengths,
                      selection: Binding(get: { model.plan.minutes }, set: { model.setMinutes($0) })) { "\($0) min" }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Session length")

            VStack(alignment: .leading, spacing: DS.Space.s) {
                ForEach(DailyFlowSegment.allCases) { segment in
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
                        Text(minutes(model.plan.seconds(for: segment)))
                            .font(DS.Typography.metric(12))
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(segment.title).font(DS.Typography.bodyEmphasis)
                            Text(segment.detail).font(DS.Typography.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            VStack(spacing: DS.Space.xxs) {
                Text("Focus keys: **\(model.focusKeys.map { String($0).uppercased() }.joined(separator: " "))**")
                    .font(DS.Typography.body)
                Text(model.usesStarterKeys
                     ? "The most common letters, until Keyflow has enough of your typing."
                     : "The keys you have missed most in recent practice.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Show the next key when I pause", isOn: $model.showsKeyboard)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(DS.Typography.body)

            if let last = model.history.sessions.last {
                Text(lastLine(last))
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            VStack(spacing: DS.Space.xs) {
                Button(model.hasPractisedToday ? "Go Again" : "Start") { model.start() }
                    .buttonStyle(.keyflowPrimary)
                    .help("Start (Return)")
                HStack(spacing: 5) {
                    KeyCap("return")
                    Text("start")
                }
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DS.Layout.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func minutes(_ seconds: TimeInterval) -> String {
        let value = seconds / 60
        return value == value.rounded() ? "\(Int(value)) min" : String(format: "%.1f min", value)
    }

    private func lastLine(_ session: DailyFlowHistory.Session) -> String {
        let day = Calendar.current.isDateInToday(session.date) ? "Today"
            : session.date.formatted(date: .abbreviated, time: .omitted)
        return "Last session: \(day) · \(flowDuration(session.totals.activeSeconds)) · \(flowPercent(session.totals.accuracy)) accuracy"
    }
}

// MARK: - Session

private struct DailyFlowSession: View {
    @Bindable var model: DailyFlowModel
    let compact: Bool
    @Environment(\.typingWidth) private var typingWidth
    @State private var confirmingEnd = false

    private struct HintTimer: Hashable {
        let activity: Int
        let enabled: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            SegmentStrip(model: model)
                .frame(maxWidth: typingWidth)
                .padding(.top, compact ? DS.Space.s : DS.Space.l)
                .padding(.horizontal, DS.Layout.pagePadding)

            Spacer(minLength: DS.Space.s)

            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text(cue)
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
                TypingSurfaceView(target: model.engine.target, typed: model.engine.typed,
                                  visibleLines: 2, isIdle: model.engine.phase == .idle)
                    .opacity(model.isPaused ? 0.4 : 1)
            }
            .frame(maxWidth: typingWidth, alignment: .leading)
            .padding(.horizontal, DS.Layout.pagePadding)

            Spacer(minLength: DS.Space.s)

            // Always laid out, so nothing moves when a hint appears.
            VStack(spacing: DS.Space.xs) {
                TrainingKeyboardView(exerciseKeys: [], nextKey: model.isHintShowing ? model.nextKey : nil,
                                     miss: nil, keySize: compact ? 26 : 32)
                FingerGuideView(nextKey: model.isHintShowing ? model.nextKey : nil, compact: true)
            }
            .opacity(model.isHintShowing ? 1 : 0)
            .accessibilityHidden(!model.isHintShowing)
            .motion(DS.Motion.quick, value: model.isHintShowing)

            Spacer(minLength: DS.Space.xs)

            controls
                .padding(.bottom, compact ? DS.Space.xs : DS.Space.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: HintTimer(activity: model.activityID, enabled: model.showsKeyboard && !model.isPaused)) {
            guard model.showsKeyboard, !model.isPaused else { return }
            try? await Task.sleep(for: .seconds(model.hintDelay))
            guard !Task.isCancelled else { return }
            model.revealHintIfDue()
        }
        .confirmationDialog("End today's session?", isPresented: $confirmingEnd) {
            Button("End Session") { model.endEarly() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text("Finished passages are saved. The passage you're on is not.")
        }
    }

    private var cue: String {
        if model.isPaused { return "Paused. Press Esc or Resume to carry on." }
        if model.isHintShowing, let key = model.nextKey {
            let name = key == " " ? "Space" : String(key).uppercased()
            return "Next key: \(name). Feel for it, then press."
        }
        if model.engine.phase == .idle { return "Eyes on the screen. Rest your fingers on the bumps of F and J." }
        return model.segment.detail
    }

    private var controls: some View {
        HStack(spacing: DS.Space.xxs) {
            Button(action: model.togglePause) {
                Label(model.isPaused ? "Resume" : "Pause", systemImage: model.isPaused ? "play" : "pause")
            }
            .buttonStyle(.quiet)
            .help("Esc")
            Button(action: model.restartPassage) { Label("Restart Passage", systemImage: "arrow.counterclockwise") }
                .buttonStyle(.quiet)
                .help("Tab")
            Button { confirmingEnd = true } label: { Label("End Session", systemImage: "xmark") }
                .buttonStyle(.quiet)
            Spacer(minLength: DS.Space.m)
            Button { model.showsKeyboard.toggle() } label: {
                Label(model.showsKeyboard ? "Turn Hints Off" : "Turn Hints On", systemImage: "lightbulb")
            }
            .buttonStyle(.quiet)
            .help("⌘K")
        }
        .frame(maxWidth: typingWidth + 80)
        .padding(.horizontal, DS.Layout.pagePadding - 10)
    }
}

/// The three parts of the session, and how far through it you are.
private struct SegmentStrip: View {
    let model: DailyFlowModel

    var body: some View {
        VStack(spacing: DS.Space.xs) {
            HStack {
                ForEach(DailyFlowSegment.allCases) { segment in
                    Text(segment.title)
                        .font(segment == model.segment ? DS.Typography.bodyEmphasis : DS.Typography.body)
                        .foregroundStyle(segment == model.segment ? .primary : .secondary)
                    if segment != DailyFlowSegment.allCases.last { Spacer() }
                }
            }
            ThinProgressBar(fraction: model.fraction)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.segment.title). \(Int((model.fraction * 100).rounded())) percent of the session done.")
    }
}

// MARK: - Complete

private struct DailyFlowComplete: View {
    let model: DailyFlowModel
    let session: DailyFlowHistory.Session

    var body: some View {
        let previous = model.history.session(before: session.id)

        VStack(spacing: DS.Space.l) {
            VStack(spacing: DS.Space.xxs) {
                Text("Nice work today")
                    .font(DS.Typography.pageTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("\(session.totals.passages) \(session.totals.passages == 1 ? "passage" : "passages") finished")
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
            }

            MetricRow(metrics: [
                Metric(value: flowDuration(session.totals.activeSeconds), label: "Practice"),
                Metric(value: flowPercent(session.totals.accuracy), label: "Accuracy"),
                Metric(value: flowPercent(session.totals.withoutHints), label: "Without Hints",
                       help: "Keystrokes made without Keyflow showing the next key. It can't see whether you looked down."),
            ])

            if let previous {
                Text("Last time: \(flowPercent(previous.totals.accuracy)) accuracy · \(flowPercent(previous.totals.withoutHints)) without hints")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("Your first Daily Flow. Next time you'll see how it compares.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = model.saveError {
                Text("Some of this session could not be saved. (\(error))")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: DS.Space.s) {
                Button("One More Session") { model.start() }
                    .buttonStyle(.quietGlass)
                Button("Done") { model.done() }
                    .buttonStyle(.keyflowPrimary)
                    .help("Done (Return)")
            }
        }
        .padding(.horizontal, DS.Layout.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Helpers

func flowPercent(_ value: Double?) -> String {
    value.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
}

func flowDuration(_ seconds: TimeInterval) -> String {
    let whole = Int(seconds.rounded())
    return whole < 60 ? "\(whole)s" : String(format: "%d:%02d", whole / 60, whole % 60)
}

/// Progress ▸ Daily Flow: this week beside last week.
struct DailyFlowProgressView: View {
    let history: DailyFlowHistory

    var body: some View {
        if history.sessions.isEmpty {
            EmptyNote("No Daily Flow sessions yet. Start one under Learn → Daily Flow.")
        } else {
            let now = Date.now
            Grid(alignment: .leading, horizontalSpacing: DS.Space.l, verticalSpacing: DS.Space.xs) {
                GridRow {
                    Text("")
                    ForEach(["Days", "Practice", "Accuracy", "Without hints"], id: \.self) {
                        Text($0).font(DS.Typography.caption).foregroundStyle(.secondary)
                    }
                }
                row("This week", history.week(of: now))
                row("Last week", history.previousWeek(from: now))
            }
        }
    }

    private func row(_ title: String, _ week: DailyFlowHistory.Week) -> some View {
        GridRow {
            Text(title)
            Text("\(week.days)")
            Text(week.totals.passages == 0 ? "–" : flowDuration(week.totals.activeSeconds))
            Text(flowPercent(week.totals.accuracy))
            Text(flowPercent(week.totals.withoutHints))
        }
        .font(DS.Typography.body)
        .accessibilityElement(children: .combine)
    }
}
