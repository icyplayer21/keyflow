import Foundation
import Testing
@testable import KeyflowCore

@Suite struct DailyFlowPlanTests {
    @Test func segmentsSplitTheSession() {
        let plan = DailyFlowPlan()
        #expect(plan.minutes == 10)
        #expect(plan.seconds(for: .warmUp) == 120)
        #expect(plan.seconds(for: .weakKeys) == 300)
        #expect(plan.seconds(for: .realText) == 180)
        #expect(plan.segment(atActive: 0) == .warmUp)
        #expect(plan.segment(atActive: 119.9) == .warmUp)
        #expect(plan.segment(atActive: 120) == .weakKeys)
        #expect(plan.segment(atActive: 420) == .realText)
        #expect(plan.segment(atActive: 600) == nil)
    }

    @Test func everyLengthAddsUp() {
        for minutes in DailyFlowPlan.lengths {
            let plan = DailyFlowPlan(minutes: minutes)
            #expect(DailyFlowSegment.allCases.reduce(0) { $0 + plan.seconds(for: $1) } == plan.totalSeconds)
        }
        #expect(DailyFlowPlan(minutes: 0).minutes == 10)
        #expect(DailyFlowPlan(minutes: 7).minutes == 10)
    }
}

@Suite struct DailyFlowPaceTests {
    @Test func startsAtTwoSeconds() {
        #expect(DailyFlowPace().delay == 2)
    }

    @Test func followsYourRhythmWithinLimits() {
        var slow = DailyFlowPace()
        for _ in 0..<10 { slow.record(gap: 1.2) }
        #expect(abs(slow.delay - 2.4) < 1e-9)

        var fast = DailyFlowPace()
        for _ in 0..<10 { fast.record(gap: 0.2) }
        #expect(fast.delay == 1.5)

        var verySlow = DailyFlowPace()
        for _ in 0..<10 { verySlow.record(gap: 3.5) }
        #expect(verySlow.delay == 4)
    }

    @Test func longPausesDoNotChangeTheRhythm() {
        var pace = DailyFlowPace()
        for _ in 0..<10 { pace.record(gap: 1) }
        for _ in 0..<3 { pace.record(gap: 60) }
        #expect(pace.delay == 2)
    }
}

@Suite struct DailyFlowFocusTests {
    @Test func picksWorstQualifyingLettersFirst() {
        let keys = DailyFlowFocus.keys(from: [
            "t": ErrorCount(attempts: 100, errors: 29),
            "e": ErrorCount(attempts: 100, errors: 20),
            "o": ErrorCount(attempts: 100, errors: 17),
            "n": ErrorCount(attempts: 100, errors: 13),
            "a": ErrorCount(attempts: 100, errors: 6),
        ])
        #expect(keys == ["t", "e", "o", "n"])
    }

    @Test func ignoresThinOrCleanData() {
        #expect(DailyFlowFocus.keys(from: [
            "q": ErrorCount(attempts: 3, errors: 3),      // too few attempts
            "w": ErrorCount(attempts: 100, errors: 1),    // one slip
            "r": ErrorCount(attempts: 100, errors: 4),    // under 5%
            ";": ErrorCount(attempts: 100, errors: 50),   // not a letter
        ]).isEmpty)
    }

    @Test func combinesCases() {
        #expect(DailyFlowFocus.keys(from: ["T": ErrorCount(attempts: 5, errors: 1),
                                           "t": ErrorCount(attempts: 5, errors: 1)]) == ["t"])
    }
}

@Suite struct DailyFlowGeneratorTests {
    @Test func sameSeedSamePassages() {
        var a = DailyFlowGenerator(seed: 7), b = DailyFlowGenerator(seed: 7)
        for segment in DailyFlowSegment.allCases {
            #expect(a.passage(for: segment, focus: ["t"]) == b.passage(for: segment, focus: ["t"]))
        }
    }

    @Test func warmUpIsHomeRowWords() {
        var generator = DailyFlowGenerator(seed: 1)
        for _ in 0..<50 {
            let text = generator.passage(for: .warmUp, focus: [])
            #expect(text.allSatisfy { " asdfghjkl".contains($0) })
            #expect(text.count >= 36)
        }
    }

