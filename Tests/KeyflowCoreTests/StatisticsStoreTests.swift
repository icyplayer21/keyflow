import Foundation
import Testing
@testable import KeyflowCore

@MainActor
@Suite struct StatisticsStoreTests {
    /// A finished 30 s session with `correct` right characters and a few wrong ones.
    private func finishedSession(correct: Int, wrong: Int = 0, limit: Double = 30) -> TypingSession {
        var engine = TypingEngine(target: String(repeating: "abcd ", count: 100), configuration: .init(timeLimit: limit))
        var time = 100.0
        for index in 0..<(correct + wrong) {
            engine.insert(index < correct ? engine.target[engine.position] : "#", at: time)
            time += 0.05
        }
        engine.backspace(at: time)
        engine.insert(engine.target[engine.position], at: time + 0.05)
        engine.tick(at: 10_000)
        return engine.session(at: 10_000)
    }

    private func date(_ offset: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + offset) }

    @Test func startsEmpty() throws {
        let store = try StatisticsStore.inMemory()
        #expect(store.summaries.isEmpty)
        #expect(store.personalBest(of: .test) == nil)
    }

    @Test func recordedSessionKeepsItsNumbers() throws {
        let store = try StatisticsStore.inMemory()
        let session = finishedSession(correct: 100, wrong: 5)
        let summary = try store.record(session, kind: .test, timeLimit: 30, date: date(0))

        let metrics = PerformanceCalculator.metrics(for: session)
        #expect(summary.metrics == metrics)
        #expect(summary.kind == .test)
        #expect(summary.timeLimit == 30)
        #expect(summary.date == date(0))
        #expect(summary.consistency == SessionAnalyzer.consistency(of: session))
        #expect(summary.consistency != nil)
        #expect(store.summaries == [summary])
    }

    @Test func fullKeystrokeLogRoundTrips() throws {
        let store = try StatisticsStore.inMemory()
        let session = finishedSession(correct: 60, wrong: 4)
        let summary = try store.record(session, kind: .practice(.punctuation), timeLimit: 30)

        let loaded = try #require(try store.session(for: summary.id))
        #expect(loaded == session)
        #expect(SessionAnalyzer.analyze(loaded) == SessionAnalyzer.analyze(session))
        #expect(try store.session(for: UUID()) == nil)
    }

    @Test func unusualCharactersSurviveStorage() throws {
        let store = try StatisticsStore.inMemory()
        var engine = TypingEngine(target: "\"q\" \\ caf\u{00E9} {x}", configuration: .init(timeLimit: 60))
        for (offset, character) in "\"q\" \\ cafe {x}".enumerated() { engine.insert(character, at: Double(offset)) }
        let session = engine.session(at: 100)
        let summary = try store.record(session, kind: .practice(.customText), timeLimit: 60)
        #expect(try store.session(for: summary.id) == session)
    }

    @Test func tooShortSessionStoresNoConsistency() throws {
        let store = try StatisticsStore.inMemory()
        var engine = TypingEngine(target: "ab")
        engine.insert("a", at: 0)
        engine.insert("b", at: 1)
        let summary = try store.record(engine.session(at: 1), kind: .practice(.customText), timeLimit: 30)
        #expect(summary.consistency == nil)
        #expect(store.summaries.first?.consistency == nil)
    }

    @Test func summariesAreNewestFirstRegardlessOfInsertOrder() throws {
        let store = try StatisticsStore.inMemory()
        let session = finishedSession(correct: 50)
        let middle = try store.record(session, kind: .test, timeLimit: 30, date: date(100))
        let newest = try store.record(session, kind: .test, timeLimit: 30, date: date(200))
        let oldest = try store.record(session, kind: .test, timeLimit: 30, date: date(0))
        #expect(store.summaries.map(\.id) == [newest.id, middle.id, oldest.id])
    }

    @Test func personalBestIsHighestNetWPMForThatKindAndLength() throws {
        let store = try StatisticsStore.inMemory()
        let slow = try store.record(finishedSession(correct: 50), kind: .test, timeLimit: 30, date: date(0))
        let fast = try store.record(finishedSession(correct: 120), kind: .test, timeLimit: 30, date: date(10))
        _ = try store.record(finishedSession(correct: 80), kind: .test, timeLimit: 30, date: date(20))
        let longTest = try store.record(finishedSession(correct: 200, limit: 60), kind: .test, timeLimit: 60, date: date(30))
        _ = try store.record(finishedSession(correct: 300), kind: .practice(.commonWords), timeLimit: 30, date: date(40))

        #expect(store.personalBest(of: .test, timeLimit: 30)?.id == fast.id)
        #expect(store.personalBest(of: .test, timeLimit: 60)?.id == longTest.id)
        #expect(store.personalBest(of: .test, timeLimit: 120) == nil)
        #expect(store.personalBest(of: .test)?.id == fast.id)      // 120 chars in 30 s beats 200 in 60 s
        #expect(store.summaries(of: .test).count == 4)
        #expect(store.summaries(of: .test, timeLimit: 30).contains { $0.id == slow.id })
        #expect(store.summaries(of: .practice(.sentences)).isEmpty)
    }

    @Test func earliestSessionWinsAPersonalBestTie() throws {
        let store = try StatisticsStore.inMemory()
        let first = try store.record(finishedSession(correct: 90), kind: .test, timeLimit: 30, date: date(0))
        _ = try store.record(finishedSession(correct: 90), kind: .test, timeLimit: 30, date: date(50))
        #expect(store.personalBest(of: .test, timeLimit: 30)?.id == first.id)
    }

    @Test func storesAreIndependentOfEachOther() throws {
        let a = try StatisticsStore.inMemory()
        let b = try StatisticsStore.inMemory()
        try a.record(finishedSession(correct: 50), kind: .test, timeLimit: 30)
        #expect(a.summaries.count == 1)
        #expect(b.summaries.isEmpty)
    }

    @Test func deleteAllEmptiesTheStore() throws {
        let store = try StatisticsStore.inMemory()
        let summary = try store.record(finishedSession(correct: 50), kind: .test, timeLimit: 30)
        try store.deleteAll()
        #expect(store.summaries.isEmpty)
        #expect(try store.session(for: summary.id) == nil)
    }

    @Test func sessionsSurviveReopeningTheFile() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "keyflow-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "nested/Keyflow.store")
        let session = finishedSession(correct: 75, wrong: 3)

        let saved: [SessionSummary]
        do {
            let store = try StatisticsStore.onDisk(at: url)
            try store.record(session, kind: .test, timeLimit: 30, date: date(0))
            try store.record(session, kind: .practice(.numbersSymbols), timeLimit: 120, date: date(60))
            saved = store.summaries
        }

        let reopened = try StatisticsStore.onDisk(at: url)
        #expect(reopened.summaries == saved)
        #expect(reopened.summaries.map(\.kind) == [.practice(.numbersSymbols), .test])
        #expect(try reopened.session(for: saved[1].id) == session)
    }
}
