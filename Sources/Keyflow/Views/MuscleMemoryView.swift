import KeyflowCore
import SwiftUI

/// Learn: structured, accuracy-first lessons that build keyboard familiarity.
struct MuscleMemoryView: View {
    @Bindable var model: MuscleMemoryModel
    @State private var keyboard = KeyboardMonitor()
    /// Results wait for the passage's sweep to finish.
    @State private var showsResults = false
    @Environment(\.typingWidth) private var typingWidth
    @State private var confirmingSkip = false

    var body: some View {
        // Short windows get smaller keys and fewer words so nothing is cut off.
        GeometryReader { geometry in
            content(compact: geometry.size.height < 700)
        }
        .background(.background)
        .holdingResultsForSweep(model.phase == .finished, shown: $showsResults)
        .onAppear { keyboard.start { model.handle($0) } }
        .onDisappear { keyboard.stop() }
        .confirmationDialog("Skip Stage \(model.stage.rawValue)?", isPresented: $confirmingSkip) {
            Button("Skip Stage") { model.skipStage() }
            Button("Keep Practising", role: .cancel) {}
        } message: {
            Text("The next stage opens, but this one will not be marked as mastered. You can come back to it at any time.")
        }
    }

    private func content(compact: Bool) -> some View {
        let running = model.phase == .running

        return VStack(spacing: 0) {
            VStack(spacing: DS.Space.s) {
                OptionBar(options: TrainingCategory.allCases,
                          selection: Binding(get: { model.category }, set: { model.select($0) })) { $0.title }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Lesson")
                StageStepper(model: model)
            }
            .padding(.top, compact ? DS.Space.s : DS.Space.l)
            .padding(.horizontal, DS.Layout.pagePadding)
            .opacity(running ? 0.35 : 1)
            .motion(DS.Motion.standard, value: running)

            Spacer(minLength: compact ? DS.Space.xs : DS.Space.m)

            VStack(alignment: .leading, spacing: compact ? DS.Space.s : DS.Space.m) {
                ExerciseHeader(model: model, compact: compact)
                if showsResults, model.phase == .finished, let summary = model.summary {
                    RoundCompleteView(model: model, summary: summary)
                        .transition(.opacity)
                } else {
                    VStack(alignment: .leading, spacing: DS.Space.m) {
                        TypingSurfaceView(target: model.engine.target, typed: model.engine.typed,
                                          visibleLines: 2, isIdle: model.phase == .idle)
                            .probedPassage()
                        RoundProgressView(model: model)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: typingWidth, alignment: .leading)
            .padding(.horizontal, DS.Layout.pagePadding)

            Spacer(minLength: compact ? DS.Space.xs : DS.Space.m)

            if model.showsKeyboard {
                VStack(spacing: compact ? DS.Space.xs : DS.Space.m) {
                    TrainingKeyboardView(exerciseKeys: model.exercise.keys, nextKey: model.nextKey,
                                         miss: model.lastMiss, keySize: compact ? 30 : 36)
                    FingerGuideView(nextKey: model.nextKey, compact: compact)
                }
                .transition(.opacity)
            } else if model.stage == .singleKeys {
                // Beginners keep the finger guidance even without the keyboard.
                FingerGuideView(nextKey: model.nextKey, compact: true)
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

    private var controls: some View {
        HStack(spacing: DS.Space.xxs) {
            RestartButton(action: model.restart)
            if model.phase != .finished {
                Button { model.nextExercise() } label: { Label("Next Exercise", systemImage: "arrow.right") }
                    .buttonStyle(.quiet)
                    .help("A new exercise for this stage (⌘→)")
            }
            Button { confirmingSkip = true } label: { Label("Skip Stage", systemImage: "forward.end") }
                .buttonStyle(.quiet)
                .disabled(!model.canSkipStage)
                .help(model.canSkipStage ? "Move on without mastering this stage" : "Only an open, unmastered stage can be skipped")

            Spacer(minLength: DS.Space.m)
            // Hints are a nicety; they give way when the window is narrow.
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

/// The four stages of the current lesson, connected left to right.
private struct StageStepper: View {
    let model: MuscleMemoryModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TrainingStage.allCases) { stage in
                if let previous = stage.previous {
                    Rectangle()
                        .fill(state(previous) == .mastered ? DS.Palette.success.opacity(0.6) : DS.Palette.hairline)
                        .frame(width: 20, height: 1)
                }
                StepButton(stage: stage, state: state(stage), isSelected: stage == model.stage) {
                    model.select(stage)
                }
            }
        }
    }

    private func state(_ stage: TrainingStage) -> LessonState {
        LessonState(status: model.status(of: stage), progress: model.tracker.progress(model.category, stage))
    }
}

private struct StepButton: View {
    let stage: TrainingStage
    let state: LessonState
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let locked = state == .locked

        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: state.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(state.tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(stage.title)
                        .font(DS.Typography.bodyEmphasis)
                        .foregroundStyle(locked ? Color.secondary : Color.primary)
                    Text(state.label)
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.control)
                    .fill(isSelected ? DS.Palette.selected : (hovering && !locked ? DS.Palette.fill : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.control))
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .onHover { hovering = $0 }
        .motion(DS.Motion.quick, value: hovering)
        .motion(DS.Motion.quick, value: isSelected)
        .help(locked ? "Master or skip Stage \(stage.rawValue - 1) first" : stage.instructions)
        .accessibilityLabel("Stage \(stage.rawValue), \(stage.title), \(state.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ExerciseHeader: View {
    let model: MuscleMemoryModel
    var compact = false

    var body: some View {
        let exercise = model.exercise

        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Eyebrow("\(model.category.title) · Stage \(model.stage.rawValue)")
            Text(model.stage.title).font(DS.Typography.pageTitle)
                .help(instructions)
            if !compact {
                Text(instructions)
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: DS.Space.m) {
                if exercise.isPracticePattern {
                    Label("Practice patterns: too few real words use only these keys", systemImage: "info.circle")
                } else if exercise.stage != .words {
                    HStack(spacing: 6) {
                        Text("Keys")
                        Text(keyList(exercise.keys)).font(DS.Typography.metric(11))
                    }
                }
                if !exercise.focus.isEmpty {
                    Label("Extra practice: \(exercise.focus.map { focusLabel($0.item) }.joined(separator: ", "))",
                          systemImage: "repeat")
                        .help("Keys and transitions you recently found hard get a few extra repetitions.")
                }
            }
            .font(DS.Typography.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
    }

    private var instructions: String {
        model.phase == .idle && model.stage == .singleKeys ? model.category.instructions : model.stage.instructions
    }

    private func keyList(_ keys: Set<Character>) -> String {
        keys.sorted { a, b in
            let pa = KeyboardLayout.position(of: a), pb = KeyboardLayout.position(of: b)
            return (pa?.row ?? 9, pa?.column ?? 99) < (pb?.row ?? 9, pb?.column ?? 99)
        }
        .map { String($0).uppercased() }
        .joined(separator: " ")
    }

    private func focusLabel(_ item: String) -> String {
        item.count == 1 ? item.uppercased() : item.uppercased().map(String.init).joined(separator: "→")
    }
}

/// Accuracy first, then how far through the round, then mastery.
private struct RoundProgressView: View {
    let model: MuscleMemoryModel

    var body: some View {
        let metrics = model.metrics
        let typed = model.engine.position
        let total = max(1, model.engine.target.count)

        HStack(alignment: .center, spacing: DS.Space.xl) {
            Metric(value: metrics.totalKeystrokes > 0 ? metrics.accuracy.percentText : "–", label: "Accuracy",
                   tint: metrics.totalKeystrokes > 0 ? .accentColor : .secondary)

            VStack(alignment: .leading, spacing: 6) {
                ThinProgressBar(fraction: Double(typed) / Double(total))
                    .frame(width: 180)
                Text("\(typed) of \(total) characters")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Round progress, \(typed) of \(total) characters")

            MasteryDots(progress: model.stageProgress)
        }
        .monospacedDigit()
        .stepsBackWhileTyping()
    }
}

/// Three dots for the three qualifying rounds a stage needs.
struct MasteryDots: View {
    let progress: StageProgress

    var body: some View {
        let filled = min(progress.qualifyingRounds, MasteryTracker.requiredRounds)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                ForEach(0..<MasteryTracker.requiredRounds, id: \.self) { index in
                    Circle()
                        .fill(index < filled ? DS.Palette.success : DS.Palette.hairline)
                        .frame(width: 8, height: 8)
                }
            }
            Text(progress.isMastered
                 ? "Stage mastered"
                 : "\(filled) of \(MasteryTracker.requiredRounds) rounds at \(Int(MasteryTracker.requiredAccuracy * 100))%+")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .motion(DS.Motion.standard, value: filled)
        .accessibilityElement(children: .combine)
    }
}

private struct RoundCompleteView: View {
    let model: MuscleMemoryModel
    let summary: MuscleMemoryModel.RoundSummary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var celebrate = false

    var body: some View {
        let result = summary.result

        VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack(alignment: .top, spacing: DS.Space.xl) {
                Metric(value: result.accuracy.percentText, label: "Accuracy", size: 56, weight: .semibold,
                       tint: result.isQualifying ? .accentColor : .primary)

                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Label {
                        Text(message.title).font(DS.Typography.sectionTitle)
                    } icon: {
                        Image(systemName: message.symbol)
                            .foregroundStyle(message.color)
                            .symbolEffect(.bounce, value: celebrate)
                    }
                    Text(message.detail)
                        .font(DS.Typography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    MasteryDots(progress: summary.progress)
                        .padding(.top, DS.Space.xxs)
                }
                .padding(.top, DS.Space.xs)
            }

            if !missed.isEmpty {
                HStack(spacing: 6) {
                    Text("Missed").foregroundStyle(.secondary)
                    Text(missed).font(DS.Typography.metric(12))
                }
                .font(DS.Typography.body)
            }

            HStack(spacing: DS.Space.xs) {
                Button(action: model.performPrimaryAction) {
                    Label(model.nextStageToContinue.map { "Continue to Stage \($0.rawValue)" } ?? "Next Exercise",
                          systemImage: "arrow.right")
                }
                .buttonStyle(.keyflowPrimary)
                .help("Return")
                Button(action: model.restart) {
                    Label("Repeat", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.quietGlass)
                .help("Tab")
            }

            if let error = model.saveError {
                Label("This round could not be saved: \(error)", systemImage: "exclamationmark.triangle")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.error)
            }
        }
        .monospacedDigit()
        .onAppear {
            if summary.justMastered, !reduceMotion { celebrate = true }
        }
    }

    private var message: (title: String, detail: String, symbol: String, color: Color) {
        if summary.justMastered {
            return ("Stage mastered", "Three rounds at 95% or better. This stage now counts as learned.",
                    "checkmark.seal.fill", DS.Palette.success)
        }
        if summary.result.isQualifying {
            return ("Round counts", "That round counts toward mastering this stage.", "checkmark.circle", DS.Palette.success)
        }
        return ("Aim for 95%", "Rounds count at 95% accuracy or better. Slow down a little: accuracy first, speed later.",
                "arrow.counterclockwise.circle", .secondary)
    }

    private var missed: String {
        summary.result.keys
            .filter { $0.value.errors > 0 }
            .sorted { ($0.value.errors, $1.key) > ($1.value.errors, $0.key) }
            .prefix(6)
            .map { "\($0.key.uppercased())×\($0.value.errors)" }
            .joined(separator: "  ")
    }
}
