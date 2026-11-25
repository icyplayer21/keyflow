import KeyflowCore
import SwiftUI

/// Learn ▸ Typing Mechanics: Shift, Caps Lock and case transitions, with
/// character and technique checked separately.
struct TypingMechanicsView: View {
    @Bindable var model: TypingMechanicsModel
    @State private var keyboard = KeyboardMonitor()
    /// Results wait for the passage's sweep to finish.
    @State private var showsResults = false
    @Environment(\.typingWidth) private var typingWidth
    @Environment(Preferences.self) private var preferences: Preferences?

    /// Settings ▸ Typing ▸ Modifier guidance. Technique is checked either way.
    private var guidance: Bool { preferences?.modifierGuidance ?? true }
    private var recommends: Bool { preferences?.adaptiveRecommendations ?? true }

    var body: some View {
        GeometryReader { geometry in
            content(compact: geometry.size.height < 660)
        }
        .background(.background)
        .holdingResultsForSweep(model.phase == .finished, shown: $showsResults)
        .onAppear { keyboard.start({ model.handle($0) }, onModifier: { model.handleModifier($0) }) }
        .onDisappear { keyboard.stop() }
    }

    private func content(compact: Bool) -> some View {
        let running = model.phase == .running

        return VStack(spacing: 0) {
            VStack(spacing: DS.Space.xs) {
                ViewThatFits(in: .horizontal) {
                    OptionBar(options: MechanicsArea.allCases,
                              selection: Binding(get: { model.area }, set: { model.select($0) })) { $0.title }
                        .fixedSize()
                    OptionBar(options: MechanicsArea.allCases,
                              selection: Binding(get: { model.area }, set: { model.select($0) })) { $0.shortTitle }
                        .fixedSize()
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Training area")
                DrillStepper(model: model)
                if recommends, model.phase == .idle, let suggestion = model.suggestion {
                    SuggestionLine(recommendation: suggestion) { model.follow(suggestion) }
                }
            }
            .padding(.top, compact ? DS.Space.xs : DS.Space.m)
            .padding(.horizontal, DS.Layout.pagePadding)
            .opacity(running ? 0.35 : 1)
            .motion(DS.Motion.standard, value: running)

            Spacer(minLength: compact ? DS.Space.xs : DS.Space.m)

            VStack(alignment: .leading, spacing: compact ? DS.Space.s : DS.Space.m) {
                MechanicsHeader(model: model, compact: compact)
                if showsResults, model.phase == .finished, let summary = model.summary {
                    // Scrolls only when the results are taller than the window.
                    ViewThatFits(in: .vertical) {
                        MechanicsResultView(model: model, summary: summary, recommends: recommends)
                        ScrollView {
                            MechanicsResultView(model: model, summary: summary, recommends: recommends)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    .transition(.opacity)
                } else {
                    VStack(alignment: .leading, spacing: DS.Space.m) {
                        TypingSurfaceView(target: model.engine.target, typed: model.engine.typed,
                                          visibleLines: 2, isIdle: model.phase == .idle)
                            .probedPassage()
                        MechanicsLiveRow(model: model, guidance: guidance)
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: typingWidth, alignment: .leading)
            .padding(.horizontal, DS.Layout.pagePadding)

            Spacer(minLength: compact ? DS.Space.xs : DS.Space.m)

            if model.showsKeyboard, !showsResults {
                VStack(spacing: compact ? DS.Space.xs : DS.Space.m) {
                    TrainingKeyboardView(
                        exerciseKeys: Set(model.text.lowercased()).subtracting([" "]),
                        nextKey: model.nextKey, miss: model.lastMiss, keySize: compact ? (model.area == .numbersSymbols ? 27 : 30) : 36,
                        modifiers: .init(capsLockOn: model.capsLockOn, heldShift: model.heldShift,
                                         recommendedShift: guidance ? model.recommendedShift : nil,
                                         capsLockNeedsToggle: guidance && model.capsLockNeedsToggle),
                        showsNumberRow: model.area == .numbersSymbols)
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

    private var controls: some View {
        HStack(spacing: DS.Space.xxs) {
            RestartButton(action: model.restart)
            if model.phase != .finished {
                Button { model.nextExercise() } label: { Label("Next Exercise", systemImage: "arrow.right") }
                    .buttonStyle(.quiet)
                    .help("A new exercise for this stage (⌘→)")
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

// MARK: - Stages

private struct DrillStepper: View {
    let model: TypingMechanicsModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.area.drills.enumerated()), id: \.element) { index, drill in
                if index > 0 {
                    Rectangle().fill(DS.Palette.hairline).frame(width: 14, height: 1)
                }
                DrillButton(drill: drill, progress: model.progress.progress(drill), isSelected: drill == model.drill) {
                    model.select(drill)
                }
            }
        }
    }
}

private struct DrillButton: View {
    let drill: MechanicsDrill
    let progress: MechanicsProgress.DrillProgress
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    private var state: LessonState {
        if drill.area == .capitalisationLab { return progress.rounds > 0 ? .inProgress(qualifying: 0) : .notStarted }
        if progress.isSteady { return .mastered }
        return progress.rounds > 0 ? .inProgress(qualifying: progress.qualifyingRounds) : .notStarted
    }

    private var label: String {
        if drill.area == .capitalisationLab {
            return progress.rounds == 0 ? "Not started" : "\(progress.rounds) \(progress.rounds == 1 ? "round" : "rounds")"
        }
        return progress.isSteady ? "Steady" : state.label
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: state.symbol).font(.system(size: 13)).foregroundStyle(state.tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(drill.stage). \(drill.title)").font(DS.Typography.bodyEmphasis)
                    Text(label).font(DS.Typography.caption).foregroundStyle(.secondary)
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
        .help(drill.instructions)
        .accessibilityLabel("Stage \(drill.stage), \(drill.title), \(label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Header and live row

private struct MechanicsHeader: View {
    let model: TypingMechanicsModel
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("\(model.area.title) · Stage \(model.drill.stage)")
                Spacer()
                CapsLockIndicator(isOn: model.capsLockOn)
            }
            Text(model.drill.title).font(DS.Typography.pageTitle)
                .help(model.drill.instructions)
            if !compact {
                Text(model.drill.instructions)
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(techniqueLine, systemImage: "keyboard.badge.ellipsis")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .help(model.area.objective)
                .padding(.top, 2)
            if !model.judgesSymbols {
                Label("Your keyboard layout (\(model.layout?.name ?? "unknown")) is not US QWERTY. Symbols may sit elsewhere, so Shift for symbols is not judged.",
                      systemImage: "globe")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let comparisonLine {
                Label(comparisonLine, systemImage: "arrow.left.arrow.right")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .help("Shift Only and Caps Lock Only use the same passage. Which comes first alternates between comparisons, so practice favours neither.")
            }
        }
    }

    private var techniqueLine: String {
        switch model.drill {
        case .labShiftOnly: return "Technique: Shift for every capital, whole words included."
        case .labCapsLockOnly: return "Technique: Caps Lock for every capital, single letters included. On before, off after."
        case .labFreeChoice: return "Technique: yours. Nothing is marked wrong; Keyflow notes the method you use."
        case .numberRow: return "Technique: no modifiers. Reach up for each digit and come back to the home row."
        default: break
        }
        switch model.area {
        case .shiftControl: return "Technique: Shift for every capital. Recommended: the Shift on the other hand to the letter."
        case .capsLockControl: return "Technique: Caps Lock for words in capitals, switched off right after. Single capitals: your choice."
        case .caseTransitions, .capitalisationLab: return "Technique: your choice. Timing between cases is what is measured."
        case .numbersSymbols: return "Technique: Shift for symbols. Recommended: the Shift on the other hand to the key."
        }
    }

    /// "Comparison 3 · part 1 of 2 · then the same passage with Caps Lock"
    private var comparisonLine: String? {
        guard let current = model.currentComparison, let other = model.drill.labCounterpart else { return nil }
        let number = model.progress.comparisons.filter { $0.id != current.id }.count + 1
        return current.order == 1
            ? "Comparison \(number) · part 1 of 2 · then the same passage with \(other.title)"
            : "Comparison \(number) · part 2 of 2 · the passage you typed with \(other.title)"
    }
}

/// Unobtrusive: only there while Caps Lock is on.
private struct CapsLockIndicator: View {
    let isOn: Bool

    var body: some View {
        Label("Caps Lock on", systemImage: "capslock.fill")
            .font(DS.Typography.caption.weight(.medium))
            .foregroundStyle(Color.accentColor)
            .opacity(isOn ? 1 : 0)
            .motion(DS.Motion.quick, value: isOn)
            .accessibilityHidden(!isOn)
    }
}

private struct MechanicsLiveRow: View {
    let model: TypingMechanicsModel
    var guidance = true

    var body: some View {
        let metrics = model.metrics
        let typed = model.engine.position
        let total = max(1, model.engine.target.count)

        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(alignment: .center, spacing: DS.Space.xl) {
                Metric(value: metrics.totalKeystrokes > 0 ? metrics.accuracy.percentText : "–", label: "Characters",
                       tint: metrics.totalKeystrokes > 0 ? .accentColor : .secondary)
                Metric(value: model.liveTechniqueChecked > 0
                       ? (Double(model.liveTechniqueCorrect) / Double(model.liveTechniqueChecked)).percentText : "–",
                       label: "Technique", tint: model.liveTechniqueChecked > 0 ? .primary : .secondary,
                       help: "Capitals and symbols typed with the technique this drill asks for. Checked only for correct characters.")
                VStack(alignment: .leading, spacing: 6) {
                    ThinProgressBar(fraction: Double(typed) / Double(total)).frame(width: 140)
                    Text("\(typed) of \(total) characters").font(DS.Typography.caption).foregroundStyle(.secondary)
                }
                NextModifierHint(model: model, guidance: guidance)
            }
            .monospacedDigit()

            Text(techniqueMissText)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.caution)
                .frame(height: 14, alignment: .leading)
                .opacity(model.lastTechniqueMiss == nil ? 0 : 1)
                .motion(DS.Motion.quick, value: model.lastTechniqueMiss)
        }
    }

    private var techniqueMissText: String {
        guard let technique = model.lastTechniqueMiss else { return " " }
        let wanted = model.drill.wantedTechnique == .shift ? "Shift" : "Caps Lock"
        return "Right character, but typed with \(technique.title). This drill asks for \(wanted)."
    }
}

/// The next key and the modifier it calls for.
private struct NextModifierHint: View {
    let model: TypingMechanicsModel
    var guidance = true

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Text(model.nextKey.map { TrainingKeyboardView.name(of: $0) } ?? "–")
                .font(DS.Typography.metric(18, weight: .semibold))
                .foregroundStyle(model.nextKey == nil ? Color.secondary : Color.accentColor)
                .frame(minWidth: 34, minHeight: 34)
                .padding(.horizontal, model.nextKey == " " ? 6 : 0)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.key).strokeBorder(Color.accentColor.opacity(0.6)))
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow("Next key")
                Text(hint).font(DS.Typography.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var hint: String {
        guard let key = model.nextKey else { return " " }
        // Without guidance, only what the key is, not how to press it.
        guard guidance else { return key == " " ? "Space" : " " }
        if model.capsLockNeedsToggle { return model.capsLockOn ? "Caps Lock off first" : "Caps Lock on first" }
        if let side = model.recommendedShift { return "\(side == .left ? "Left" : "Right") Shift (recommended)" }
        if model.capsLockOn, key.isUppercase { return "Caps Lock is on" }
        if CaseRequirement.of(key) == .shiftedSymbol, !model.judgesSymbols { return "Shift on US layouts (not judged)" }
        if CaseRequirement.of(key) != .plain, model.nextRule == .any { return "Shift or Caps Lock" }
        return "No modifier"
    }
}

extension CaseTechnique {
    var title: String {
        switch self {
        case .leftShift: "Left Shift"
        case .rightShift: "Right Shift"
        case .shift: "Shift"
        case .capsLock: "Caps Lock"
        case .capsLockWithShift: "Caps Lock and Shift"
        case .unmodified: "no modifier"
        case .unknown: "an unknown method"
        }
    }
}

// MARK: - Results

private struct MechanicsResultView: View {
    let model: TypingMechanicsModel
    let summary: TypingMechanicsModel.RoundSummary
    var recommends = true

    var body: some View {
        let result = summary.result

        VStack(alignment: .leading, spacing: DS.Space.l) {
            HStack(alignment: .top, spacing: DS.Space.xl) {
                Metric(value: result.characterAccuracy.percentText, label: "Characters", size: 48, weight: .semibold,
                       tint: .accentColor)
                if model.drill == .labFreeChoice {
                    Metric(value: "–", label: "Not judged", size: 48, weight: .semibold, tint: .secondary,
                           help: "Free Choice accepts any method; see which you used below.")
                } else {
                    Metric(value: result.techniqueAccuracy?.percentText ?? "–", label: "Technique", size: 48, weight: .semibold,
                           help: "Correct capitals and symbols produced the way the drill asks.")
                }
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(headline).font(DS.Typography.sectionTitle)
                    Text(subline)
                        .font(DS.Typography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, DS.Space.xs)
            }

            if model.area == .numbersSymbols {
                numbersGrid(result)
            } else {
                capitalsGrid(result)
            }

            if model.area != .numbersSymbols {
                OverheadPanel(estimates: model.overhead, round: result)
            }

            if model.area == .capitalisationLab {
                if let comparison = summary.comparison {
                    LabComparisonView(comparison: comparison)
                } else {
                    LabSegmentsView(result: result, freeChoice: model.drill == .labFreeChoice)
                }
            }

            tipsAndActions
        }
    }

    private func numbersGrid(_ result: MechanicsRoundResult) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: DS.Space.xl, verticalSpacing: DS.Space.s) {
            GridRow {
                item("Letters to numbers", transition([.intoDigitDirect, .intoDigitAcrossSpace], result, versus: "between letters"))
                item("Numbers to letters", transition([.outOfDigitDirect, .outOfDigitAcrossSpace], result, versus: "between letters"))
            }
            GridRow {
                item("Within numbers", transition([.withinDigits], result, versus: "between letters"))
                item("Into symbols", transition([.intoShiftedSymbol], result, versus: "between letters"))
            }
            GridRow {
                item("Shift before the symbol", median(result.shiftLead, of: "symbols"))
                item("Characters to watch", watchList(result))
            }
            GridRow {
                item("Shift mistakes", result.caseErrors == 0 ? "None" : "\(result.caseErrors) right key without Shift (or with it)")
                item("Shift side", shiftSide(result))
            }
        }
        .monospacedDigit()
    }

    private func watchList(_ result: MechanicsRoundResult) -> String {
        let watch = MechanicsFeedback.charactersToWatch(in: result).prefix(4)
        guard !watch.isEmpty else { return "None stands out" }
        return watch.map { item in
            let stat = result.characters?[String(item.character)]
            return item.reason == .errors
                ? "\u{201C}\(item.character)\u{201D} wrong \(stat?.errors ?? 0) of \(stat?.attempts ?? 0)"
                : "\u{201C}\(item.character)\u{201D} slow to reach"
        }
        .joined(separator: " · ")
    }

    private func capitalsGrid(_ result: MechanicsRoundResult) -> some View {
            Grid(alignment: .topLeading, horizontalSpacing: DS.Space.xl, verticalSpacing: DS.Space.s) {
                GridRow {
                    item("Into capitals", transition(.intoUpperDirect, .intoUpperAcrossSpace, result))
                    item("Back to lower case", transition(.outOfUpperDirect, .outOfUpperAcrossSpace, result))
                }
                GridRow {
                    if model.area == .capsLockControl || result.capsLockLead.count > result.shiftLead.count {
                        item("Caps Lock to first capital", median(result.capsLockLead, of: "switches"))
                    } else {
                        item("Shift before the letter", median(result.shiftLead, of: "capitals"))
                    }
                    item("Case mistakes", caseMistakes(result))
                }
                GridRow {
                    item("Techniques seen", techniques(result))
                    if model.area == .shiftControl {
                        item("Shift side", shiftSide(result))
                    } else {
                        item("Not observable", result.techniqueUnknown == 0 ? "None" : "\(result.techniqueUnknown), not judged")
                    }
                }
            }
            .monospacedDigit()
    }

    private var tipsAndActions: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            if recommends, !model.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Eyebrow("Recommended practice · from your last \(MechanicsRecommender.window) rounds")
                    ForEach(model.recommendations) { recommendation in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                            Image(systemName: "scope").foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recommendation.title).font(DS.Typography.bodyEmphasis)
                                Text(recommendation.evidence).font(DS.Typography.body).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: DS.Space.s)
                            Button(practiceLabel(recommendation)) { model.follow(recommendation) }
                                .buttonStyle(.quiet)
                        }
                    }
                }
            }

            if !summary.tips.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(summary.tips, id: \.title) { tip in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                            Image(systemName: "lightbulb").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tip.title).font(DS.Typography.bodyEmphasis)
                                Text(tip.detail).font(DS.Typography.body).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            HStack(spacing: DS.Space.xs) {
                Button(action: model.performPrimaryAction) { Label(model.primaryActionTitle, systemImage: "arrow.right") }
                    .buttonStyle(.keyflowPrimary)
                    .help("Return")
                Button(action: model.restart) { Label("Repeat", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.quietGlass)
                    .help("Tab")
            }

            if let error = model.saveError {
                Label("This round could not be saved: \(error)", systemImage: "exclamationmark.triangle")
                    .font(DS.Typography.caption).foregroundStyle(DS.Palette.error)
            }
        }
    }

