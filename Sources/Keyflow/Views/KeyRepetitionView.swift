import AppKit
import KeyflowCore
import SwiftUI

/// Learn ▸ Key Repetition: one letter, pressed again and again.
/// Choose a key and a goal, press Start (or Return), press the key.
struct KeyRepetitionView: View {
    @Bindable var model: KeyRepetitionModel
    /// Back to Learn's lessons, from the completion screen.
    var backToLearn: () -> Void = {}
    @State private var keyboard = KeyboardMonitor()

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 640
            Group {
                switch model.stage {
                case .setup:
                    KeyRepetitionSetup(model: model, compact: compact)
                case .training:
                    KeyRepetitionTraining(model: model, area: geometry.size)
                case .complete(let event):
                    // The results sit under the blast and rise in as it clears.
                    ZStack {
                        KeyRepetitionComplete(model: model, event: event, backToLearn: backToLearn)
                        if model.showsBurst {
                            KeyRepetitionBurstView(letter: event.result.letter.uppercased(), area: geometry.size,
                                                   power: model.finalLevel,
                                                   seed: UInt64(truncatingIfNeeded: event.id.hashValue)) { model.finishBurst() }
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .motion(DS.Motion.standard, value: StageKind(model.stage, burst: model.showsBurst))
        .background(.background)
        .onAppear { keyboard.start { model.handle($0) } }
        // Leaving the screen or the app pauses a session; it is never thrown away.
        .onDisappear { keyboard.stop(); model.pause(); model.finishBurst() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            model.pause()
        }
    }

    private enum StageKind: Equatable {
        // The ending plays in place of training, with no crossfade between them.
        case setup, training, complete
        init(_ stage: KeyRepetitionModel.Stage, burst: Bool) {
            switch stage {
            case .setup: self = .setup
            case .training: self = .training
            case .complete: self = burst ? .training : .complete
            }
        }
    }
}

// MARK: - Setup

private struct KeyRepetitionSetup: View {
    @Bindable var model: KeyRepetitionModel
    let compact: Bool
    /// Custom shows the number field even when the goal matches a preset.
    @State private var customGoal = false

    private enum GoalChoice: Hashable { case preset(Int), custom }

    var body: some View {
        VStack(spacing: compact ? DS.Space.m : DS.Space.l) {
            VStack(spacing: DS.Space.xxs) {
                Text("Key Repetition")
                    .font(DS.Typography.pageTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("Press one letter again and again to make finding it familiar. Each press counts once; holding a key down does not count. Slow down and the letter shrinks, but your count stays.")
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 520)

            LetterPicker(selection: model.letter, keySize: compact ? 30 : 34) { model.select($0) }

            Text("Target key **\(model.displayLetter)** · \(model.fingerName) recommended")
                .font(DS.Typography.body)
                .accessibilityLabel("Target key \(model.displayLetter). Recommended finger: \(model.fingerName).")

            VStack(spacing: DS.Space.s) {
                HStack(spacing: DS.Space.s) {
                    Text("Repetitions").font(DS.Typography.body).foregroundStyle(.secondary)
                    OptionBar(options: KeyRepetitionCounter.presets.map(GoalChoice.preset) + [.custom],
                              selection: Binding(get: { goalChoice }, set: choose)) { choice in
                        if case .preset(let value) = choice { "\(value)" } else { "Custom" }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Repetitions")
                    if goalChoice == .custom {
                        CustomGoalField(model: model)
                    }
                }
                HStack(spacing: DS.Space.s) {
                    Text("Mode").font(DS.Typography.body).foregroundStyle(.secondary)
                    OptionBar(options: KeyRepetitionMode.allCases, selection: $model.mode) { $0.title }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Mode")
                }
                Text(model.mode == .continuous
                     ? "Press the key steadily, one deliberate press at a time."
                     : "After each press, bring your fingers back to the home row before the next one.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            if let stats = model.history.stats(for: model.letter) {
                Text("\(model.displayLetter) so far: \(stats.sessions) \(stats.sessions == 1 ? "session" : "sessions") · \(stats.repetitions) repetitions · \(percent(stats.accuracy)) accuracy")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            VStack(spacing: DS.Space.xs) {
                Button("Start") { model.start() }
                    .buttonStyle(.keyflowPrimary)
                    .help("Start (Return)")
                HStack(spacing: DS.Space.m) {
                    hint("a–z", "choose a key")
                    hint("return", "start")
                }
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, DS.Layout.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { customGoal = !KeyRepetitionCounter.presets.contains(model.goal) }
    }

    private var goalChoice: GoalChoice { customGoal ? .custom : .preset(model.goal) }

    private func choose(_ choice: GoalChoice) {
        switch choice {
        case .preset(let value):
            customGoal = false
            model.setGoal(value)
        case .custom:
            customGoal = true
        }
    }
}

/// A number from 5 to 500, typed or stepped.
private struct CustomGoalField: View {
    let model: KeyRepetitionModel
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: DS.Space.xxs) {
            TextField("Repetitions", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .accessibilityLabel("Custom repetitions, 5 to 500")
            Stepper("Custom repetitions", value: Binding(get: { model.goal }, set: { model.setGoal($0); text = "\(model.goal)" }),
                    in: KeyRepetitionCounter.goalRange, step: 5)
                .labelsHidden()
        }
        .help("5 to 500")
        .onAppear { text = "\(model.goal)"; focused = true }
    }

    /// Anything outside 5...500 is brought into range; anything not a number is put back.
    private func commit() {
        if let value = Int(text.trimmingCharacters(in: .whitespaces)) { model.setGoal(value) }
        text = "\(model.goal)"
    }
}

/// The 26 letters in their keyboard rows. The selected key is filled.
private struct LetterPicker: View {
    let selection: Character
    var keySize: CGFloat = 34
    let select: (Character) -> Void

    private static let rows: [(keys: String, indent: CGFloat)] = [("qwertyuiop", 0), ("asdfghjkl", 0.3), ("zxcvbnm", 0.8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Self.rows, id: \.keys) { row in
                HStack(spacing: 5) {
                    ForEach(Array(row.keys), id: \.self) { letter in
                        LetterKey(letter: letter, isSelected: letter == selection, size: keySize) { select(letter) }
                    }
                }
                .padding(.leading, row.indent * keySize)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Target key")
    }
}

private struct LetterKey: View {
    let letter: Character
    let isSelected: Bool
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(String(letter).uppercased())
                .font(.system(size: size * 0.42, weight: .medium, design: .rounded))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.key)
                        .fill(isSelected ? Color.accentColor : (hovering ? DS.Palette.hover : DS.Palette.fill))
                )
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.key).strokeBorder(isSelected ? Color.clear : DS.Palette.hairline))
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.key))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(DS.Motion.quick, value: isSelected)
        .accessibilityLabel("Letter \(String(letter).uppercased())")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Training

/// Just the letter, alone. It grows with every correct press until the goal.
private struct KeyRepetitionTraining: View {
    @Bindable var model: KeyRepetitionModel
    let area: CGSize
    @State private var confirming: EndAction?
    /// Return to Home: the reminder shows right after a correct press, then the prompt.
    @State private var showsHomeReminder = false
    @State private var isMissFlashing = false
    @State private var showsFinger = true
    @State private var controlsAwake = false
    @State private var hoverID = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.decorativeAnimations) private var decorative

    private enum EndAction: Identifiable { case restart, exit; var id: Self { self } }

    private var showsControls: Bool { controlsAwake || model.isPaused || confirming != nil }

    var body: some View {
        let counter = model.counter
        ZStack {
            // Redrawn over time because the letter drains between presses.
            // Under Reduce Motion it changes in a few calm steps instead.
            TimelineView(.animation(minimumInterval: isCalm ? 0.25 : nil, paused: model.isPaused)) { _ in
                GrowingLetter(letter: model.displayLetter,
                              progress: shownLevel(earned: Double(counter.correct) / Double(counter.goal)),
                              pressID: model.feedback?.id ?? 0,
                              outcome: model.feedback?.outcome,
                              isMissFlashing: isMissFlashing,
                              isPaused: model.isPaused,
                              area: area)
            }
                .accessibilityElement()
                .accessibilityLabel("Target key \(model.displayLetter)")
                .accessibilityValue("\(counter.correct) of \(counter.goal) repetitions, \(counter.incorrect) errors")

            VStack(spacing: DS.Space.xs) {
                Spacer(minLength: 0)
                GlassGroup {
                    VStack(spacing: DS.Space.xs) {
                        footnote
                        Text("\(counter.correct) / \(counter.goal)")
                            .font(DS.Typography.metric(13))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, DS.Space.s)
                            .padding(.vertical, 3)
                            .floatingPill()
                            .accessibilityHidden(true)
                        controls
                            .opacity(showsControls ? 1 : 0)
                            .motion(DS.Motion.standard, value: showsControls)
                    }
                }
            }
            .padding(.horizontal, DS.Layout.pagePadding)
            .padding(.bottom, DS.Space.s)
        }
        .frame(width: area.width, height: area.height)
        .clipped()
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active = phase {
                controlsAwake = true
                hoverID += 1
            }
        }
        .task(id: hoverID) {
            guard hoverID > 0 else { return }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            controlsAwake = false
        }
        .task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withMotion(DS.Motion.standard) { showsFinger = false }
        }
        .task(id: model.feedback?.id) { await react(to: model.feedback) }
        .confirmationDialog(confirming == .exit ? "End this session?" : "Start this session again?",
                            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            presenting: confirming) { action in
            Button(action == .exit ? "End Session" : "Restart", role: .destructive) {
                action == .exit ? model.exit() : model.restart()
            }
            Button("Keep Going", role: .cancel) {}
        } message: { _ in
            Text("The \(model.counter.correct) repetitions so far will not be saved. Only finished sessions are kept.")
        }
    }

