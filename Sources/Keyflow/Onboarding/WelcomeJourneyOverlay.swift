import AppKit
import KeyflowCore
import SwiftUI

/// The Welcome Journey, drawn over the real window: a welcome card, then a
/// spotlight, arrow and short explanation on each real control, then the
/// first typing exercise and a small celebration.
///
/// Everything behind it stays live and laid out as normal; the overlay only
/// dims it and takes clicks, so the tour shows the actual interface.
struct WelcomeJourneyOverlay: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.decorativeAnimations) private var decorative
    /// The overlay's own frame in window coordinates, to place targets in it.
    @State private var overlayFrame: CGRect?
    @State private var popoverSize: CGSize = .zero

    private var animation: Animation? { reduceMotion || !decorative ? nil : DS.Motion.tour }

    var body: some View {
        let journey = app.journey
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let layout = tourLayout(journey: journey, bounds: bounds)

            ZStack(alignment: .topLeading) {
                // Takes every click meant for the window behind.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .accessibilityHidden(true)

                Dimming(spotlight: layout?.spotlight)
                    .accessibilityHidden(true)

                if let step = journey.currentStep {
                    if let layout {
                        GuidedArrow(layout: layout)
                            .accessibilityHidden(true)
                    }
                    TourPopover(step: step, number: journey.stepNumber ?? 1, of: journey.stepCount, canGoBack: journey.canGoBack)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { popoverSize = $0 }
                        .position(popoverCenter(layout: layout, bounds: bounds))
                        .opacity(popoverSize == .zero ? 0 : 1)
                } else {
                    card(for: journey.stage)
                        .frame(width: bounds.width, height: bounds.height)
                }
            }
            .animation(animation, value: layout)
            .animation(animation, value: StageKind(journey.stage))
            .onChange(of: layout, initial: true) { _, layout in
                if OnboardingProbe.isEnabled { OnboardingProbe.layout = layout }
            }
        }
        .background(WindowFrameReader { frame in
            overlayFrame = frame
            if OnboardingProbe.isEnabled { OnboardingProbe.overlayFrame = frame }
        })
        .onChange(of: journey.stage) {
            // Ask every target for its frame again once the new section is laid out.
            NotificationCenter.default.post(name: WindowFrameReader.ReaderView.measureAll, object: nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Welcome Journey")
    }

    private func tourLayout(journey: WelcomeJourney, bounds: CGRect) -> TourLayout? {
        guard let step = journey.currentStep, let overlayFrame, let frame = journey.targetFrames[step.target] else { return nil }
        return TourLayout.make(target: TourLayout.local(frame, in: overlayFrame), popover: popoverSize, bounds: bounds)
    }

    /// Next to its target, or centred while the target is not laid out yet.
    private func popoverCenter(layout: TourLayout?, bounds: CGRect) -> CGPoint {
        if let layout { return CGPoint(x: layout.popover.midX, y: layout.popover.midY) }
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }

    @ViewBuilder
    private func card(for stage: WelcomeJourney.Stage?) -> some View {
        switch stage {
        case .welcome:
            WelcomeCard().transition(.opacity)
        case .typing:
            FirstKeystrokesCard().transition(.opacity)
        case .complete(let summary):
            CompletionCard(summary: summary).transition(.opacity.combined(with: .scale(scale: 0.98)))
        case .tour, nil:
            EmptyView()
        }
    }
}

/// The stage without its payload, to animate between cards.
private enum StageKind: Equatable {
    case welcome, tour, typing, complete, none
    init(_ stage: WelcomeJourney.Stage?) {
        switch stage {
        case .welcome: self = .welcome
        case .tour: self = .tour
        case .typing: self = .typing
        case .complete: self = .complete
        case nil: self = .none
        }
    }
}

// MARK: - Spotlight

