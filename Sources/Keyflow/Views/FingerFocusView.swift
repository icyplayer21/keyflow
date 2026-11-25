import KeyflowCore
import SwiftUI

/// Finger Focus: short, accuracy-first sets for one ring finger or pinky.
struct FingerFocusView: View {
    @Bindable var model: FingerFocusModel
    @State private var keyboard = KeyboardMonitor()
    /// Results wait for the passage's sweep to finish.
    @State private var showsResults = false
    @Environment(\.typingWidth) private var typingWidth

    var body: some View {
        GeometryReader { geometry in
            content(compact: geometry.size.height < 660)
        }
        .background(.background)
        .holdingResultsForSweep(model.phase == .finished, shown: $showsResults)
        .onAppear { keyboard.start { model.handle($0) } }
        .onDisappear { keyboard.stop() }
    }

    private func content(compact: Bool) -> some View {
        let running = model.phase == .running

        return VStack(spacing: 0) {
            VStack(spacing: DS.Space.xs) {
                OptionBar(options: targetOptions,
                          selection: Binding(get: { model.target }, set: { model.select($0) })) { $0.title }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Finger")
                LevelStepper(model: model)
                SetSettings(model: model)
            }
            .padding(.top, compact ? DS.Space.xs : DS.Space.m)
            .padding(.horizontal, DS.Layout.pagePadding)
            .opacity(running ? 0.35 : 1)
            .motion(DS.Motion.standard, value: running)

            Spacer(minLength: compact ? DS.Space.xs : DS.Space.m)

            VStack(alignment: .leading, spacing: compact ? DS.Space.s : DS.Space.m) {
                FingerFocusHeader(model: model, compact: compact)
                if showsResults, model.phase == .finished, let check = model.checkSummary {
                    CheckCompleteView(model: model, summary: check)
                        .transition(.opacity)
                } else if showsResults, model.phase == .finished, let summary = model.summary {
                    FingerRoundCompleteView(model: model, summary: summary)
                        .transition(.opacity)
                } else {
                    VStack(alignment: .leading, spacing: DS.Space.m) {
                        TypingSurfaceView(target: model.engine.target, typed: model.engine.typed,
                                          visibleLines: 2, isIdle: model.phase == .idle)
                            .probedPassage()
                        FingerRoundProgress(model: model)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: typingWidth, alignment: .leading)
            .padding(.horizontal, DS.Layout.pagePadding)

            Spacer(minLength: compact ? DS.Space.xs : DS.Space.m)

            // After a round the key report needs the room; the keyboard returns with the next round.
            if model.showsKeyboard, !showsResults {
                VStack(spacing: compact ? DS.Space.xs : DS.Space.m) {
                    TrainingKeyboardView(exerciseKeys: model.exercise.keys, nextKey: model.nextKey,
                                         miss: model.lastMiss, keySize: compact ? 30 : 36,
                                         targetKeys: Set(model.target.keys))
                    // In short windows the next-key label already names the recommended finger.
                    if !compact { FingerGuideView(nextKey: model.nextKey) }
                }
                .transition(.opacity)
            }

            Spacer(minLength: compact ? DS.Space.xs : DS.Space.s)

            controls
                .padding(.bottom, compact ? DS.Space.xs : DS.Space.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .motion(DS.Motion.standard, value: model.phase)
        .motion(DS.Motion.standard, value: model.showsKeyboard)
    }

    /// The ring-finger and pinky targets, plus a middle or index finger
    /// when one was opened from Progress.
    private var targetOptions: [FingerFocusTarget] {
        FingerFocusTarget.primary.contains(model.target) ? FingerFocusTarget.primary : FingerFocusTarget.primary + [model.target]
    }

    private var controls: some View {
        HStack(spacing: DS.Space.xxs) {
            RestartButton(action: model.restart)
            if model.isCheck {
                Button { model.endCheck() } label: { Label("Back to Training", systemImage: "arrow.uturn.backward") }
                    .buttonStyle(.quiet)
            } else if model.phase != .finished {
                Button { model.nextExercise() } label: { Label("Next Exercise", systemImage: "arrow.right") }
                    .buttonStyle(.quiet)
                    .help("A new exercise for this round (⌘→)")
            }
            if !model.isCheck {
                Button { model.startNewSet() } label: { Label("New Set", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(.quiet)
                    .help("Start the set again from round 1")
                Button { model.startCheck() } label: { Label(model.checkTitle, systemImage: "gauge.with.needle") }
                    .buttonStyle(.quiet)
                    .help("A short passage scored on this finger's keys and compared with your previous check")
            }

            Spacer(minLength: DS.Space.m)
            ViewThatFits(in: .horizontal) {
                ShortcutHints(finished: model.phase == .finished)
                Color.clear.frame(width: 1, height: 1)
            }
            Spacer(minLength: DS.Space.m)

            Button { model.showsKeyboard.toggle() } label: {
                Label(model.showsKeyboard ? "Hide Keyboard" : "Show Keyboard", systemImage: "keyboard")
            }
            .buttonStyle(.quiet)
            .help("⌘K")
        }
        .frame(maxWidth: typingWidth + 80)
        .padding(.horizontal, DS.Layout.pagePadding - 10)
    }
}

// MARK: - Level and set controls

/// The four levels. None is locked; the recommended one is marked.
private struct LevelStepper: View {
    let model: FingerFocusModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FingerFocusLevel.allCases) { level in
                if level.rawValue > 1 {
                    Rectangle().fill(DS.Palette.hairline).frame(width: 14, height: 1)
                }
                LevelButton(level: level,
                            progress: model.tracker.progress(model.target, level),
                            isRecommended: level == model.recommendedLevel,
                            isSelected: level == model.level) {
                    model.select(level)
                }
            }
        }
    }
}

private struct LevelButton: View {
    let level: FingerFocusLevel
    let progress: FingerFocusTracker.LevelProgress
    let isRecommended: Bool
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    private var state: LessonState {
        if progress.isSteady { return .mastered }
        return progress.rounds > 0 ? .inProgress(qualifying: progress.qualifyingRounds) : .notStarted
    }

    private var label: String {
        if progress.isSteady { return "Steady" }
        if isRecommended { return progress.rounds > 0 ? "Recommended · \(state.label)" : "Recommended" }
        return state.label
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: state.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(state.tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(level.rawValue). \(level.title)").font(DS.Typography.bodyEmphasis)
                    Text(label)
                        .font(DS.Typography.caption)
                        .foregroundStyle(isRecommended && !progress.isSteady ? Color.accentColor : Color.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control)
                    .fill(isSelected ? DS.Palette.selected : (hovering ? DS.Palette.fill : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(DS.Motion.quick, value: hovering)
        .motion(DS.Motion.quick, value: isSelected)
        .help(level.instructions)
        .accessibilityLabel("Level \(level.rawValue), \(level.title), \(label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Rounds per set and the optional rest between rounds.
private struct SetSettings: View {
    @Bindable var model: FingerFocusModel

    var body: some View {
        HStack(spacing: DS.Space.l) {
            HStack(spacing: DS.Space.xs) {
                Eyebrow("Rounds per set")
                OptionBar(options: FingerFocusModel.setSizes, selection: $model.roundsPerSet,
                          font: DS.Typography.caption) { "\($0)" }
            }
            .help("Short sets: a few brief rounds instead of one long drill")
            HStack(spacing: DS.Space.xs) {
                Eyebrow("Rest")
                OptionBar(options: FingerFocusModel.restOptions, selection: $model.restSeconds,
                          font: DS.Typography.caption) { $0 == 0 ? "Off" : "\($0)s" }
            }
            .help("An optional pause between rounds. Press Return to end it early.")
        }
    }
}

// MARK: - Exercise

private struct FingerFocusHeader: View {
    let model: FingerFocusModel
    var compact = false

    var body: some View {
        let exercise = model.exercise

        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Eyebrow(model.isCheck
                    ? "\(model.target.title) · Finger check"
                    : "\(model.target.title) · Level \(model.level.rawValue) · Round \(model.roundInSet) of \(model.roundsPerSet)")
            Text(model.isCheck ? (isBaseline ? "Baseline Check" : "Retest") : model.level.title)
                .font(DS.Typography.pageTitle)
                .help(instructions)
            if !compact {
                Text(instructions)
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: DS.Space.m) {
                HStack(spacing: 6) {
                    Text("Target keys")
                    Text(model.target.keys.map { String($0).uppercased() }.joined(separator: " "))
                        .font(DS.Typography.metric(11))
                }
                .help("The keys standard touch typing assigns to the \(fingerNames). A recommendation: Keyflow cannot see which finger you use.")
                if exercise.complexity > 0, !model.isCheck {
                    Label("Longer transitions", systemImage: "arrow.up.right")
                        .help("Added after steady rounds at this level.")
                }
                if !exercise.focus.isEmpty {
                    Label("Extra practice: \(exercise.focus.map { focusLabel($0.item) }.joined(separator: ", "))",
                          systemImage: "repeat")
                        .help("Keys and transitions you recently missed get a few extra repetitions.")
                }
            }
            .font(DS.Typography.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
    }

    /// The check on screen is the first for this finger.
    private var isBaseline: Bool {
        if let summary = model.checkSummary { return summary.comparison == nil }
        return model.checks.isEmpty
    }

    private var instructions: String {
        model.isCheck
            ? "Type at a comfortable pace. Only \(keys) are scored, and the result is compared with your previous check. Checks are not counted as training."
            : model.level.instructions
    }

    private var keys: String {
        model.target.keys.map { String($0).uppercased() }.joined(separator: " ")
    }

    private var fingerNames: String {
        model.target.fingers.map(\.title).joined(separator: " and ")
    }
}

func focusLabel(_ item: String) -> String {
    item.count == 1 ? item.uppercased() : item.uppercased().map(String.init).joined(separator: "→")
}

/// Accuracy, where you are in the round and set, and the next key.
private struct FingerRoundProgress: View {
    let model: FingerFocusModel

    var body: some View {
        let metrics = model.metrics
        let typed = model.engine.position
        let total = max(1, model.engine.target.count)

        HStack(alignment: .center, spacing: DS.Space.xl) {
            Metric(value: metrics.totalKeystrokes > 0 ? metrics.accuracy.percentText : "–", label: "Accuracy",
                   tint: metrics.totalKeystrokes > 0 ? .accentColor : .secondary)

            VStack(alignment: .leading, spacing: 6) {
                ThinProgressBar(fraction: Double(typed) / Double(total))
                    .frame(width: 160)
                Text("\(typed) of \(total) characters")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Round progress, \(typed) of \(total) characters")

            if !model.isCheck {
                SetDots(completed: model.setResults.count, total: model.roundsPerSet)
            }

            NextKeyView(key: model.nextKey)
        }
        .monospacedDigit()
    }
}

/// One dot per round in the set.
private struct SetDots: View {
    let completed: Int
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                ForEach(0..<total, id: \.self) { index in
                    Circle()
                        .fill(index < completed ? Color.accentColor.opacity(0.8) : DS.Palette.hairline)
                        .frame(width: 8, height: 8)
                }
            }
            Text("\(min(completed, total)) of \(total) rounds")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .motion(DS.Motion.standard, value: completed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Set progress, \(min(completed, total)) of \(total) rounds")
    }
}

/// The next key and the finger recommended for it.
private struct NextKeyView: View {
    let key: Character?

    var body: some View {
        let finger = key.flatMap(FingerMap.finger(for:))

        HStack(spacing: DS.Space.xs) {
            Text(key.map { TrainingKeyboardView.name(of: $0) } ?? "–")
                .font(DS.Typography.metric(key == " " ? 12 : 18, weight: .semibold))
                .foregroundStyle(key == nil ? Color.secondary : Color.accentColor)
                .frame(minWidth: 34, minHeight: 34)
                .padding(.horizontal, key == " " ? 6 : 0)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.key).strokeBorder(Color.accentColor.opacity(key == nil ? 0.2 : 0.6)))
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow("Next key")
                Text(finger.map { $0 == .thumb ? "Either thumb" : $0.title.prefix(1).uppercased() + $0.title.dropFirst() } ?? " ")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .help("Recommended finger for standard touch typing")
            }
        }
        .contentTransition(.opacity)
        .motion(DS.Motion.quick, value: key)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Round complete

private struct FingerRoundCompleteView: View {
    let model: FingerFocusModel
    let summary: FingerFocusModel.RoundSummary

    var body: some View {
        let result = summary.result

        VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack(alignment: .top, spacing: DS.Space.xl) {
                Metric(value: (summary.completesSet ? model.setAccuracy ?? result.accuracy : result.accuracy).percentText,
                       label: summary.completesSet ? "Set accuracy" : "Accuracy", size: 56, weight: .semibold,
                       tint: result.isQualifying ? .accentColor : .primary)

                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Label {
                        Text(message.title).font(DS.Typography.sectionTitle)
                    } icon: {
                        Image(systemName: message.symbol).foregroundStyle(message.color)
                    }
                    Text(message.detail)
                        .font(DS.Typography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let rest = model.restRemaining {
                        HStack(spacing: DS.Space.xs) {
                            Image(systemName: "pause.circle").foregroundStyle(.secondary)
                            Text("Rest \(rest)s. Let your hand relax; the next round starts by itself.")
                                .font(DS.Typography.body)
                                .contentTransition(.numericText(countsDown: true))
                                .motion(DS.Motion.quick, value: rest)
                        }
                    }
                }
                .padding(.top, DS.Space.xs)
            }

            HStack(spacing: DS.Space.xs) {
                Button(action: model.performPrimaryAction) {
                    Label(summary.completesSet ? "New Set" : (model.restRemaining != nil ? "Skip Rest" : "Next Round"),
                          systemImage: "arrow.right")
                }
                .buttonStyle(.keyflowPrimary)
                .help("Return")
                Button(action: model.restart) {
                    Label("Repeat Round", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.quietGlass)
                .help("Tab")
                if summary.completesSet {
                    Button(action: model.startCheck) {
                        Label(model.checkTitle, systemImage: "gauge.with.needle")
                    }
                    .buttonStyle(.quiet)
                    .help("A short, new passage scored on this finger's keys, compared with your previous check")
                }
            }

            KeyReport(model: model, result: result)

            if let error = model.saveError {
                Label("This round could not be saved: \(error)", systemImage: "exclamationmark.triangle")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.error)
            }
        }
        .monospacedDigit()
    }

    private var message: (title: String, detail: String, symbol: String, color: Color) {
        let progress = model.levelProgress
        if summary.completesSet {
            return ("Set complete",
                    "\(model.setResults.count) rounds of \(model.level.title). Short sets with breaks build control better than long ones.",
                    "checkmark.circle", DS.Palette.success)
        }
        if summary.result.isQualifying {
            let detail = progress.isSteady
                ? "This level is steady: \(MasteryTracker.requiredRounds) or more rounds at 95%+."
                : "\(min(progress.qualifyingRounds, MasteryTracker.requiredRounds)) of \(MasteryTracker.requiredRounds) rounds at 95%+ at this level."
            return ("Clean round", detail, "checkmark.circle", DS.Palette.success)
        }
        return ("Accuracy first", "Slow down until the reach feels easy. Speed comes later and is not measured here.",
                "arrow.counterclockwise.circle", .secondary)
    }
}

/// Keeps two things apart: where each key should be typed (a recommendation)
/// and how the key has actually gone (what Keyflow measured).
private struct KeyReport: View {
    let model: FingerFocusModel
    let result: RoundResult

    var body: some View {
        let stats = model.keyStats
        let recommendations = model.recommendations

        VStack(alignment: .leading, spacing: DS.Space.s) {
            Divider()
            Grid(alignment: .topLeading, horizontalSpacing: DS.Space.xl, verticalSpacing: DS.Space.xs) {
                GridRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow("Recommended placement")
                        Text(placement)
                            .font(DS.Typography.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: 300, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow("Observed key accuracy · last \(FingerFocusTracker.recentRounds) rounds")
                        HStack(spacing: DS.Space.m) {
                            ForEach(stats, id: \.key) { stat in
                                HStack(spacing: 4) {
                                    Text(String(stat.key).uppercased()).font(DS.Typography.code)
                                    Text(stat.accuracy?.percentText ?? "–")
                                        .font(DS.Typography.metric(11))
                                        .foregroundStyle(tint(stat))
                                }
                                .help("\(stat.count.errors) errors in \(stat.count.attempts) presses of this key")
                            }
                        }
                        Text("Which key was pressed, not which finger pressed it.")
                            .font(DS.Typography.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            ForEach(recommendations, id: \.key) { recommendation in
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "lightbulb").foregroundStyle(.secondary)
                    Text("\(String(recommendation.key).uppercased()) missed \(recommendation.count.errors) of \(recommendation.count.attempts) times recently. Extra \(String(recommendation.key).uppercased()) practice is added to your exercises.")
                        .font(DS.Typography.body)
                        .fixedSize(horizontal: false, vertical: true)
                    if recommendation.level != model.level {
                        Button("Practise at Level \(recommendation.level.rawValue)") { model.select(recommendation.level) }
                            .buttonStyle(.quiet)
                    }
                }
            }
        }
    }

    private var placement: String {
        model.target.fingers
            .map { finger in
                let keys = FingerKeys.keys(for: finger).map { String($0).uppercased() }.joined(separator: " ")
                return "\(keys): \(finger.title)"
            }
            .joined(separator: "\n")
    }

    private func tint(_ stat: FingerKeyStat) -> Color {
        guard let accuracy = stat.accuracy else { return .secondary }
        return accuracy < 1 - FingerFocusTracker.problemRate ? DS.Palette.error : .secondary
    }
}


// MARK: - Finger check

private struct CheckCompleteView: View {
    let model: FingerFocusModel
    let summary: FingerFocusModel.CheckSummary

    var body: some View {
        let result = summary.event.result

        VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack(alignment: .top, spacing: DS.Space.xl) {
                Metric(value: result.accuracy.map(\.percentText) ?? "–",
                       label: "\(keys) accuracy", size: 56, weight: .semibold, tint: .accentColor)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(summary.comparison == nil ? "Baseline saved" : "Retest saved").font(DS.Typography.sectionTitle)
                    Text(summary.comparison == nil
                         ? "Train this finger, then take a retest. It uses different words in the same proportions, so the two can be compared."
                         : "Compared with your previous check. A change is only called when it is unlikely to be chance.")
                        .font(DS.Typography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: DS.Space.l) {
                        detail("Speed", FingerFormat.relativeSpeed(result.relativeLatency.count >= FingerAssessment.minimumTimingSamples
                                                                   ? result.relativeLatency.mean : nil,
                                                                   reference: "your other keys"))
                        detail("Mistakes", "\(result.target.errors) wrong \(result.target.errors == 1 ? "press" : "presses") · \(result.correctedErrors) corrected · \(result.uncorrectedErrors) left")
                    }
                    .padding(.top, DS.Space.xxs)
                }
                .padding(.top, DS.Space.xs)
            }

            if let comparison = summary.comparison {
                ComparisonView(comparison: comparison)
            }

            HStack(spacing: DS.Space.xs) {
                Button(action: model.endCheck) {
                    Label("Back to Training", systemImage: "arrow.right")
                }
                .buttonStyle(.keyflowPrimary)
                .help("Return")
            }

            if let error = model.saveError {
                Label("This check could not be saved: \(error)", systemImage: "exclamationmark.triangle")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.error)
            }
        }
        .monospacedDigit()
    }

    private var keys: String { model.target.keys.map { String($0).uppercased() }.joined(separator: " ") }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(label)
            Text(value).font(DS.Typography.body)
        }
    }
}

/// Baseline against retest, with a verdict for each measure.
struct ComparisonView: View {
    let comparison: FingerAssessmentComparison

    var body: some View {
        let before = comparison.baseline.result, after = comparison.retest.result

        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Grid(alignment: .leading, horizontalSpacing: DS.Space.l, verticalSpacing: DS.Space.xs) {
                GridRow {
                    Eyebrow("")
                    Eyebrow("Baseline")
                    Eyebrow("Retest")
                    Eyebrow("Change")
                }
                GridRow {
                    Text("Accuracy").font(DS.Typography.body)
                    Text(before.accuracy.map(\.percentText) ?? "–").font(DS.Typography.metric(13))
                    Text(after.accuracy.map(\.percentText) ?? "–").font(DS.Typography.metric(13))
                    VerdictLabel(verdict: comparison.accuracy)
                }
                GridRow {
                    Text("Time vs other keys").font(DS.Typography.body)
                        .help("Latency on this finger's keys compared with your other keys in the same check, for the same kinds of key change. Lower is faster.")
                    Text(FingerFormat.ratio(before.relativeLatency)).font(DS.Typography.metric(13))
                    Text(FingerFormat.ratio(after.relativeLatency)).font(DS.Typography.metric(13))
                    VerdictLabel(verdict: comparison.latency)
                }
            }
            Text("\(comparison.trainingRounds) Finger Focus \(comparison.trainingRounds == 1 ? "round" : "rounds") between the two checks, \(comparison.baseline.date.formatted(date: .abbreviated, time: .omitted)) and \(comparison.retest.date.formatted(date: .abbreviated, time: .omitted)).")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Improved / Declined / No clear change / Not enough data, with a symbol
/// so the colour is never the only signal.
struct VerdictLabel: View {
    let verdict: ChangeVerdict

    var body: some View {
        Label(verdict.title, systemImage: symbol)
            .font(DS.Typography.bodyEmphasis)
            .foregroundStyle(color)
    }

    private var symbol: String {
        switch verdict {
        case .improved: "arrow.up.right"
        case .declined: "arrow.down.right"
        case .noClearChange: "equal"
        case .insufficientData: "ellipsis"
        }
    }

    private var color: Color {
        switch verdict {
        case .improved: DS.Palette.success
        case .declined: DS.Palette.caution
        case .noClearChange, .insufficientData: .secondary
        }
    }
}

/// Wording for estimates, with no more precision than the data supports.
enum FingerFormat {
    /// "About your average", "About 15% slower than <reference>". Rounded to 5%.
    static func relativeSpeed(_ ratio: Double?, reference: String = "your average") -> String {
        guard let ratio else { return "Not enough timing data yet" }
        let percent = Int(((ratio - 1) * 100 / 5).rounded()) * 5
        if percent == 0 { return "About the same as \(reference)" }
        return percent > 0 ? "About \(percent)% slower than \(reference)" : "About \(-percent)% faster than \(reference)"
    }

    /// "+15%" (slower) or "−5%" (faster) than the reference, rounded to 5%;
    /// "–" without enough samples.
    static func ratio(_ sums: LatencySums) -> String {
        guard sums.count >= FingerAssessment.minimumTimingSamples, let mean = sums.mean else { return "–" }
        let percent = Int(((mean - 1) * 100 / 5).rounded()) * 5
        return percent == 0 ? "±0%" : (percent > 0 ? "+\(percent)%" : "−\(-percent)%")
    }
}
