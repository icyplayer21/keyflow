import Foundation
import Testing
@testable import KeyflowCore

/// A scripted typist: steady pace, optional slow letter pairs, optional keys
/// that are always typed wrong. Produces a finished 30-second session.
func simulatedSession(seed: UInt64, characters: Int = 300, pace: Double = 0.08,
                      slowPairs: [String: Double] = [:], missedKeys: Set<Character> = []) -> TypingSession {
    var supply = TextSupply(mode: .sentences, seed: seed)
    var engine = TypingEngine(target: supply.next(atLeast: characters + 10), configuration: .init(timeLimit: 30))
    var time = 1_000.0
    var previous: Character?
    for _ in 0..<characters {
        let expected = engine.target[engine.position]
        let lower = Character(expected.lowercased())
        if let previous, let slow = slowPairs[String([previous, lower])] { time += slow } else { time += pace }
        engine.insert(missedKeys.contains(lower) ? "#" : expected, at: time)
        previous = lower
    }
    engine.tick(at: 5_000)
    return engine.session(at: 5_000)
}

func analyzed(_ session: TypingSession, kind: SessionKind = .test, hour: Int) -> AnalyzedSession {
    AnalyzedSession(
        summary: SessionSummary(
            id: UUID(), date: Date(timeIntervalSince1970: 1_700_000_000 + Double(hour) * 3_600), kind: kind, timeLimit: 30,
            metrics: PerformanceCalculator.metrics(for: session), consistency: SessionAnalyzer.consistency(of: session)),
        analysis: SessionAnalyzer.analyze(session))
}

@Suite struct ProgressAnalyzerTests {
    @Test func emptyHistoryProducesAnEmptyReport() {
        let report = ProgressAnalyzer.report(for: [])
        #expect(report.tests.isEmpty)
        #expect(report.practiceSessions == 0)
        #expect(report.personalBest == nil)
        #expect(report.recentWPM == nil && report.recentAccuracy == nil && report.recentConsistency == nil)
        #expect(report.totalTime == 0)
        #expect(!report.weaknesses.hasEnoughData)
        #expect(report.weaknessHistory.isEmpty)
        #expect(report.formerWeaknesses.isEmpty)
    }

    @Test func oneShortSessionIsNotEnoughData() {
        let report = ProgressAnalyzer.report(for: [analyzed(simulatedSession(seed: 1, missedKeys: ["e"]), hour: 0)])
        #expect(report.tests.count == 1)
        #expect(report.weaknesses.keystrokes == 300)
        #expect(!report.weaknesses.hasEnoughData)
        #expect(report.weaknesses.all.isEmpty)       // even though every "e" was wrong
        #expect(report.weaknessHistory.isEmpty)
    }

    @Test func consistentProblemsAreFoundAndSeparated() throws {
        let sessions = (0..<12).map { index in
            analyzed(simulatedSession(seed: UInt64(index), slowPairs: ["th": 0.24], missedKeys: ["v"]), hour: index)
        }
        let report = ProgressAnalyzer.report(for: sessions)

        #expect(report.weaknesses.hasEnoughData)
        let missed = try #require(report.weaknesses.accuracy.first { $0.id == "accuracy.key.v" })
        #expect(missed.value == 1)
        #expect(missed.errors == missed.samples)
        let slow = try #require(report.weaknesses.speed.first { $0.id == "speed.combination.th" })
        #expect(abs(slow.value - 0.24) < 1e-9)
        #expect(slow.severity > 2)

        // The slow pair is not an accuracy problem and the missed key is not a speed problem.
        #expect(!report.weaknesses.accuracy.contains { $0.item == "th" })
        #expect(!report.weaknesses.speed.contains { $0.category == .key && $0.item == "v" })
        // Each cause is reported once: no pairs or words that merely contain
        // the missed key, and no slow "h" key on account of "th".
        #expect(report.weaknesses.accuracy.map(\.id) == ["accuracy.key.v"])
        #expect(report.weaknesses.speed.map(\.id) == ["speed.combination.th"])
    }