    /// The first of `kinds` with enough samples, against its lower-case baseline.
    private func transition(_ kinds: [TransitionClass], _ result: MechanicsRoundResult, versus: String) -> String {
        for kind in kinds {
            if let c = MechanicsFeedback.comparison(kind, in: result) {
                let sign = c.difference >= 0 ? "+" : "−"
                let spaced = [.intoDigitAcrossSpace, .outOfDigitAcrossSpace].contains(kind)
                return "\(Int(c.observed.rounded())) ms vs \(Int(c.baseline.rounded())) ms \(versus) (\(sign)\(Int(abs(c.difference).rounded())) ms, median\(spaced ? ", across a space" : ""))"
            }
        }
        let have = kinds.reduce(0) { $0 + result.samples($1).count }
        return have == 0 ? "No samples in this text" : "Not enough samples yet (\(have))"
    }

    private var headline: String {
        if model.drill == .labFreeChoice { return "Your natural capitalisation" }
        if summary.comparison != nil { return "Comparison complete" }
        if summary.justSteadied { return "Stage steady" }
        return MechanicsProgress.qualifies(summary.result) ? "Clean round" : "Accuracy first"
    }

    private var subline: String {
        let progress = model.drillProgress
        if model.drill == .labFreeChoice {
            return "Nothing here is right or wrong. Completed in \(seconds(summary.result.duration))."
        }
        if summary.comparison != nil {
            return "The same passage with Shift and with Caps Lock. Each comparison adds to the picture; one alone can be chance."
        }
        if model.pending != nil {
            return "Completed in \(seconds(summary.result.duration)). Now the same passage with \(model.pending!.awaiting.title)."
        }
        if summary.justSteadied { return "Three clean rounds: characters at 95%+ and technique at 90%+." }
        if MechanicsProgress.qualifies(summary.result) {
            return "\(min(progress.qualifyingRounds, MasteryTracker.requiredRounds)) of \(MasteryTracker.requiredRounds) clean rounds for this stage."
        }
        return "Rounds count at 95% characters and 90% technique. Slow down until the movement is automatic."
    }

