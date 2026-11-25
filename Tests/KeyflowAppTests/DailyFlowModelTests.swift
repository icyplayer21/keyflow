import Foundation
import Testing
@testable import Keyflow
import KeyflowCore

@MainActor
@Suite struct DailyFlowModelTests {
    private final class Clock { var now: Double = 1000 }

    private func key(_ c: Character, at time: Double, repeat isRepeat: Bool = false) -> KeyPress {
        KeyPress(keyCode: 1, characters: String(c), hasCommandOrControl: false, hasOption: false,
                 timestamp: time, isRepeat: isRepeat)
    }

    private func special(_ code: UInt16, at time: Double = 0) -> KeyPress {
        KeyPress(keyCode: code, characters: nil, hasCommandOrControl: false, hasOption: false, timestamp: time)
    }

    /// Types the current passage correctly, `gap` seconds apart.
    private func typePassage(_ model: DailyFlowModel, _ clock: Clock, gap: Double = 0.5) {
        let target = model.engine.target
        for character in target.dropFirst(model.engine.position) {
            clock.now += gap
            _ = model.handle(key(character, at: clock.now))
        }
    }

    private func model(store: TrainingStore? = nil, statistics: StatisticsStore? = nil,
                       defaults: UserDefaults? = nil, clock: Clock) -> DailyFlowModel {
        DailyFlowModel(store: store, statistics: statistics, defaults: defaults, seed: 42, clock: { clock.now })
    }

    @Test func startsWarmUpWithoutAHint() {
        let clock = Clock()
        let m = model(clock: clock)
        #expect(m.stage == .start)
        #expect(m.handle(special(KeyPress.return)))
        #expect(m.stage == .flowing)
        #expect(m.segment == .warmUp)
        #expect(!m.isHintShowing)
        #expect(m.nextKey != nil)
    }

    @Test func strayLettersAreSwallowedOffSession() {
        let clock = Clock()
        let m = model(clock: clock)
        #expect(m.handle(key("p", at: 1)))
        #expect(m.stage == .start)
    }

    @Test func hintWaitsForThePause() {
        let clock = Clock()
        let m = model(clock: clock)
        m.start()
        #expect(!m.revealHintIfDue(at: clock.now + 1.9))
        #expect(m.revealHintIfDue(at: clock.now + 2))
        #expect(m.isHintShowing)
        #expect(m.hintsThisPassage == 1)
        clock.now += 2
        _ = m.handle(key(m.nextKey!, at: clock.now))
        #expect(!m.isHintShowing)
    }

    @Test func oneHintPerPosition() {
        let clock = Clock()
        let m = model(clock: clock)
        m.start()
        #expect(m.revealHintIfDue(at: clock.now + 3))
        #expect(!m.revealHintIfDue(at: clock.now + 9))
        clock.now += 3
        _ = m.handle(key("#", at: clock.now))
        clock.now += 0.1
        _ = m.handle(special(KeyPress.delete, at: clock.now))
        #expect(m.engine.position == 0)
        #expect(m.revealHintIfDue(at: clock.now + 5))
        #expect(m.hintsThisPassage == 1, "the same position is one hint")
    }

    @Test func hintsOffNeverShow() {
        let clock = Clock()
        let m = model(clock: clock)
        m.start()
        m.showsKeyboard = false
        #expect(!m.revealHintIfDue(at: clock.now + 60))
    }

    @Test func noHintWhilePaused() {
        let clock = Clock()
        let m = model(clock: clock)
        m.start()
        _ = m.handle(special(KeyPress.escape))
        #expect(m.isPaused)
        #expect(!m.revealHintIfDue(at: clock.now + 60))
        let position = m.engine.position
        #expect(m.handle(key("a", at: clock.now + 1)))
        #expect(m.engine.position == position)
        _ = m.handle(special(KeyPress.escape))
        #expect(!m.isPaused)
    }

