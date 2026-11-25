import KeyflowCore
import SwiftUI

/// Learn ▸ Today: Keyflow's front door. Today's Daily Flow with one Start
/// button, the days you practised this week, and a way back into the modes
/// you have used. It reads saved practice only and changes none of it.
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @State private var keyboard = KeyboardMonitor()

    var body: some View {
        // Read once per update; the date line and week follow the clock at each visit.
        let now = Date.now
        let days = app.practiceDays

        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(DS.Typography.body)
                        .foregroundStyle(.secondary)
                    Text("Today")
                        .font(DS.Typography.pageTitle)
                        .accessibilityAddTraits(.isHeader)
                }

                TodaySessionCard(model: app.dailyFlow, start: app.startDailyFlowFromToday)

                PracticeWeekView(days: days, now: now)

                let rows = app.pickUps
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Text("Pick up where you left off")
                            .font(DS.Typography.sectionTitle)
                            .accessibilityAddTraits(.isHeader)
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                if index > 0 { Divider().padding(.leading, 44) }
                                PickUpRow(row: row) { app.pickUp(row) }
                            }
                        }
                        .background(DS.Palette.fill, in: RoundedRectangle(cornerRadius: DS.Radius.panel))
                    }
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(.horizontal, DS.Layout.pagePadding)
            .padding(.vertical, DS.Space.l)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(.background)
        .onAppear {
            keyboard.start { press in
                // Return starts today's session, like the button.
                guard press.keyCode == KeyPress.return || press.keyCode == KeyPress.enter,
                      !press.hasCommandOrControl else { return false }
                app.startDailyFlowFromToday()
                return true
            }
            if app.dailyFlow.stage == .start { app.dailyFlow.refreshFocus() }
        }
        .onDisappear { keyboard.stop() }
    }
}

// MARK: - Today's session

private struct TodaySessionCard: View {
    let model: DailyFlowModel
    let start: () -> Void

    private enum State { case ready, underWay, done(DailyFlowHistory.Session?) }

    private var state: State {
        if case .flowing = model.stage { return .underWay }
        if model.hasPractisedToday {
            let today = model.history.sessions.last { Calendar.current.isDateInToday($0.date) }
            return .done(today)
        }
        return .ready
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Eyebrow("Daily Flow")
            switch state {
            case .ready:
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("Today's session · about \(model.plan.minutes) min")
                        .font(DS.Typography.sectionTitle)
                    focusKeys
                }
                actions(primary: true, title: "Start", help: "Start today's session (Return)")
            case .underWay:
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("Today's session is under way")
                        .font(DS.Typography.sectionTitle)
                    Text("It's paused where you left it.")
                        .font(DS.Typography.body)
                        .foregroundStyle(.secondary)
                }
                actions(primary: true, title: "Continue", help: "Back to today's session (Return)")
            case .done(let session):
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Label("Done for today", systemImage: "checkmark.circle")
                        .font(DS.Typography.sectionTitle)
                    if let session {
                        Text("\(flowDuration(session.totals.activeSeconds)) · \(flowPercent(session.totals.accuracy)) accuracy")
                            .font(DS.Typography.body)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                actions(primary: false, title: "Practice More", help: "Open Daily Flow (Return)")
            }
        }
        .padding(DS.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Palette.fill, in: RoundedRectangle(cornerRadius: DS.Radius.panel * 1.5))
        .accessibilityElement(children: .contain)
    }

    private var focusKeys: some View {
        HStack(spacing: DS.Space.xs) {
            Text("Focus keys").foregroundStyle(.secondary)
            ForEach(model.focusKeys, id: \.self) { KeyCap(String($0).uppercased()) }
        }
        .font(DS.Typography.body)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus keys: \(model.focusKeys.map { String($0).uppercased() }.joined(separator: ", "))")
    }

    @ViewBuilder
    private func actions(primary: Bool, title: String, help: String) -> some View {
        HStack(spacing: DS.Space.s) {
            if primary {
                Button(title, action: start).buttonStyle(.keyflowPrimary)
            } else {
                Button(title, action: start).buttonStyle(.quiet)
            }
            HStack(spacing: 5) {
                KeyCap("return")
                Text(title.lowercased())
            }
            .font(DS.Typography.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .help(help)
    }
}

// MARK: - This week

/// Seven dots for the days of this week. Filled: you practised. Ringed: today.
struct PracticeWeekView: View {
    let days: PracticeDays
    let now: Date

    var body: some View {
        let week = days.week(of: now)
        let streak = days.streak(asOf: now)

        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .font(DS.Typography.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                // Said only when true, and never as a score.
                if streak >= 2 {
                    Text("\(streak) days in a row")
                        .font(DS.Typography.body)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            HStack(spacing: 0) {
                ForEach(week) { day in
                    VStack(spacing: DS.Space.xs) {
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(DS.Typography.caption)
                            .foregroundStyle(day.isToday ? .primary : .secondary)
                        WeekDot(day: day)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("This week")
            .accessibilityValue(summary(week))
        }
    }

    private func summary(_ week: [PracticeDays.Day]) -> String {
        let practised = week.filter(\.practised).map { $0.date.formatted(.dateTime.weekday(.wide)) }
        guard !practised.isEmpty else { return "No practice yet this week" }
        return "Practised on " + ListFormatter.localizedString(byJoining: practised)
    }
}

private struct WeekDot: View {
    let day: PracticeDays.Day
    private let size: CGFloat = 14

    var body: some View {
        Circle()
            .fill(day.practised ? Color.accentColor : DS.Palette.selected)
            .opacity(day.isAhead ? 0.5 : 1)
            .frame(width: size, height: size)
            .padding(3)
            .overlay {
                if day.isToday { Circle().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5) }
            }
    }
}

// MARK: - Pick up

private struct PickUpRow: View {
    let row: AppModel.PickUp
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.s) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(DS.Typography.bodyEmphasis)
                    Text(detail).font(DS.Typography.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: DS.Space.s)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, DS.Space.s)
            .background(isHovered ? DS.Palette.hover : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.panel))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("\(title): \(detail)")
        .accessibilityHint("Opens \(title)")
    }

    private var title: String {
        switch row {
        case .lessons: LearnMode.lessons.title
        case .fingerFocus: LearnMode.fingerFocus.title
        case .keyRepetition: LearnMode.keyRepetition.title
        }
    }

    private var detail: String {
        switch row {
        case .lessons(let category, let stage): "\(category.title) · Stage \(stage.rawValue): \(stage.title)"
        case .fingerFocus(let target): target.title
        case .keyRepetition(let letter): "The \(String(letter).uppercased()) key"
        }
    }

    private var symbol: String {
        switch row {
        case .lessons: "list.number"
        case .fingerFocus: "hand.point.up.left"
        case .keyRepetition: "repeat"
        }
    }
}