    private func practiceLabel(_ recommendation: MechanicsRecommendation) -> String {
        recommendation.area == .capitalisationLab ? "Open Lab" : "Practise \(recommendation.drill.title)"
    }

    private func seconds(_ value: TimeInterval) -> String { String(format: "%.1f s", value) }

    private func item(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Eyebrow(label)
            Text(value).font(DS.Typography.body).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Observed against the same key change in lower case; direct changes preferred.
    private func transition(_ direct: TransitionClass, _ spaced: TransitionClass, _ result: MechanicsRoundResult) -> String {
        for kind in [direct, spaced] {
            if let c = MechanicsFeedback.comparison(kind, in: result) {
                let sign = c.difference >= 0 ? "+" : "−"
                return "\(Int(c.observed.rounded())) ms vs \(Int(c.baseline.rounded())) ms in lower case (\(sign)\(Int(abs(c.difference).rounded())) ms, median\(kind == spaced ? ", across a space" : ""))"
            }
        }
        let have = result.samples(direct).count + result.samples(spaced).count
        let baseline = result.samples(.lowerDirect).count + result.samples(.lowerAcrossSpace).count
        if have == 0 { return "No samples in this text" }
        if have >= MechanicsFeedback.minimumSamples, baseline < MechanicsFeedback.minimumSamples {
            return "\(have) timed; this text has too few matching lower-case changes to compare with"
        }
        return "Not enough samples yet (\(have))"
    }

    private func median(_ samples: TimingSamples, of noun: String) -> String {
        guard samples.count >= MechanicsFeedback.minimumSamples, let median = samples.median else {
            return samples.count == 0 ? "Not observed" : "Not enough samples yet (\(samples.count))"
        }
        return "\(Int(median.rounded())) ms (median of \(samples.count) \(noun))"
    }

    private func caseMistakes(_ result: MechanicsRoundResult) -> String {
        guard result.caseErrors > 0 else { return "None" }
        var text = "\(result.caseErrors) right key, wrong case"
        if result.capsLockLeftOn > 0 { text += "; \(result.capsLockLeftOn) with Caps Lock left on" }
        return text
    }

    private func techniques(_ result: MechanicsRoundResult) -> String {
        let order: [CaseTechnique] = [.leftShift, .rightShift, .shift, .capsLock, .capsLockWithShift, .unknown]
        let parts = order.compactMap { technique -> String? in
            guard let count = result.techniques[technique.rawValue], count > 0 else { return nil }
            return "\(technique.title.prefix(1).uppercased() + technique.title.dropFirst()) \(count)"
        }
        return parts.isEmpty ? "No capitals checked" : parts.joined(separator: " · ")
    }

    private func shiftSide(_ result: MechanicsRoundResult) -> String {
        let known = result.oppositeHandShift + result.sameHandShift
        guard known > 0 else { return "Side not observed" }
        return "\(result.oppositeHandShift) of \(known) with the opposite Shift (recommended)"
    }
}


// MARK: - Capitalisation Lab

/// Runs of capitals in this round, grouped by length: how long the whole
/// run took including the keys either side, and (Free Choice) the method.
private struct LabSegmentsView: View {
    let result: MechanicsRoundResult
    let freeChoice: Bool

