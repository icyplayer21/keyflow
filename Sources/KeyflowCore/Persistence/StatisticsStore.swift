import Foundation
import Observation
import SwiftData

/// The headline numbers of a saved session, as a plain value.
public struct SessionSummary: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let date: Date
    public let kind: SessionKind
    /// Configured session length in seconds.
    public let timeLimit: Int
    public let metrics: PerformanceMetrics
    public let consistency: Double?

    public init(id: UUID, date: Date, kind: SessionKind, timeLimit: Int,
                metrics: PerformanceMetrics, consistency: Double?) {
        self.id = id
        self.date = date
        self.kind = kind
        self.timeLimit = timeLimit
        self.metrics = metrics
        self.consistency = consistency
    }
}

/// Local, offline storage for every completed session. The rest of the app
/// deals only in value types; SwiftData objects never leave this class.
@MainActor
@Observable
public final class StatisticsStore {
    /// All saved sessions, newest first.
    public private(set) var summaries: [SessionSummary] = []

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var identifiers: [UUID: PersistentIdentifier] = [:]
    @ObservationIgnored private var analyses: [UUID: SessionAnalysis] = [:]
    @ObservationIgnored private var fingerCache: [UUID: FingerObservations] = [:]
    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) throws {
        self.container = container
        try reload()
    }

    public static func inMemory() throws -> StatisticsStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try StatisticsStore(container: ModelContainer(for: SessionRecord.self, configurations: configuration))
    }

    public static func onDisk(at url: URL) throws -> StatisticsStore {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: url)
        return try StatisticsStore(container: ModelContainer(for: SessionRecord.self, configurations: configuration))
    }

    /// `~/Library/Application Support/Keyflow/Keyflow.store`
    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Keyflow/Keyflow.store")
    }

    // MARK: Writing

    /// Saves a finished session and returns its summary.
    @discardableResult
    public func record(_ session: TypingSession, kind: SessionKind, timeLimit: Int,
                       date: Date = .now, id: UUID = UUID()) throws -> SessionSummary {
        let payload = SessionPayload(target: String(session.target), typed: String(session.typed), events: session.events)
        let record = SessionRecord(
            id: id,
            date: date,
            kind: kind,
            timeLimit: timeLimit,
            metrics: PerformanceCalculator.metrics(for: session),
            consistency: SessionAnalyzer.consistency(of: session),
            payload: try JSONEncoder().encode(payload)
        )
        context.insert(record)
        do {
            try context.save()
        } catch {
            context.delete(record)
            throw error
        }
        let summary = Self.summary(of: record)!
        identifiers[id] = record.persistentModelID
        summaries.append(summary)
        summaries.sort { $0.date > $1.date }
        return summary
    }

    public func deleteAll() throws {
        for record in try context.fetch(FetchDescriptor<SessionRecord>()) { context.delete(record) }
        try context.save()
        try reload()
    }

    // MARK: Reading

    /// The full keystroke log of a saved session.
    public func session(for id: UUID) throws -> TypingSession? {
        guard let identifier = identifiers[id],
              let record = context.model(for: identifier) as? SessionRecord else { return nil }
        let payload = try JSONDecoder().decode(SessionPayload.self, from: record.payload)
        return TypingSession(
            target: Array(payload.target),
            typed: Array(payload.typed),
            events: payload.events,
            elapsed: record.elapsed,
            timeLimit: TimeInterval(record.timeLimit),
            isFinished: true
        )
    }

    /// The keystroke analysis of a saved session. Computed once, then cached.
    public func analysis(for id: UUID) throws -> SessionAnalysis? {
        if let cached = analyses[id] { return cached }
        guard let session = try session(for: id) else { return nil }
        let analysis = SessionAnalyzer.analyze(session)
        analyses[id] = analysis
        return analysis
    }

    /// The most recent `limit` sessions with their analyses, oldest first.
    /// A session whose log cannot be read is skipped.
    public func analyzedSessions(limit: Int = 200) -> [AnalyzedSession] {
        summaries.prefix(limit).reversed().compactMap { summary in
            guard let analysis = try? analysis(for: summary.id) else { return nil }
            return AnalyzedSession(summary: summary, analysis: analysis)
        }
    }

    /// Per-finger observations of the most recent `limit` sessions, oldest
    /// first. Computed from the saved keystroke logs, then cached.
    public func fingerObservations(limit: Int = 200) -> [(summary: SessionSummary, observations: FingerObservations)] {
        summaries.prefix(limit).reversed().compactMap { summary in
            if let cached = fingerCache[summary.id] { return (summary, cached) }
            guard let session = try? session(for: summary.id) else { return nil }
            let observations = FingerAnalyzer.observe(session)
            fingerCache[summary.id] = observations
            return (summary, observations)
        }
    }

    public func summaries(of kind: SessionKind, timeLimit: Int? = nil) -> [SessionSummary] {
        summaries.filter { $0.kind == kind && (timeLimit == nil || $0.timeLimit == timeLimit) }
    }

    /// The saved session with the highest net WPM (earliest wins a tie).
    public func personalBest(of kind: SessionKind, timeLimit: Int? = nil) -> SessionSummary? {
        summaries(of: kind, timeLimit: timeLimit)
            .max { ($0.metrics.netWPM, $1.date) < ($1.metrics.netWPM, $0.date) }
    }

    // MARK: Private

    private func reload() throws {
        let records = try context.fetch(FetchDescriptor<SessionRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
        identifiers = [:]
        analyses = [:]
        fingerCache = [:]
        summaries = records.compactMap { record in
            guard let summary = Self.summary(of: record) else { return nil }
            identifiers[summary.id] = record.persistentModelID
            return summary
        }
    }

    private static func summary(of record: SessionRecord) -> SessionSummary? {
        guard let kind = SessionKind(storageKey: record.kind) else { return nil }
        return SessionSummary(
            id: record.id,
            date: record.date,
            kind: kind,
            timeLimit: record.timeLimit,
            metrics: PerformanceMetrics(
                netWPM: record.netWPM,
                rawWPM: record.rawWPM,
                accuracy: record.accuracy,
                elapsed: record.elapsed,
                totalKeystrokes: record.totalKeystrokes,
                correctKeystrokes: record.correctKeystrokes,
                incorrectKeystrokes: record.totalKeystrokes - record.correctKeystrokes,
                backspaces: record.backspaces,
                correctCharacters: record.correctCharacters,
                incorrectCharacters: record.incorrectCharacters
            ),
            consistency: record.consistency
        )
    }
}