    private var isCalm: Bool { reduceMotion || !decorative }

    private func shownLevel(earned: Double) -> Double {
        let level = model.letterLevel()
        guard isCalm, level < earned else { return level }
        return (level * 10).rounded() / 10
    }

    /// One quiet line, only when there is something to say.
    @ViewBuilder private var footnote: some View {
        Group {
            if model.isPaused {
                Text("Paused. Press Esc to carry on.")
            } else if model.mode == .returnToHome, showsHomeReminder {
                Label("Return to home position.", systemImage: "hand.raised")
            } else if model.mode == .returnToHome, model.counter.attempts > 0 {
                Text("Press \(model.displayLetter) again.")
            } else if showsFinger {
                Text(model.counter.attempts == 0
                     ? "\(model.fingerName) · recommended finger · Esc pauses"
                     : "\(model.fingerName) · recommended finger")
            }
        }
        .font(DS.Typography.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, 3)
        .floatingPill()
    }

    private var controls: some View {
        HStack(spacing: DS.Space.m) {
            Button { model.togglePause() } label: {
                Label(model.isPaused ? "Resume" : "Pause", systemImage: model.isPaused ? "play" : "pause")
            }
            .buttonStyle(.quiet)
            .help(model.isPaused ? "Resume (Esc)" : "Pause (Esc)")
            Button { ask(.restart) } label: { Label("Restart", systemImage: "arrow.clockwise") }
                .buttonStyle(.quiet)
                .help("Restart (Tab)")
            Button { ask(.exit) } label: { Label("Exit", systemImage: "xmark") }
                .buttonStyle(.quiet)
                .help("Back to choosing a key")
        }
        .padding(.horizontal, DS.Space.xs)
        .floatingPill()
    }