/// Dims the window, leaving a clear rounded window around the target with a
/// thin accent edge. The target keeps its own appearance.
private struct Dimming: View {
    let spotlight: CGRect?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let dim = (colorScheme == .dark ? 0.5 : 0.3) + (contrast == .increased ? 0.15 : 0)
        let spot = spotlight ?? .zero
        ZStack {
            SpotlightCutout(spotlight: spot, open: spotlight == nil ? 0 : 1)
                .fill(Color.black.opacity(dim), style: FillStyle(eoFill: true))
            if spotlight != nil {
                SpotlightCutout.ring(spot)
                    .stroke(Color.accentColor, lineWidth: contrast == .increased ? 3 : 2)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The whole area with a rounded hole. `open` 0 closes the hole, so the dim
/// covers everything when no target is shown.
private struct SpotlightCutout: Shape {
    var spotlight: CGRect
    var open: CGFloat

    var animatableData: AnimatablePair<CGRect.AnimatableData, CGFloat> {
        get { AnimatablePair(spotlight.animatableData, open) }
        set { spotlight.animatableData = newValue.first; open = newValue.second }
    }

    static let cornerRadius: CGFloat = 8

    static func ring(_ rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: cornerRadius)
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if open > 0.01, spotlight.width > 0 {
            path.addRoundedRect(in: spotlight, cornerSize: CGSize(width: Self.cornerRadius, height: Self.cornerRadius))
        }
        return path
    }
}

// MARK: - Arrow

/// A thin curved arrow from the explanation to the target, with a soft halo
/// so it reads on the dimmed window in light and dark appearance.
private struct GuidedArrow: View {
    let layout: TourLayout
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = ArrowShape(start: layout.arrowStart, control1: layout.arrowControl1,
                               control2: layout.arrowControl2, end: layout.arrowEnd)
        let width: CGFloat = contrast == .increased ? 3.5 : 2.5
        ZStack {
            shape.stroke(Color(nsColor: .windowBackgroundColor).opacity(0.75),
                         style: StrokeStyle(lineWidth: width + 3, lineCap: .round, lineJoin: .round))
            shape.stroke(Color.accentColor, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
    }
}

private struct ArrowShape: Shape {
    var start: CGPoint
    var control1: CGPoint
    var control2: CGPoint
    var end: CGPoint

    var animatableData: AnimatablePair<AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>,
                                       AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>> {
        get { AnimatablePair(AnimatablePair(start.animatableData, control1.animatableData),
                             AnimatablePair(control2.animatableData, end.animatableData)) }
        set {
            start.animatableData = newValue.first.first
            control1.animatableData = newValue.first.second
            control2.animatableData = newValue.second.first
            end.animatableData = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: control1, control2: control2)
        // The head follows the curve's direction at its end.
        let angle = atan2(end.y - control2.y, end.x - control2.x)
        let length: CGFloat = 10
        for spread in [CGFloat.pi * 0.82, -CGFloat.pi * 0.82] {
            path.move(to: end)
            path.addLine(to: CGPoint(x: end.x + cos(angle + spread) * length, y: end.y + sin(angle + spread) * length))
        }
        return path
    }
}

// MARK: - Cards

/// The surface every journey panel sits on: a material that follows Reduce
/// Transparency, with a firmer edge under Increase Contrast.
private struct JourneyCard: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Group {
            if #available(macOS 26, *), !reduceTransparency {
                content
                    .environment(\.isOnGlass, true)
                    .glassEffect(.regular, in: shape)
                    .overlay {
                        if contrast == .increased { shape.strokeBorder(Color.primary.opacity(0.45)) }
                    }
            } else {
                content
                    .background {
                        if reduceTransparency {
                            shape.fill(Color(nsColor: .windowBackgroundColor))
                        } else {
                            shape.fill(.regularMaterial)
                        }
                    }
                    .overlay(shape.strokeBorder(contrast == .increased ? Color.primary.opacity(0.45) : DS.Palette.hairline))
                    .shadow(color: .black.opacity(0.14), radius: 12, y: 4)
            }
        }
    }
}

private extension View {
    func journeyCard() -> some View { modifier(JourneyCard()) }
}

/// "3 of 7" (Full Tour) or "3 of 6" (Quick Tour).
private struct StepIndicator: View {
    let number: Int
    let count: Int
    var body: some View {
        Text("\(number) of \(count)")
            .font(DS.Typography.eyebrow)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .accessibilityLabel("Step \(number) of \(count)")
    }
}

private struct TourPopover: View {
    @Environment(AppModel.self) private var app
    let step: TourStep
    let number: Int
    let of: Int
    let canGoBack: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            StepIndicator(number: number, count: of)
            Text(step.title)
                .font(DS.Typography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Text(step.message)
                .font(DS.Typography.body)
                .fixedSize(horizontal: false, vertical: true)
            let location = step.location(app.preferences.navigation)
            Label(location, systemImage: "arrow.turn.up.left")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Highlighted: \(location)")
            HStack(spacing: DS.Space.xs) {
                Button("Skip Tour") { app.skipJourney() }
                    .buttonStyle(.quiet)
                    .keyboardShortcut(.cancelAction)
                    .help("Close the tour (Esc). Take it again any time from the Help menu.")
                Spacer(minLength: 0)
                if canGoBack {
                    Button("Back") { app.journeyBack() }
                        .buttonStyle(.quiet)
                        .keyboardShortcut(.leftArrow, modifiers: [])
                        .help("Back (←)")
                }
                Button("Next") { app.journeyNext() }
                    .buttonStyle(.keyflowPrimary)
                    .keyboardShortcut(.defaultAction)
                    .help("Next (Return)")
            }
            .padding(.top, DS.Space.xxs)
        }
        .padding(DS.Space.m + 2)
        .frame(width: 300)
        .journeyCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(step.title), step \(number) of \(of)")
    }
}