    @Test func cleanSteadyTypingHasNoWeaknesses() {
        let sessions = (0..<12).map { analyzed(simulatedSession(seed: UInt64($0)), hour: $0) }
        let report = ProgressAnalyzer.report(for: sessions)
        #expect(report.weaknesses.hasEnoughData)
        #expect(report.weaknesses.all.isEmpty)
        #expect(report.weaknessHistory.allSatisfy { $0.accuracy == 0 && $0.speed == 0 })
        #expect(report.formerWeaknesses.isEmpty)
    }

    @Test func historyStartsOnceThereIsEnoughDataAndTracksFirstFlagged() throws {
        let sessions = (0..<6).map { analyzed(simulatedSession(seed: UInt64($0), missedKeys: ["e"]), hour: $0) }
        let report = ProgressAnalyzer.report(for: sessions)

        // 300 keystrokes per session: the 600 minimum is met at session 2.
        #expect(report.weaknessHistory.map(\.index) == [2, 3, 4, 5, 6])
        #expect(report.weaknessHistory.map(\.date) == sessions.dropFirst().map(\.summary.date))
        #expect(report.weaknessHistory.last?.accuracy == report.weaknesses.accuracy.count)

        let firstFlagged = try #require(report.firstFlagged["accuracy.key.e"])
        #expect(sessions.map(\.summary.date).contains(firstFlagged))
        #expect(firstFlagged <= sessions[5].summary.date)
        #expect(Set(report.firstFlagged.keys) == Set(report.weaknesses.all.map(\.id)))
    }

    @Test func aProblemThatStopsIsNoLongerFlagged() throws {
        let troubled = (0..<10).map { analyzed(simulatedSession(seed: UInt64($0), missedKeys: ["e"]), hour: $0) }
        let clean = (10..<45).map { analyzed(simulatedSession(seed: UInt64($0)), hour: $0) }
        let report = ProgressAnalyzer.report(for: troubled + clean)

        #expect(report.weaknesses.all.isEmpty)
        #expect(report.weaknessHistory.last?.accuracy == 0)
        #expect((report.weaknessHistory.map(\.accuracy).max() ?? 0) > 0)

        let former = try #require(report.formerWeaknesses.first { $0.id == "accuracy.key.e" })
        #expect(former.weakness.value > 0)
        // Anything else once flagged was about the same key.
        #expect(report.formerWeaknesses.allSatisfy { $0.weakness.dimension == .accuracy && $0.weakness.item.hasSuffix("e") })
        #expect(former.lastFlagged >= troubled[9].summary.date)       // still flagged while troubled sessions were recent
        #expect(former.lastFlagged < clean[34].summary.date)
        #expect(report.firstFlagged.isEmpty)
    }

    @Test func onlyTheRecentWindowFeedsTheCurrentProfile() {
        let sessions = (0..<45).map { analyzed(simulatedSession(seed: UInt64($0)), hour: $0) }
        let report = ProgressAnalyzer.report(for: sessions)
        #expect(report.profile.sessions == ProgressAnalyzer.window)
        #expect(report.profile.keystrokes == ProgressAnalyzer.window * 300)
        #expect(report.profile == TypingProfile(sessions.suffix(30).map(\.analysis)))
    }

    @Test func summaryNumbersCoverTestsAndPractice() throws {
        // Faster typing later on; one practice session in the middle.
        var sessions = (0..<12).map { index in
            analyzed(simulatedSession(seed: UInt64(index), characters: 200 + index * 10, pace: 0.05), hour: index)
        }
        sessions.insert(analyzed(simulatedSession(seed: 99), kind: .practice(.commonWords), hour: 100), at: 5)
        let report = ProgressAnalyzer.report(for: sessions.shuffled())

        #expect(report.tests.count == 12)
        #expect(report.practiceSessions == 1)
        #expect(report.tests.map(\.date) == report.tests.map(\.date).sorted())      // oldest first, whatever the input order
        #expect(report.totalTime == 13 * 30)

        let best = try #require(report.personalBest)
        #expect(best.metrics.netWPM == 124)       // 310 characters / 5 / 0.5 min
        #expect(best.id == sessions.last?.summary.id)

        // Averages use the last 10 tests: 220...310 characters.
        var total = 0.0
        for index in 2..<12 { total += Double(200 + index * 10) / 5 / 0.5 }
        let expected = total / 10
        #expect(abs((report.recentWPM ?? 0) - expected) < 1e-9)
        #expect(report.recentAccuracy == 1)
        #expect(report.recentConsistency != nil)
    }