    private func ask(_ action: EndAction) {
        if model.hasProgress { confirming = action } else if action == .exit { model.exit() } else { model.restart() }
    }

    /// Brief feedback only. Typing is never held up: the next press counts at once.
    private func react(to feedback: KeyRepetitionModel.Feedback?) async {
        guard let feedback else { isMissFlashing = false; showsHomeReminder = false; return }
        controlsAwake = false
        isMissFlashing = feedback.outcome == .incorrect
        showsHomeReminder = model.mode == .returnToHome && feedback.outcome == .correct
        if feedback.outcome == .incorrect, let typed = feedback.typed {
            AccessibilityNotification.Announcement("That was \(String(typed).uppercased()). Press \(model.displayLetter).").post()
        }
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled else { return }
        isMissFlashing = false
        try? await Task.sleep(for: .milliseconds(650))
        guard !Task.isCancelled else { return }
        showsHomeReminder = false
    }
}

/// The letter at its current size and color, with a punch on each correct
/// press, a shake on a mistake, and a glow and tremble near the goal.
private struct GrowingLetter: View {
    let letter: String
    let progress: Double
    let pressID: Int
    let outcome: KeyRepetitionCounter.Outcome?
    let isMissFlashing: Bool
    let isPaused: Bool
    let area: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.decorativeAnimations) private var decorative
    @Environment(\.colorScheme) private var colorScheme

    private struct Bump {
        var scale = 1.0
        var shake = 0.0
    }

    private var isAnimated: Bool { !reduceMotion && decorative }

    var body: some View {
        let metrics = KeyRepetitionGrowth.Metrics.of(letter)
        // Drawn once at full size and scaled down, so growth stays smooth and sharp.
        let full = KeyRepetitionGrowth.endFontSize(area: area, metrics: metrics)
        let current = KeyRepetitionGrowth.fontSize(progress: progress, area: area, metrics: metrics)
        let dark = colorScheme == .dark
        let intensity = KeyRepetitionGrowth.intensity(progress)
        let peak = isAnimated && outcome == .correct ? 1 + KeyRepetitionGrowth.punch(progress) : 1
        let shake = isAnimated && outcome == .incorrect ? 12.0 : 0
        let trembles = isAnimated && intensity > 0 && !isPaused

        ZStack {
            // An overlay, so the glow never changes the screen's layout.
            Color.clear.overlay {
                Circle()
                    .fill(RadialGradient(colors: [KeyRepetitionGrowth.bottomColor(1, dark: dark).color.opacity(0.32 * intensity), .clear],
                                         center: .center, startRadius: 0, endRadius: min(area.width, area.height) * 0.62))
                    .frame(width: min(area.width, area.height) * 1.24, height: min(area.width, area.height) * 1.24)
            }
            .allowsHitTesting(false)

            Color.clear.overlay {
                ZStack {
                    Text(letter)
                        .foregroundStyle(LinearGradient(colors: [KeyRepetitionGrowth.topColor(progress, dark: dark).color,
                                                                 KeyRepetitionGrowth.bottomColor(progress, dark: dark).color],
                                                        startPoint: .top, endPoint: .bottom))
                    Text(letter)
                        .foregroundStyle(DS.Palette.error)
                        .opacity(isMissFlashing ? 1 : 0)
                }
                .font(.system(size: full, weight: .semibold, design: .rounded))
                .fixedSize()
                .scaleEffect(current / full)
                .motion(.spring(duration: 0.18, bounce: 0.2), value: pressID)
            }
            .keyframeAnimator(initialValue: Bump(), trigger: pressID) { view, bump in
                view.scaleEffect(bump.scale).offset(x: bump.shake)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(peak, duration: 0.04)
                    SpringKeyframe(1, duration: 0.13)
                }
                KeyframeTrack(\.shake) {
                    LinearKeyframe(-shake, duration: 0.04)
                    LinearKeyframe(shake, duration: 0.05)
                    LinearKeyframe(-shake * 0.6, duration: 0.05)
                    LinearKeyframe(shake * 0.3, duration: 0.04)
                    LinearKeyframe(0, duration: 0.04)
                }
            }
            .modifier(Tremble(amount: trembles ? KeyRepetitionGrowth.maximumTremble * intensity : 0))
        }
        .opacity(isPaused ? 0.4 : 1)
        .motion(DS.Motion.standard, value: isPaused)
        .motion(DS.Motion.quick, value: isMissFlashing)
    }
}