private struct WelcomeCard: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: DS.Space.s) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            Text("Welcome to Keyflow")
                .font(.system(size: 26, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text("A better way to master your keyboard.")
                .font(.system(size: 15, weight: .medium))
            Text("Build accuracy, develop muscle memory, and discover your typing potential.")
                .font(DS.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // First launch only: replays and existing users keep what they have.
            if app.journey.isFirstLaunch {
                NavigationChoice()
                    .padding(.top, DS.Space.xs)
            }
            VStack(spacing: DS.Space.xs) {
                Button("Start Journey") { app.startJourney() }
                    .buttonStyle(.keyflowPrimary)
                    .keyboardShortcut(.defaultAction)
                Button("Skip for Now") { app.skipJourney() }
                    .buttonStyle(.quiet)
                    .keyboardShortcut(.cancelAction)
                    .help("Take the tour any time from the Help menu.")
            }
            .padding(.top, DS.Space.s)
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, DS.Space.l + 4)
        .frame(width: 420)
        .journeyCard()
        .accessibilityElement(children: .contain)
    }
}

/// "How do you like to get around?" on the first welcome: top bar or
/// sidebar, each with a small picture. It changes the window behind at once.
private struct NavigationChoice: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: DS.Space.xs) {
            Text("How do you like to get around?")
                .font(DS.Typography.bodyEmphasis)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: DS.Space.s) {
                ForEach(NavigationStyle.allCases) { style in
                    NavigationChoiceTile(style: style, isSelected: app.preferences.navigation == style) {
                        app.setNavigation(style)
                    }
                }
            }
            Text("You can change this any time in Settings.")
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigation")
    }
}