    @Test func focusWordsWorkForEveryLetter() {
        for letter in "abcdefghijklmnopqrstuvwxyz" {
            var generator = DailyFlowGenerator(seed: 3)
            let text = generator.passage(for: .weakKeys, focus: [letter])
            let words = text.split(separator: " ")
            #expect(text.contains(letter), "no \(letter) in \(text)")
            #expect(words.count >= 3)
            #expect(text.allSatisfy { $0 == " " || ("a"..."z").contains($0) })
        }
    }

    @Test func everyFocusKeyGetsATurn() {
        var generator = DailyFlowGenerator(seed: 11)
        let focus: [Character] = ["t", "e", "o", "n"]
        var text = ""
        for _ in 0..<4 { text += generator.passage(for: .weakKeys, focus: focus) }
        for key in focus { #expect(text.contains(key)) }
    }

    @Test func sentencesArePlainAndShort() {
        #expect(DailyFlowGenerator.sentences.count > 10)
        var generator = DailyFlowGenerator(seed: 5)
        var previous = ""
        for _ in 0..<100 {
            let text = generator.passage(for: .realText, focus: [])
            #expect(!text.isEmpty && text.count <= 64)
            #expect(text.allSatisfy { $0 == " " || ("a"..."z").contains($0) })
            #expect(!text.hasSuffix(" "))
            #expect(text != previous)
            previous = text
        }
    }
}

@MainActor
@Suite struct DailyFlowHistoryTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func event(_ session: UUID, _ date: Date, keystrokes: Int = 50, correct: Int = 45, hints: Int = 5) -> DailyFlowEvent {
        let result = RoundResult(text: "text", accuracy: Double(correct) / Double(keystrokes), keystrokes: keystrokes,
                                 correctKeystrokes: correct, backspaces: 0, duration: 30)
        return DailyFlowEvent(date: date, round: DailyFlowRound(sessionID: session, segment: .weakKeys, plannedMinutes: 10,
                                                                activeSeconds: 30, hints: hints, result: result))
    }

    @Test func groupsPassagesIntoSessions() throws {
        let a = UUID(), b = UUID()
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let history = DailyFlowHistory(events: [event(a, start), event(a, start + 60), event(b, start + 86_400)])
        #expect(history.sessions.map(\.id) == [a, b])
        let first = try #require(history.sessions.first)
        #expect(first.totals.passages == 2)
        #expect(first.totals.activeSeconds == 60)
        #expect(first.totals.accuracy == 0.9)
        #expect(first.totals.withoutHints == 0.9)
        #expect(history.session(before: b)?.id == a)
        #expect(history.session(before: a) == nil)
    }

    @Test func weeksCountDistinctDays() {
        let calendar = calendar
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 12))!
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: monday)!
        let id = UUID()
        let history = DailyFlowHistory(events: [
            event(id, monday), event(id, monday + 60), event(UUID(), monday + 86_400), event(UUID(), lastWeek),
        ])
        #expect(history.week(of: monday, calendar: calendar).days == 2)
        #expect(history.week(of: monday, calendar: calendar).totals.passages == 3)
        #expect(history.previousWeek(from: monday, calendar: calendar).days == 1)
        #expect(history.hasPractised(on: monday, calendar: calendar))
    }

    @Test func emptyTotalsHaveNoRatios() {
        #expect(DailyFlowTotals().accuracy == nil)
        #expect(DailyFlowTotals().withoutHints == nil)
    }

    @Test func savedPassagesRoundTripAndStaySeparate() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flow-\(UUID().uuidString)").appendingPathComponent("Training.store")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let saved = event(UUID(), Date(timeIntervalSinceReferenceDate: 800_000_000))
        do {
            let store = try TrainingStore.onDisk(at: url)
            try store.record(saved)
        }
        let reopened = try TrainingStore.onDisk(at: url)
        #expect(reopened.dailyFlowEvents == [saved])
        #expect(reopened.events.isEmpty)
        #expect(reopened.fingerFocusEvents.isEmpty)
        #expect(reopened.assessmentEvents.isEmpty)
        #expect(reopened.mechanicsEvents.isEmpty)
        #expect(reopened.keyRepetitionEvents.isEmpty)
    }
}