    @Test func earliestTestWinsAPersonalBestTie() {
        let sessions = (0..<3).map { analyzed(simulatedSession(seed: 7), hour: $0) }
        #expect(ProgressAnalyzer.report(for: sessions).personalBest?.id == sessions[0].summary.id)
    }
}

@Suite struct KeyboardLayoutTests {
    @Test func everyTypableCharacterBelongsToExactlyOneKey() {
        let keys = KeyboardLayout.rows.joined()
        var owners: [Character: Int] = [:]
        for key in keys {
            owners[key.base, default: 0] += 1
            if let shifted = key.shifted { owners[shifted, default: 0] += 1 }
        }
        #expect(owners.values.allSatisfy { $0 == 1 })

        // All printable ASCII except upper-case letters, which fold into lower case.
        let expected = (0x20...0x7E).map { Character(UnicodeScalar($0)) }.filter { !$0.isUppercase }
        #expect(Set(owners.keys) == Set(expected))
        #expect(KeyboardLayout.rows.count == KeyboardLayout.rowOffsets.count)
        #expect(KeyboardLayout.rows.map(\.count) == [13, 13, 11, 10, 1])
    }

    @Test func shiftedSymbolsCountTowardTheirPhysicalKey() throws {
        let profile = TypingProfile([analysisOf(keys: [
            keyStat("1", attempts: 10, errors: 1, latencies: [0.2, 0.2]),
            keyStat("!", attempts: 5, errors: 2, latencies: [0.4]),
            keyStat(";", attempts: 3),
            keyStat(":", attempts: 4, errors: 4),
            keyStat("a", attempts: 20, errors: 2, latencies: [0.1]),
            keyStat(" ", attempts: 50),
        ])])
        let heat = KeyboardLayout.heat(for: profile).joined()

        let one = try #require(heat.first { $0.key.base == "1" })
        #expect(one.attempts == 15)
        #expect(one.errors == 3)
        #expect(one.errorRate == 0.2)
        #expect(abs((one.meanLatency ?? 0) - 0.8 / 3) < 1e-12)

        #expect(heat.first { $0.key.base == ";" }?.errors == 4)
        #expect(heat.first { $0.key.base == ";" }?.attempts == 7)
        #expect(heat.first { $0.key.base == "a" }?.errorRate == 0.1)
        #expect(heat.first { $0.key.base == " " }?.attempts == 50)

        let untouched = try #require(heat.first { $0.key.base == "q" })
        #expect(untouched.attempts == 0)
        #expect(untouched.errorRate == nil && untouched.meanLatency == nil)
        // Nothing is lost or double counted.
        #expect(heat.reduce(0) { $0 + $1.attempts } == profile.keystrokes)
    }
}

@MainActor
@Suite struct StoredAnalysisTests {
    @Test func storedSessionsComeBackAnalysedOldestFirst() throws {
        let store = try StatisticsStore.inMemory()
        let sessions = (0..<5).map { simulatedSession(seed: UInt64($0), missedKeys: ["e"]) }
        for (index, session) in sessions.enumerated().reversed() {
            try store.record(session, kind: index == 2 ? .practice(.sentences) : .test, timeLimit: 30,
                             date: Date(timeIntervalSince1970: Double(index) * 1_000))
        }

        let analyzed = store.analyzedSessions()
        #expect(analyzed.map(\.analysis) == sessions.map(SessionAnalyzer.analyze))
        #expect(analyzed.map(\.summary.kind) == [.test, .test, .practice(.sentences), .test, .test])

        // A limit keeps the most recent sessions.
        #expect(store.analyzedSessions(limit: 2).map(\.analysis) == sessions.suffix(2).map(SessionAnalyzer.analyze))

        let id = try #require(store.summaries.first?.id)
        #expect(try store.analysis(for: id) == SessionAnalyzer.analyze(sessions[4]))
        #expect(try store.analysis(for: UUID()) == nil)

        // The report built from storage matches one built directly.
        let direct = ProgressAnalyzer.report(for: analyzed)
        #expect(direct.tests.count == 4)
        #expect(direct.practiceSessions == 1)
        #expect(direct.weaknesses.accuracy.contains { $0.id == "accuracy.key.e" })
    }
}
