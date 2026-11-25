import SwiftUI

/// Learn: Today, Daily Flow, lessons by keyboard region, Finger Focus drills
/// for one finger at a time, Key Repetition and Typing Mechanics.
struct LearnView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 0) {
            // Steps aside with the main bar while you type, keeping its space.
            VStack(spacing: 0) {
                OptionBar(options: LearnMode.allCases, selection: $app.learnMode, font: DS.Typography.body, style: .tabs,
                          tour: (app.journey, { .learnMode($0) })) { $0.title }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Learn mode")
                Divider()
                    .frame(maxWidth: DS.Layout.readingWidth)
                    .padding(.horizontal, DS.Layout.pagePadding)
            }
            .opacity(app.topBar.isFaded ? 0 : 1)
            .allowsHitTesting(!app.topBar.isFaded)
            .motion(DS.Motion.standard, value: app.topBar.isFaded)

            switch app.learnMode {
            case .today: TodayView()
            case .dailyFlow: DailyFlowView(model: app.dailyFlow, isCovered: app.journey.isActive)
            case .lessons: MuscleMemoryView(model: app.muscleMemory)
            case .fingerFocus: FingerFocusView(model: app.fingerFocus)
            case .keyRepetition: KeyRepetitionView(model: app.keyRepetition) { app.learnMode = .lessons }
            case .mechanics: TypingMechanicsView(model: app.mechanics)
            }
        }
        .background(.background)
    }
}