/// A small, fast, irregular shake.
private struct Tremble: ViewModifier {
    let amount: CGFloat

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: amount == 0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            content.offset(x: amount == 0 ? 0 : amount * sin(t * 71) * cos(t * 23),
                           y: amount == 0 ? 0 : amount * sin(t * 59 + 1))
        }
    }
}

// MARK: - Completion

/// The payoff: the letter, the title, each number, then the buttons, rising
/// in one after another while the last shards fade.
private struct KeyRepetitionComplete: View {
    private static let lastStep = 7
    private static let firstDelay = 0.62
    private static let stepGap = 0.06

    let model: KeyRepetitionModel
    let event: KeyRepetitionEvent
    let backToLearn: () -> Void
    @State private var step: Int
    @State private var shownCorrect: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.decorativeAnimations) private var decorative
    @Environment(\.colorScheme) private var colorScheme

    init(model: KeyRepetitionModel, event: KeyRepetitionEvent, backToLearn: @escaping () -> Void) {
        self.model = model
        self.event = event
        self.backToLearn = backToLearn
        _step = State(initialValue: model.showsBurst ? 0 : Self.lastStep)
        _shownCorrect = State(initialValue: model.showsBurst ? 0 : event.result.correct)
    }

    private var isAnimated: Bool { !reduceMotion && decorative }

    var body: some View {
        let result = event.result
        let dark = colorScheme == .dark
        VStack(spacing: DS.Space.m) {
            Text(result.letter.uppercased())
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [KeyRepetitionGrowth.topColor(1, dark: dark).color,
                                                         KeyRepetitionGrowth.bottomColor(1, dark: dark).color],
                                                startPoint: .top, endPoint: .bottom))
                .accessibilityLabel("Key \(result.letter.uppercased())")
                .scaleEffect(step >= 1 || !isAnimated ? 1 : 0.5)
                .opacity(step >= 1 ? 1 : 0)
                .motion(.spring(duration: 0.34, bounce: 0.35), value: step >= 1)

            VStack(spacing: DS.Space.xxs) {
                Text("Session Complete")
                    .font(.system(size: 24, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(result.mode.title)
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
            }
            .rising(step >= 2)

            HStack(alignment: .top, spacing: 0) {
                number(Metric(value: "\(shownCorrect)", label: "Correct", size: 30), index: 0)
                number(Metric(value: "\(result.incorrect)", label: "Incorrect", size: 30,
                              tint: result.incorrect > 0 ? DS.Palette.error : .primary), index: 1)
                number(Metric(value: percent(result.accuracy), label: "Accuracy", size: 30,
                              help: "Correct presses out of every counted press"), index: 2)
                number(Metric(value: time(result.duration), label: "Time", size: 30,
                              help: "From your first press to the last, without pauses"), index: 3)
            }
            .monospacedDigit()
            .padding(.vertical, DS.Space.s)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(result.correct) correct, \(result.incorrect) incorrect, \(percent(result.accuracy)) accuracy, \(time(result.duration))")

            VStack(spacing: DS.Space.m) {
                if let stats = model.history.stats(for: model.counter.letter), stats.sessions > 1 {
                    Text("\(result.letter.uppercased()) over \(stats.sessions) sessions: \(stats.repetitions) repetitions, \(percent(stats.accuracy)) accuracy")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let error = model.saveError {
                    Label("This session could not be saved: \(error)", systemImage: "exclamationmark.triangle")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.caution)
                }
                HStack(spacing: DS.Space.s) {
                    Button("Choose Another Key") { model.exit() }
                        .buttonStyle(.quietGlass)
                    Button("Back to Learn") { model.exit(); backToLearn() }
                        .buttonStyle(.quietGlass)
                    Button("Repeat Again") { model.start() }
                        .buttonStyle(.keyflowPrimary)
                        .help("Repeat Again (Return)")
                }
            }
            .rising(step >= Self.lastStep)
        }
        .padding(.horizontal, DS.Layout.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .task(id: model.showsBurst) {
            guard model.showsBurst else { showEverything(); return }
            guard isAnimated else { return }
            try? await Task.sleep(for: .seconds(Self.firstDelay))
            for next in 1...Self.lastStep {
                guard !Task.isCancelled else { return }
                step = next
                try? await Task.sleep(for: .seconds(Self.stepGap))
            }
        }
        .task(id: step >= 3) {
            guard step >= 3, shownCorrect < result.correct else { return }
            let frames = 16
            for frame in 1...frames {
                try? await Task.sleep(for: .seconds(0.34 / Double(frames)))
                guard !Task.isCancelled else { return }
                shownCorrect = result.correct * frame / frames
            }
        }
    }

    private func showEverything() {
        step = Self.lastStep
        shownCorrect = event.result.correct
    }

    @ViewBuilder private func number(_ metric: Metric, index: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if index > 0 {
                Rectangle()
                    .fill(DS.Palette.hairline)
                    .frame(width: 1, height: 46)
                    .padding(.horizontal, DS.Space.l)
            }
            metric
        }
        .rising(step >= 3 + index)
    }

    private func time(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        return whole < 60 ? "\(whole)s" : String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

private extension View {
    /// Fades in while rising a few points. Under Reduce Motion it just appears.
    func rising(_ isVisible: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 12)
            .motion(.spring(duration: 0.3, bounce: 0.15), value: isVisible)
    }
}

// MARK: - Helpers

private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

@MainActor
private func hint(_ key: String, _ action: String) -> some View {
    HStack(spacing: 5) {
        KeyCap(key)
        Text(action)
    }
    .fixedSize()
}
