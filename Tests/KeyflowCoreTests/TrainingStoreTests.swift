import Foundation
import Testing
@testable import KeyflowCore

@MainActor
@Suite struct TrainingStoreTests {
    private func sample(_ accuracy: Double = 0.97) -> RoundResult {
        RoundResult(text: "fj; dk.", accuracy: accuracy, keystrokes: 40, correctKeystrokes: 39, backspaces: 2, duration: 12.5,
                    keys: ["f": ErrorCount(attempts: 10, errors: 1), ";": ErrorCount(attempts: 5, errors: 0)],
                    pairs: ["fj": ErrorCount(attempts: 6, errors: 1)])
    }

    @Test func startsEmpty() throws {
        #expect(try TrainingStore.inMemory().events.isEmpty)
    }

    @Test func roundsAndSkipsRoundTrip() throws {
        let store = try TrainingStore.inMemory()
        let round = event(.homeRow, .singleKeys, .round(sample()), minute: 0)
        let skip = event(.topRow, .patterns, .skip, minute: 1)
        try store.record(round)
        try store.record(skip)
        #expect(store.events == [round, skip])
    }

    @Test func eventsStayInDateOrder() throws {
        let store = try TrainingStore.inMemory()
        let late = event(.round(sample()), minute: 10)
        let early = event(.round(sample(0.5)), minute: 1)
        let middle = event(.skip, minute: 5)
        try store.record(late)
        try store.record(early)
        try store.record(middle)
        #expect(store.events.map(\.id) == [early.id, middle.id, late.id])
    }

    @Test func storesAreIndependent() throws {
        let a = try TrainingStore.inMemory()
        let b = try TrainingStore.inMemory()
        try a.record(event(.skip, minute: 0))
        #expect(a.events.count == 1)
        #expect(b.events.isEmpty)
    }

    @Test func deleteAllEmptiesTheStore() throws {
        let store = try TrainingStore.inMemory()
        try store.record(event(.round(sample()), minute: 0))
        try store.deleteAll()
        #expect(store.events.isEmpty)
    }

    @Test func progressSurvivesReopeningTheFile() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "keyflow-training-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "MuscleMemory.store")

        var saved: [TrainingEvent] = []
        do {
            let store = try TrainingStore.onDisk(at: url)
            for minute in 0..<3 { try store.record(event(.homeRow, .singleKeys, .round(sample()), minute: minute)) }
            try store.record(event(.homeRow, .transitions, .skip, minute: 5))
            try store.record(event(.rightHand, .words, .round(sample(0.6)), minute: 6))
            saved = store.events
        }

        let reopened = try TrainingStore.onDisk(at: url)
        #expect(reopened.events == saved)

        let tracker = MasteryTracker(events: reopened.events)
        #expect(tracker.status(.homeRow, .singleKeys) == .mastered)
        #expect(tracker.status(.homeRow, .transitions) == .skipped)
        #expect(tracker.status(.homeRow, .patterns) == .available)
        #expect(tracker.progress(.rightHand, .words).accuracyHistory == [0.6])
        #expect(tracker.mistypedKeys(in: .homeRow).map(\.key) == ["f"])
    }

    @Test func livesAlongsideSessionHistoryWithoutTouchingIt() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "keyflow-both-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessionsURL = directory.appending(path: "Keyflow.store")
        let trainingURL = directory.appending(path: "MuscleMemory.store")

        var engine = TypingEngine(target: "abc", configuration: .init(timeLimit: 30))
        type("abc", into: &engine, from: 0, every: 0.5)
        do {
            let sessions = try StatisticsStore.onDisk(at: sessionsURL)
            try sessions.record(engine.session(at: 40), kind: .test, timeLimit: 30)
        }
        let before = try StatisticsStore.onDisk(at: sessionsURL).summaries

        do {
            let training = try TrainingStore.onDisk(at: trainingURL)
            try training.record(event(.round(sample()), minute: 0))
        }

        let after = try StatisticsStore.onDisk(at: sessionsURL).summaries
        #expect(after == before)
        #expect(after.count == 1)
        #expect(FileManager.default.fileExists(atPath: trainingURL.path))
        #expect(try TrainingStore.onDisk(at: trainingURL).events.count == 1)
    }
}
