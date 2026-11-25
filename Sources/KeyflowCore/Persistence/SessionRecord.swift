import Foundation
import Observation
import SwiftData

/// One saved session: headline numbers as columns, the full keystroke log as
/// a JSON payload.
///
/// This is the hand-written equivalent of an `@Model` class. The `@Model`
/// macro needs a compiler plugin that ships only with Xcode, and this project
/// must also build with the Command Line Tools alone. If you add a property,
/// add its accessor *and* its `schemaMetadata` entry.
public final class SessionRecord {
    public var id: UUID {
        get { read(\.id) }
        set { write(\.id, newValue) }
    }
    public var date: Date {
        get { read(\.date) }
        set { write(\.date, newValue) }
    }
    /// `SessionKind.storageKey`.
    public var kind: String {
        get { read(\.kind) }
        set { write(\.kind, newValue) }
    }
    /// Configured session length in seconds.
    public var timeLimit: Int {
        get { read(\.timeLimit) }
        set { write(\.timeLimit, newValue) }
    }
    public var elapsed: Double {
        get { read(\.elapsed) }
        set { write(\.elapsed, newValue) }
    }
    public var netWPM: Double {
        get { read(\.netWPM) }
        set { write(\.netWPM, newValue) }
    }
    public var rawWPM: Double {
        get { read(\.rawWPM) }
        set { write(\.rawWPM, newValue) }
    }
    public var accuracy: Double {
        get { read(\.accuracy) }
        set { write(\.accuracy, newValue) }
    }
    public var consistency: Double? {
        get { read(\.consistency) }
        set { write(\.consistency, newValue) }
    }
    public var totalKeystrokes: Int {
        get { read(\.totalKeystrokes) }
        set { write(\.totalKeystrokes, newValue) }
    }
    public var correctKeystrokes: Int {
        get { read(\.correctKeystrokes) }
        set { write(\.correctKeystrokes, newValue) }
    }
    public var backspaces: Int {
        get { read(\.backspaces) }
        set { write(\.backspaces, newValue) }
    }
    public var correctCharacters: Int {
        get { read(\.correctCharacters) }
        set { write(\.correctCharacters, newValue) }
    }
    public var incorrectCharacters: Int {
        get { read(\.incorrectCharacters) }
        set { write(\.incorrectCharacters, newValue) }
    }
    /// JSON-encoded `SessionPayload`.
    public var payload: Data {
        get { read(\.payload) }
        set { write(\.payload, newValue) }
    }

    public init(id: UUID, date: Date, kind: SessionKind, timeLimit: Int,
                metrics: PerformanceMetrics, consistency: Double?, payload: Data) {
        self.id = id
        self.date = date
        self.kind = kind.storageKey
        self.timeLimit = timeLimit
        self.elapsed = metrics.elapsed
        self.netWPM = metrics.netWPM
        self.rawWPM = metrics.rawWPM
        self.accuracy = metrics.accuracy
        self.consistency = consistency
        self.totalKeystrokes = metrics.totalKeystrokes
        self.correctKeystrokes = metrics.correctKeystrokes
        self.backspaces = metrics.backspaces
        self.correctCharacters = metrics.correctCharacters
        self.incorrectCharacters = metrics.incorrectCharacters
        self.payload = payload
    }

    // MARK: SwiftData plumbing (what @Model would generate)

    private var _$backingData: any BackingData<SessionRecord> = SessionRecord.createBackingData()
    private let _$observationRegistrar = ObservationRegistrar()

    public var persistentBackingData: any BackingData<SessionRecord> {
        get { _$backingData }
        set { _$backingData = newValue }
    }

    public init(backingData: any BackingData<SessionRecord>) {
        _$backingData = backingData
    }

    public static var schemaMetadata: [Schema.PropertyMetadata] {
        [
            .init(name: "id", keypath: \SessionRecord.id, defaultValue: nil, metadata: nil),
            .init(name: "date", keypath: \SessionRecord.date, defaultValue: nil, metadata: nil),
            .init(name: "kind", keypath: \SessionRecord.kind, defaultValue: nil, metadata: nil),
            .init(name: "timeLimit", keypath: \SessionRecord.timeLimit, defaultValue: nil, metadata: nil),
            .init(name: "elapsed", keypath: \SessionRecord.elapsed, defaultValue: nil, metadata: nil),
            .init(name: "netWPM", keypath: \SessionRecord.netWPM, defaultValue: nil, metadata: nil),
            .init(name: "rawWPM", keypath: \SessionRecord.rawWPM, defaultValue: nil, metadata: nil),
            .init(name: "accuracy", keypath: \SessionRecord.accuracy, defaultValue: nil, metadata: nil),
            .init(name: "consistency", keypath: \SessionRecord.consistency, defaultValue: nil, metadata: nil),
            .init(name: "totalKeystrokes", keypath: \SessionRecord.totalKeystrokes, defaultValue: nil, metadata: nil),
            .init(name: "correctKeystrokes", keypath: \SessionRecord.correctKeystrokes, defaultValue: nil, metadata: nil),
            .init(name: "backspaces", keypath: \SessionRecord.backspaces, defaultValue: nil, metadata: nil),
            .init(name: "correctCharacters", keypath: \SessionRecord.correctCharacters, defaultValue: nil, metadata: nil),
            .init(name: "incorrectCharacters", keypath: \SessionRecord.incorrectCharacters, defaultValue: nil, metadata: nil),
            .init(name: "payload", keypath: \SessionRecord.payload, defaultValue: nil, metadata: nil),
        ]
    }

    private func read<Value: Codable>(_ keyPath: KeyPath<SessionRecord, Value>) -> Value {
        _$observationRegistrar.access(self, keyPath: keyPath)
        return getValue(forKey: keyPath)
    }

    private func write<Value: Codable>(_ keyPath: ReferenceWritableKeyPath<SessionRecord, Value>, _ value: Value) {
        _$observationRegistrar.withMutation(of: self, keyPath: keyPath) {
            setValue(forKey: keyPath, to: value)
        }
    }
}

extension SessionRecord: PersistentModel {}
extension SessionRecord: Observable {}

/// The part of a session too detailed for columns.
struct SessionPayload: Codable {
    var target: String
    var typed: String
    var events: [TypingEvent]
}

extension TypingEvent: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind = "k", time = "t", position = "p", expected = "e", typed = "c"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let expected = try container.decode(String.self, forKey: .expected)
        let typed = try container.decode(String.self, forKey: .typed)
        guard expected.count == 1, typed.count == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .expected, in: container,
                                                   debugDescription: "Expected single characters")
        }
        self.init(
            kind: try container.decode(Int.self, forKey: .kind) == 0 ? .insert : .backspace,
            time: try container.decode(Double.self, forKey: .time),
            position: try container.decode(Int.self, forKey: .position),
            expected: expected.first!,
            typed: typed.first!
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind == .insert ? 0 : 1, forKey: .kind)
        try container.encode(time, forKey: .time)
        try container.encode(position, forKey: .position)
        try container.encode(String(expected), forKey: .expected)
        try container.encode(String(typed), forKey: .typed)
    }
}