    var body: some View {
        let segments = result.segments ?? []

        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Eyebrow(freeChoice ? "Your method by length of capitals" : "Runs of capitals by length")
            Grid(alignment: .leading, horizontalSpacing: DS.Space.l, verticalSpacing: 4) {
                GridRow {
                    Text("Letters").font(DS.Typography.caption).foregroundStyle(.secondary)
                    Text("Timed run, median").font(DS.Typography.caption).foregroundStyle(.secondary)
                    Text(freeChoice ? "Method used" : "Clean").font(DS.Typography.caption).foregroundStyle(.secondary)
                }
                ForEach(SegmentLength.allCases, id: \.self) { group in
                    let inGroup = segments.filter { $0.group == group }
                    if !inGroup.isEmpty {
                        GridRow {
                            Text(group.title).font(DS.Typography.code)
                            Text(LabFormat.span(inGroup)).font(DS.Typography.body)
                            Text(freeChoice ? LabFormat.methods(inGroup) : "\(inGroup.filter(\.clean).count) of \(inGroup.count)")
                                .font(DS.Typography.body).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .monospacedDigit()
            Text("A timed run starts at the key before the capitals and ends at the key after, so switching Caps Lock on and off is included.")
                .font(DS.Typography.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The same passage with Shift Only and Caps Lock Only, side by side.
private struct LabComparisonView: View {
    let comparison: MechanicsProgress.LabComparison

    var body: some View {
        let shift = comparison.shift, caps = comparison.capsLock

        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Eyebrow("Shift Only vs Caps Lock Only · \(comparison.first.title) first")
            Grid(alignment: .leading, horizontalSpacing: DS.Space.l, verticalSpacing: 4) {
                GridRow {
                    Text("").font(DS.Typography.caption)
                    Text("Shift").font(DS.Typography.caption).foregroundStyle(.secondary)
                    Text("Caps Lock").font(DS.Typography.caption).foregroundStyle(.secondary)
                }
                row("Completion time", String(format: "%.1f s", shift.duration), String(format: "%.1f s", caps.duration))
                row("Characters", shift.characterAccuracy.percentText, caps.characterAccuracy.percentText)
                row("Technique", shift.techniqueAccuracy?.percentText ?? "–", caps.techniqueAccuracy?.percentText ?? "–")
                ForEach(SegmentLength.allCases, id: \.self) { group in
                    let a = (shift.segments ?? []).filter { $0.group == group }
                    let b = (caps.segments ?? []).filter { $0.group == group }
                    if !a.isEmpty || !b.isEmpty {
                        row("\(group.title) letter\(group == .one ? "" : "s")", LabFormat.span(a), LabFormat.span(b))
                    }
                }
            }
            .monospacedDigit()
            Text("Runs are timed from the key before to the key after. Rows with fewer than two clean, timed runs show \u{201C}–\u{201D}. One passage is too little to call a method faster.")
                .font(DS.Typography.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ label: String, _ a: String, _ b: String) -> some View {
        GridRow {
            Text(label).font(DS.Typography.body)
            Text(a).font(DS.Typography.metric(13))
            Text(b).font(DS.Typography.metric(13))
        }
    }
}

enum LabFormat {
    /// Median span of clean, timed runs; "–" with fewer than two.
    static func span(_ segments: [UppercaseSegment]) -> String {
        let timed = segments.filter(\.clean).compactMap(\.spanMs)
        guard timed.count >= 2, let median = TimingSamples(timed).median else {
            return timed.count == 1 ? "1 run, not enough" : "–"
        }
        return "\(Int(median.rounded())) ms (\(timed.count))"
    }

    /// "Shift 2 · Caps Lock 1".
    static func methods(_ segments: [UppercaseSegment]) -> String {
        let order: [(UppercaseSegment.Method, String)] = [(.shift, "Shift"), (.capsLock, "Caps Lock"), (.mixed, "Mixed"), (.unknown, "Not observed")]
        return order.compactMap { method, title in
            let count = segments.filter { $0.method == method }.count
            return count > 0 ? "\(title) \(count)" : nil
        }
        .joined(separator: " · ")
    }
}


// MARK: - Capitalisation Overhead

/// Observed time, baseline and estimated overhead per method, pooled over
/// recent rounds, kept visibly apart.
struct OverheadPanel: View {
    let estimates: [CapitalisationOverhead.Method: CapitalisationOverhead.Estimate]
    /// This round's own runs, shown for context.
    var round: MechanicsRoundResult?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Eyebrow("Capitalisation overhead · last \(CapitalisationOverhead.recentRounds) rounds")
            Grid(alignment: .leading, horizontalSpacing: DS.Space.l, verticalSpacing: 4) {
                GridRow {
                    header("")
                    header("Observed")
                    header("Baseline")
                    header("Estimated overhead")
                    header("Runs")
                }
                ForEach(CapitalisationOverhead.Method.allCases, id: \.self) { method in
                    row(method, estimates[method])
                }
            }
            .monospacedDigit()
            if let note = roundNote {
                Text(note).font(DS.Typography.caption).foregroundStyle(.secondary)
            }
            Text("Per run of capitals, from the key before to the key after. Baseline: the same number of ordinary key changes in that round. Overhead = observed − baseline, as a median with its 95% range. An estimate from timing, not a measurement of your hands.")
                .font(DS.Typography.caption).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }

    private func header(_ text: String) -> some View {
        Text(text).font(DS.Typography.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func row(_ method: CapitalisationOverhead.Method, _ estimate: CapitalisationOverhead.Estimate?) -> some View {
        let runs = estimate?.runs ?? 0
        if let estimate, let overhead = estimate.overheadMs {
            GridRow {
                Text(method.title).font(DS.Typography.bodyEmphasis)
                Text(OverheadFormat.ms(estimate.observedMs)).font(DS.Typography.metric(13))
                Text(OverheadFormat.ms(estimate.baselineMs)).font(DS.Typography.metric(13))
                VStack(alignment: .leading, spacing: 1) {
                    Text(OverheadFormat.signed(overhead)).font(DS.Typography.metric(13, weight: .semibold))
                    Text(OverheadFormat.range(estimate.range))
                        .font(DS.Typography.caption).foregroundStyle(.secondary)
                }
                Text("\(runs)").font(DS.Typography.metric(13)).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(method.title): estimated overhead \(OverheadFormat.signed(overhead)) per run of capitals, from \(runs) runs")
        } else {
            GridRow {
                Text(method.title).font(DS.Typography.bodyEmphasis)
                Text("Not enough data yet: \(runs) of \(CapitalisationOverhead.minimumRuns) runs")
                    .font(DS.Typography.body).foregroundStyle(.secondary)
                    .gridCellColumns(4)
            }
        }
    }

    /// "This round: Shift +80 ms over 6 runs."
    private var roundNote: String? {
        guard let round else { return nil }
        let observations = CapitalisationOverhead.observations(from: [round])
        let parts = CapitalisationOverhead.Method.allCases.compactMap { method -> String? in
            let own = observations.filter { $0.method == method }.map(\.overheadMs)
            guard let median = TimingSamples(own).median else { return nil }
            return "\(method.title) \(OverheadFormat.signed(median)) over \(own.count) \(own.count == 1 ? "run" : "runs")"
        }
        return parts.isEmpty ? nil : "This round alone: " + parts.joined(separator: ", ") + " (median)."
    }
}

enum OverheadFormat {
    /// Rounded to 5 ms: finer than that would be false precision.
    static func rounded(_ value: Double) -> Int { Int((value / 5).rounded()) * 5 }

    static func ms(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(rounded(value)) ms"
    }

    /// "+60 ms to +110 ms", the 95% range of the median.
    static func range(_ range: ClosedRange<Double>?) -> String {
        guard let range else { return "range not yet available" }
        let low = signed(range.lowerBound), high = signed(range.upperBound)
        return low == high ? "no spread across runs" : "\(low) to \(high)"
    }

    static func signed(_ value: Double) -> String {
        let r = rounded(value)
        return r == 0 ? "±0 ms" : (r > 0 ? "+\(r) ms" : "−\(-r) ms")
    }
}


/// One quiet line under the stages: what recent rounds suggest practising.
private struct SuggestionLine: View {
    let recommendation: MechanicsRecommendation
    let action: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "scope").foregroundStyle(Color.accentColor)
            Text("Suggested: \(recommendation.area.title) · \(recommendation.title)")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(recommendation.evidence)
            Button("Go", action: action)
                .buttonStyle(.quiet)
                .font(DS.Typography.caption)
                .help(recommendation.evidence)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(recommendation.evidence)
    }
}