    @Test func heldKeyTypesNothing() {
        let clock = Clock()
        let m = model(clock: clock)
        m.start()
        for i in 0..<50 { #expect(m.handle(key("a", at: clock.now + Double(i) * 0.03, repeat: true))) }
        #expect(m.engine.position == 0)
    }

    @Test func walkingAwayDoesNotFillTheSession() {
        let clock = Clock()
        let m = model(clock: clock)
        m.start()
        let first = m.nextKey!
        _ = m.handle(key(first, at: 100))
        _ = m.handle(key(m.nextKey!, at: 10_000))
        #expect(m.activeSeconds == DailyFlowPlan.maximumGap)
    }

    @Test func pauseAddsNoTime() {
        let clock = Clock()
        let m = model(clock: clock)
        m.start()
        _ = m.handle(key(m.nextKey!, at: 100))
        m.pause()
        clock.now = 500
        m.resume()
        _ = m.handle(key(m.nextKey!, at: 500.5))
        #expect(m.activeSeconds == 0)
    }

    @Test func finishedPassageSavesAndContinues() throws {
        let store = try TrainingStore.inMemory()
        let clock = Clock()
        let m = model(store: store, clock: clock)
        m.start()
        let text = m.engine.target
        typePassage(m, clock)
        #expect(store.dailyFlowEvents.count == 1)
        let saved = try #require(store.dailyFlowEvents.first)
        #expect(saved.round.segment == .warmUp)
        #expect(saved.round.plannedMinutes == 10)
        #expect(saved.round.result.accuracy == 1)
        #expect(m.stage == .flowing)
        #expect(m.engine.target != text)
        #expect(m.engine.position == 0)
    }

    @Test func runsThroughEverySegmentAndEnds() throws {
        let store = try TrainingStore.inMemory()
        let clock = Clock()
        let m = model(store: store, clock: clock)
        m.setMinutes(5)
        m.start()
        var seen: [DailyFlowSegment] = []
        var guardCount = 0
        while m.stage == .flowing, guardCount < 500 {
            if seen.last != m.segment { seen.append(m.segment) }
            typePassage(m, clock, gap: 1)
            guardCount += 1
        }
        #expect(seen == [.warmUp, .weakKeys, .realText])
        guard case .complete(let session) = m.stage else { Issue.record("did not finish"); return }
        #expect(session.totals.activeSeconds >= 300)
        #expect(session.totals.activeSeconds < 300 + 80, "ends at the first passage end after the plan")
        #expect(session.totals.accuracy == 1)
        #expect(session.totals.withoutHints == 1)
        #expect(Set(store.dailyFlowEvents.map(\.round.sessionID)).count == 1)
        #expect(m.handle(special(KeyPress.return)))
        #expect(m.stage == .start)
    }

    @Test func endingEarlyKeepsFinishedPassagesOnly() throws {
        let store = try TrainingStore.inMemory()
        let clock = Clock()
        let m = model(store: store, clock: clock)
        m.start()
        typePassage(m, clock)
        clock.now += 0.5
        _ = m.handle(key(m.nextKey!, at: clock.now))
        m.endEarly()
        #expect(store.dailyFlowEvents.count == 1)
        guard case .complete(let session) = m.stage else { Issue.record("no summary"); return }
        #expect(session.totals.passages == 1)
    }

    @Test func endingBeforeAnyPassageSavesNothing() throws {
        let store = try TrainingStore.inMemory()
        let clock = Clock()
        let m = model(store: store, clock: clock)
        m.start()
        m.endEarly()
        #expect(m.stage == .start)
        #expect(store.dailyFlowEvents.isEmpty)
    }

    @Test func restartingAPassageTakesItsTimeBack() {
        let clock = Clock()
        let m = model(clock: clock)
        m.start()
        let text = m.engine.target
        _ = m.handle(key(m.nextKey!, at: 10))
        _ = m.handle(key(m.nextKey!, at: 11))
        #expect(m.activeSeconds == 1)
        #expect(m.handle(special(KeyPress.tab)))
        #expect(m.engine.target == text)
        #expect(m.engine.position == 0)
        #expect(m.activeSeconds == 0)
    }

    @Test func focusComesFromRecentMistakes() throws {
        let store = try TrainingStore.inMemory()
        let result = RoundResult(text: "t", accuracy: 0.7, keystrokes: 100, correctKeystrokes: 70, backspaces: 0, duration: 60,
                                 keys: ["t": ErrorCount(attempts: 50, errors: 20)])
        try store.record(TrainingEvent(category: .homeRow, stage: .singleKeys, kind: .round(result)))
        let clock = Clock()
        let m = model(store: store, clock: clock)
        #expect(m.focusKeys == ["t"])
        #expect(!m.usesStarterKeys)
        let fresh = model(clock: clock)
        #expect(fresh.focusKeys == DailyFlowFocus.starterKeys)
        #expect(fresh.usesStarterKeys)
    }

    @Test func choicesAreRemembered() {
        let name = "keyflow.tests.dailyFlow.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let clock = Clock()
        let m = model(defaults: defaults, clock: clock)
        m.setMinutes(15)
        m.showsKeyboard = false
        let again = model(defaults: defaults, clock: clock)
        #expect(again.plan.minutes == 15)
        #expect(!again.showsKeyboard)
    }

    @Test func appWiring() throws {
        let store = try TrainingStore.inMemory()
        let app = AppModel(store: try StatisticsStore.inMemory(), trainingStore: store, defaults: nil)
        #expect(Array(LearnMode.allCases.prefix(2)) == [.today, .dailyFlow])
        #expect(AppSection.allCases.count == 5)
        #expect(app.learnMode == .today, "Learn opens on Today")
        app.section = .muscleMemory
        app.learnMode = .dailyFlow
        #expect(!app.hasNextLearnExercise)
        app.learnShowsKeyboard = false
        #expect(!app.dailyFlow.showsKeyboard)
        app.resetSettings()
        #expect(app.dailyFlow.showsKeyboard)

        let clock = Clock()
        _ = clock
        app.dailyFlow.start()
        let text = app.dailyFlow.engine.target
        for (i, c) in text.enumerated() { _ = app.dailyFlow.handle(key(c, at: Double(i))) }
        #expect(store.dailyFlowEvents.count == 1)
        #expect(store.events.isEmpty)
        #expect(app.store?.summaries.isEmpty == true)

        let export = try JSONSerialization.jsonObject(with: KeyflowExport(store: nil, trainingStore: store).json()) as? [String: Any]
        #expect((export?["dailyFlow"] as? [Any])?.count == 1)

        try app.resetProgress()
        #expect(store.dailyFlowEvents.isEmpty)
        #expect(app.dailyFlow.history.sessions.isEmpty)
    }
}