private struct NavigationChoiceTile: View {
    let style: NavigationStyle
    let isSelected: Bool
    let choose: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: choose) {
            VStack(spacing: 6) {
                NavigationThumbnail(style: style)
                    .frame(width: 104, height: 64)
                Text(style.title)
                    .font(DS.Typography.body)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .padding(DS.Space.xs)
            .background(shape.fill(isSelected ? Color.accentColor.opacity(0.12) : DS.Palette.fill))
            .overlay(shape.strokeBorder(isSelected ? Color.accentColor : DS.Palette.hairline, lineWidth: isSelected ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .motion(DS.Motion.quick, value: isSelected)
        .accessibilityLabel(style.title)
        .accessibilityHint(style == .topBar ? "Sections in a bar across the top that steps aside while you type."
                                            : "Sections in a list down the left side.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A tiny window showing where the sections go. Decorative: the tile says it in words.
private struct NavigationThumbnail: View {
    let style: NavigationStyle

    var body: some View {
        let frame = RoundedRectangle(cornerRadius: 6, style: .continuous)
        let ink = Color.primary
        ZStack(alignment: .topLeading) {
            frame.fill(ink.opacity(0.05))
            HStack(spacing: 0) {
                if style == .sidebar {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(0..<5) { index in
                            Capsule()
                                .fill(index == 0 ? Color.accentColor : ink.opacity(0.28))
                                .frame(width: index == 0 ? 18 : 14, height: 3)
                        }
                    }
                    .padding(.top, 15)
                    .padding(.leading, 6)
                    .frame(width: 30, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(ink.opacity(0.07))
                }
                VStack(spacing: 5) {
                    if style == .topBar {
                        HStack(spacing: 3) {
                            ForEach(0..<5) { index in
                                Capsule()
                                    .fill(index == 0 ? Color.accentColor : ink.opacity(0.28))
                                    .frame(width: 7, height: 3)
                            }
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(ink.opacity(0.09)))
                        .padding(.top, 4)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach([0.9, 0.75, 0.85], id: \.self) { width in
                            GeometryReader { proxy in
                                Capsule().fill(ink.opacity(0.18)).frame(width: proxy.size.width * width, height: 3)
                            }
                            .frame(height: 3)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, style == .topBar ? 4 : 18)
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 2.5) {
                ForEach(0..<3) { _ in Circle().fill(ink.opacity(0.3)).frame(width: 4, height: 4) }
            }
            .padding(5)
        }
        .clipShape(frame)
        .overlay(frame.strokeBorder(ink.opacity(0.18)))
        .accessibilityHidden(true)
    }
}

/// The first typing exercise: Keyflow's own engine and renderer, no clock,
/// no score to reach, nothing saved.
private struct FirstKeystrokesCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.typingStyle) private var style
    @State private var keyboard = KeyboardMonitor(scope: .onboarding)

    private static let width: CGFloat = 600
    private static let padding: CGFloat = 28

    var body: some View {
        let journey = app.journey
        let engine = journey.engine
        let textWidth = Self.width - Self.padding * 2
        let lines = style.characterWidth * CGFloat(engine.target.count) <= textWidth ? 1 : 2

        VStack(alignment: .leading, spacing: DS.Space.s) {
            StepIndicator(number: journey.stepCount, count: journey.stepCount)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text("Your First Keystrokes")
                    .font(DS.Typography.pageTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("Every great typist starts somewhere.")
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
            }
            TypingSurfaceView(target: engine.target, typed: engine.typed, visibleLines: lines, isIdle: engine.typed.isEmpty)
                .padding(.vertical, DS.Space.s)
                .accessibilityHint("Type the sentence: \(WelcomeJourney.sentence)")
            Text(hint(journey))
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
            HStack(spacing: DS.Space.xs) {
                Button("Skip") { app.skipJourney() }
                    .buttonStyle(.quiet)
                    .help("Skip the exercise. Take the tour again any time from the Help menu.")
                Spacer()
                Button("Back") { app.journeyBack() }
                    .buttonStyle(.quiet)
            }
        }
        .padding(Self.padding)
        .frame(width: Self.width)
        .journeyCard()
        .accessibilityElement(children: .contain)
        .onAppear {
            // Typing goes straight here, with no field to click: the window
            // becomes key and nothing behind keeps the keyboard focus.
            if let window = NSApp.windows.first(where: { $0.identifier != KeyboardMonitor.settingsWindowID && $0.isVisible && $0.canBecomeKey }) {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(nil)
            }
            keyboard.start { app.handleJourneyKey($0) }
        }
        .onDisappear { keyboard.stop() }
    }

    private func hint(_ journey: WelcomeJourney) -> String {
        let engine = journey.engine
        if engine.typed.isEmpty { return "Just start typing. There’s no timer, so take your time." }
        if journey.hasMistakeShowing {
            return engine.typed.count == engine.target.count
                ? "Almost there. Press Delete to fix the letters in red."
                : "Red means a different key was pressed. Press Delete to fix it, then carry on."
        }
        return "Nice. Keep going."
    }
}

/// The end of a tour. Full Tour: a short celebration with Start Learning or
/// Explore Keyflow. Quick Tour: "You're all caught up" and back to where
/// the user was; returning users are never sent somewhere new.
private struct CompletionCard: View {
    @Environment(AppModel.self) private var app
    /// Nil after a Quick Tour.
    let summary: FirstTypingSummary?

    var body: some View {
        let completion: TutorialCompletion = summary == nil ? .quick : .full
        VStack(spacing: DS.Space.s) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: summary == nil ? 32 : 40, weight: .light))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(completion.title)
                .font(.system(size: 22, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            if let message = completion.message {
                Text(message)
                    .font(DS.Typography.body)
                    .foregroundStyle(.secondary)
            }
            if let summary {
                Text("\(seconds(summary)) · \(Int((summary.accuracy * 100).rounded()))% accuracy")
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            VStack(spacing: DS.Space.xs) {
                if summary == nil {
                    Button("Back to Keyflow") { app.finishJourney(startLearning: false) }
                        .buttonStyle(.keyflowPrimary)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Start Learning") { app.finishJourney(startLearning: true) }
                        .buttonStyle(.keyflowPrimary)
                        .keyboardShortcut(.defaultAction)
                    Button("Explore Keyflow") { app.finishJourney(startLearning: false) }
                        .buttonStyle(.quiet)
                        .help("Return to where you were")
                }
            }
            .padding(.top, DS.Space.s)
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.vertical, summary == nil ? DS.Space.l : DS.Space.l + 4)
        .frame(width: summary == nil ? 320 : 400)
        .journeyCard()
        .accessibilityElement(children: .contain)
    }

    private func seconds(_ summary: FirstTypingSummary) -> String {
        let value = max(1, Int(summary.seconds.rounded()))
        return value == 1 ? "1 second" : "\(value) seconds"
    }
}
