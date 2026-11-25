import Foundation
import KeyflowCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings ▸ Data & Privacy ▸ Export. A JSON file of the user's training
/// results, versioned so later Keyflow versions can read older exports.
///
/// Schema version 1 (documented in Docs/export-format.md):
/// - `sessions`: every saved Practice and Test session's headline numbers.
///   Keystroke logs and the typed text are **not** included: Custom Text can
///   contain anything the user pasted.
/// - `lessons`, `fingerFocus`, `fingerChecks`, `typingMechanics`,
///   `keyRepetition`, `dailyFlow` (added later, additive): Learn
///   results, as Keyflow stores them (counts, accuracies, timing summaries,
///   and the generated exercise text).
struct KeyflowExport: Encodable {
    static let schemaVersion = 1

    struct Session: Encodable {
        let id: UUID
        let date: Date
        let kind: String
        let timeLimitSeconds: Int
        let elapsedSeconds: Double
        let netWPM: Double
        let rawWPM: Double
        let accuracy: Double
        let consistency: Double?
        let keystrokes: Int
        let correctKeystrokes: Int
        let backspaces: Int
    }

    struct Lesson: Encodable {
        let id: UUID
        let date: Date
        let category: String
        let stage: Int
        let kind: String
        let result: RoundResult?
    }

    struct FingerRound: Encodable {
        let id: UUID
        let date: Date
        let target: String
        let level: Int
        let result: RoundResult
    }

    struct FingerCheck: Encodable {
        let id: UUID
        let date: Date
        let target: String
        let result: FingerAssessmentResult
    }

    struct MechanicsRound: Encodable {
        let id: UUID
        let date: Date
        let drill: String
        let result: MechanicsRoundResult
    }

    struct KeyRepetitionSession: Encodable {
        let id: UUID
        let date: Date
        let key: String
        let goal: Int
        let mode: String
        let correct: Int
        let incorrect: Int
        /// correct ÷ (correct + incorrect).
        let accuracy: Double
        /// Seconds from the first counted press, without pauses.
        let durationSeconds: Double
    }

    struct DailyFlowPassage: Encodable {
        let id: UUID
        let date: Date
        let sessionID: UUID
        let segment: String
        let plannedMinutes: Int
        let activeSeconds: Double
        let hints: Int
        let result: RoundResult
    }

    let schemaVersion = Self.schemaVersion
    let app = "Keyflow"
    let appVersion: String
    let exportedAt: Date
    let sessions: [Session]
    let lessons: [Lesson]
    let fingerFocus: [FingerRound]
    let fingerChecks: [FingerCheck]
    let typingMechanics: [MechanicsRound]
    let keyRepetition: [KeyRepetitionSession]
    let dailyFlow: [DailyFlowPassage]

    @MainActor
    init(store: StatisticsStore?, trainingStore: TrainingStore?, now: Date = .now) {
        appVersion = AppInfo.versionDescription
        exportedAt = now
        sessions = (store?.summaries ?? []).reversed().map { s in
            Session(id: s.id, date: s.date, kind: s.kind.storageKey, timeLimitSeconds: s.timeLimit,
                    elapsedSeconds: s.metrics.elapsed, netWPM: s.metrics.netWPM, rawWPM: s.metrics.rawWPM,
                    accuracy: s.metrics.accuracy, consistency: s.consistency, keystrokes: s.metrics.totalKeystrokes,
                    correctKeystrokes: s.metrics.correctKeystrokes, backspaces: s.metrics.backspaces)
        }
        lessons = (trainingStore?.events ?? []).map { e in
            Lesson(id: e.id, date: e.date, category: e.category.rawValue, stage: e.stage.rawValue,
                   kind: e.round == nil ? "skip" : "round", result: e.round)
        }
        fingerFocus = (trainingStore?.fingerFocusEvents ?? []).map {
            FingerRound(id: $0.id, date: $0.date, target: $0.target.rawValue, level: $0.level.rawValue, result: $0.result)
        }
        fingerChecks = (trainingStore?.assessmentEvents ?? []).map {
            FingerCheck(id: $0.id, date: $0.date, target: $0.target.rawValue, result: $0.result)
        }
        typingMechanics = (trainingStore?.mechanicsEvents ?? []).map {
            MechanicsRound(id: $0.id, date: $0.date, drill: $0.drill.rawValue, result: $0.result)
        }
        keyRepetition = (trainingStore?.keyRepetitionEvents ?? []).map {
            KeyRepetitionSession(id: $0.id, date: $0.date, key: $0.result.letter, goal: $0.result.goal,
                                 mode: $0.result.mode.rawValue, correct: $0.result.correct,
                                 incorrect: $0.result.incorrect, accuracy: $0.result.accuracy,
                                 durationSeconds: $0.result.duration)
        }
        dailyFlow = (trainingStore?.dailyFlowEvents ?? []).map {
            DailyFlowPassage(id: $0.id, date: $0.date, sessionID: $0.round.sessionID, segment: $0.round.segment.rawValue,
                             plannedMinutes: $0.round.plannedMinutes, activeSeconds: $0.round.activeSeconds,
                             hints: $0.round.hints, result: $0.round.result)
        }
    }

    func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

/// The export as a document for the native save panel.
struct ExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Version information, read from the application bundle.
enum AppInfo {
    static var name: String { string("CFBundleDisplayName") ?? string("CFBundleName") ?? "Keyflow" }
    static var version: String { string("CFBundleShortVersionString") ?? "Unknown" }
    static var build: String { string("CFBundleVersion") ?? "Unknown" }
    /// The release channel from the build, such as "Beta 1"; nil for a regular release.
    static var channel: String? { string("KeyflowReleaseChannel").flatMap { $0.isEmpty ? nil : $0 } }
    /// "1.0 Beta 1", or just "1.0".
    static var displayVersion: String { [version, channel].compactMap { $0 }.joined(separator: " ") }
    static var versionDescription: String { "\(displayVersion) (\(build))" }

    /// The beta feedback address, set at build time (Scripts/release-beta.sh).
    /// Nil when the build has none; then no feedback button is shown.
    static var feedbackEmail: String? {
        string("KeyflowFeedbackEmail").flatMap { $0.contains("@") ? $0 : nil }
    }

    /// A new email to the feedback address, with the versions filled in.
    static var feedbackMailURL: URL? { feedbackEmail.flatMap(feedbackMailURL(to:)) }

    static func feedbackMailURL(to address: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Keyflow \(displayVersion) feedback"),
            URLQueryItem(name: "body", value: """
                What happened (bug, UI issue, typing accuracy, suggestion or installation):


                Steps to reproduce, if it's a problem:


                What you expected instead:


                —
                Keyflow \(versionDescription)
                \(platform)
                """),
        ]
        return components.url
    }

    static var platform: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let arch = "Apple silicon"
        #else
        let arch = "Intel"
        #endif
        return "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · \(arch)"
    }

    private static func string(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
