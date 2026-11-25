import Foundation
import Observation
import SwiftData

/// One saved training event. Hand-written equivalent of an `@Model` class,
/// for the same reason as `SessionRecord`: the macro needs Xcode.
///
/// Lives in its own store file, separate from session history, so adding
/// Muscle Memory never migrates or touches existing data.
public final class TrainingRecord {
    public var id: UUID {
        get { read(\.id) }
        set { write(\.id, newValue) }
    }
    public var date: Date {
        get { read(\.date) }
        set { write(\.date, newValue) }
    }
    /// `TrainingCategory.rawValue`.
    public var category: String {
        get { read(\.category) }
        set { write(\.category, newValue) }
    }
    /// `TrainingStage.rawValue`.
    public var stage: Int {
        get { read(\.stage) }
        set { write(\.stage, newValue) }
    }
    /// "round" or "skip".
    public var kind: String {
        get { read(\.kind) }
        set { write(\.kind, newValue) }
    }
    /// Round accuracy, or 0 for a skip. Kept as a column for quick queries.
    public var accuracy: Double {
        get { read(\.accuracy) }
        set { write(\.accuracy, newValue) }
    }
    /// JSON-encoded `RoundResult`; empty for a skip.
    public var payload: Data {
        get { read(\.payload) }
        set { write(\.payload, newValue) }
    }

    init(_ event: TrainingEvent) throws {
        self.id = event.id
        self.date = event.date
        self.category = event.category.rawValue
        self.stage = event.stage.rawValue
        switch event.kind {
        case .round(let result):
            self.kind = "round"
            self.accuracy = result.accuracy
            self.payload = try JSONEncoder().encode(result)
        case .skip:
            self.kind = "skip"
            self.accuracy = 0
            self.payload = Data()
        }
    }

    /// A Finger Focus round. Stored in the same table, told apart by a
    /// category of the form "fingerFocus.leftPinky", so no schema change is
    /// needed and lesson history never sees these rows.
    init(_ event: FingerFocusEvent) throws {
        self.id = event.id
        self.date = event.date
        self.category = Self.fingerFocusPrefix + event.target.rawValue
        self.stage = event.level.rawValue
        self.kind = "round"
        self.accuracy = event.result.accuracy
        self.payload = try JSONEncoder().encode(event.result)
    }

    static let fingerFocusPrefix = "fingerFocus."
    static let assessmentPrefix = "fingerAssessment."
    static let mechanicsPrefix = "mechanics."

    /// A Typing Mechanics round: aggregates and timing summaries only.
    init(_ event: MechanicsEvent) throws {
        self.id = event.id
        self.date = event.date
        self.category = Self.mechanicsPrefix + event.drill.rawValue
        self.stage = event.drill.stage
        self.kind = "round"
        self.accuracy = event.result.characterAccuracy
        self.payload = try JSONEncoder().encode(event.result)
    }

    static let keyRepetitionPrefix = "keyRepetition."

    /// A completed Key Repetition session, in the same table: category
    /// "keyRepetition.p", stage = the goal. No schema change, and no other
    /// history reads these rows (each reader matches its own prefix).
    init(_ event: KeyRepetitionEvent) throws {
        self.id = event.id
        self.date = event.date
        self.category = Self.keyRepetitionPrefix + event.result.letter
        self.stage = event.result.goal
        self.kind = "round"
        self.accuracy = event.result.accuracy
        self.payload = try JSONEncoder().encode(event.result)
    }

    var keyRepetitionEvent: KeyRepetitionEvent? {
        guard category.hasPrefix(Self.keyRepetitionPrefix), kind == "round",
              let result = try? JSONDecoder().decode(KeyRepetitionResult.self, from: payload) else { return nil }
        return KeyRepetitionEvent(id: id, date: date, result: result)
    }

    static let dailyFlowPrefix = "dailyFlow."

    /// One finished Daily Flow passage, in the same table: category
    /// "dailyFlow.warmUp", stage = the planned minutes. No schema change.
    init(_ event: DailyFlowEvent) throws {
        self.id = event.id
        self.date = event.date
        self.category = Self.dailyFlowPrefix + event.round.segment.rawValue
        self.stage = event.round.plannedMinutes
        self.kind = "round"
        self.accuracy = event.round.result.accuracy
        self.payload = try JSONEncoder().encode(event.round)
    }

    var dailyFlowEvent: DailyFlowEvent? {
        guard category.hasPrefix(Self.dailyFlowPrefix), kind == "round",
              let round = try? JSONDecoder().decode(DailyFlowRound.self, from: payload) else { return nil }
        return DailyFlowEvent(id: id, date: date, round: round)
    }

    var mechanicsEvent: MechanicsEvent? {
        guard category.hasPrefix(Self.mechanicsPrefix), kind == "round",
              let drill = MechanicsDrill(rawValue: String(category.dropFirst(Self.mechanicsPrefix.count))),
              let result = try? JSONDecoder().decode(MechanicsRoundResult.self, from: payload) else { return nil }
        return MechanicsEvent(id: id, date: date, drill: drill, result: result)
    }

    /// A finger check (baseline or retest), stored the same way.
    init(_ event: FingerAssessmentEvent) throws {
        self.id = event.id
        self.date = event.date
        self.category = Self.assessmentPrefix + event.target.rawValue
        self.stage = 0
        self.kind = "assessment"
        self.accuracy = event.result.accuracy ?? 0
        self.payload = try JSONEncoder().encode(event.result)
    }

    var assessmentEvent: FingerAssessmentEvent? {
        guard category.hasPrefix(Self.assessmentPrefix), kind == "assessment",
              let target = FingerFocusTarget(rawValue: String(category.dropFirst(Self.assessmentPrefix.count))),
              let result = try? JSONDecoder().decode(FingerAssessmentResult.self, from: payload) else { return nil }
        return FingerAssessmentEvent(id: id, date: date, target: target, result: result)
    }

    var fingerFocusEvent: FingerFocusEvent? {
        guard category.hasPrefix(Self.fingerFocusPrefix), kind == "round",
              let target = FingerFocusTarget(rawValue: String(category.dropFirst(Self.fingerFocusPrefix.count))),
              let level = FingerFocusLevel(rawValue: stage),
              let result = try? JSONDecoder().decode(RoundResult.self, from: payload) else { return nil }
        return FingerFocusEvent(id: id, date: date, target: target, level: level, result: result)
    }

    var event: TrainingEvent? {
        guard let category = TrainingCategory(rawValue: category),
              let stage = TrainingStage(rawValue: stage) else { return nil }
        switch kind {
        case "skip":
            return TrainingEvent(id: id, date: date, category: category, stage: stage, kind: .skip)
        case "round":
            guard let result = try? JSONDecoder().decode(RoundResult.self, from: payload) else { return nil }
            return TrainingEvent(id: id, date: date, category: category, stage: stage, kind: .round(result))
        default:
            return nil
        }
    }

    // MARK: SwiftData plumbing (what @Model would generate)

    private var _$backingData: any BackingData<TrainingRecord> = TrainingRecord.createBackingData()
    private let _$observationRegistrar = ObservationRegistrar()

    public var persistentBackingData: any BackingData<TrainingRecord> {
        get { _$backingData }
        set { _$backingData = newValue }
    }

    public init(backingData: any BackingData<TrainingRecord>) {
        _$backingData = backingData
    }

    public static var schemaMetadata: [Schema.PropertyMetadata] {
        [
            .init(name: "id", keypath: \TrainingRecord.id, defaultValue: nil, metadata: nil),
            .init(name: "date", keypath: \TrainingRecord.date, defaultValue: nil, metadata: nil),
            .init(name: "category", keypath: \TrainingRecord.category, defaultValue: nil, metadata: nil),
            .init(name: "stage", keypath: \TrainingRecord.stage, defaultValue: nil, metadata: nil),
            .init(name: "kind", keypath: \TrainingRecord.kind, defaultValue: nil, metadata: nil),
            .init(name: "accuracy", keypath: \TrainingRecord.accuracy, defaultValue: nil, metadata: nil),
            .init(name: "payload", keypath: \TrainingRecord.payload, defaultValue: nil, metadata: nil),
        ]
    }

    private func read<Value: Codable>(_ keyPath: KeyPath<TrainingRecord, Value>) -> Value {
        _$observationRegistrar.access(self, keyPath: keyPath)
        return getValue(forKey: keyPath)
    }

    private func write<Value: Codable>(_ keyPath: ReferenceWritableKeyPath<TrainingRecord, Value>, _ value: Value) {
        _$observationRegistrar.withMutation(of: self, keyPath: keyPath) {
            setValue(forKey: keyPath, to: value)
        }
    }
}

extension TrainingRecord: PersistentModel {}
extension TrainingRecord: Observable {}

/// Local storage for Muscle Memory training. Value types only leave this class.
@MainActor
@Observable
public final class TrainingStore {
    /// Every saved event, oldest first.
    public private(set) var events: [TrainingEvent] = []
    /// Every saved Finger Focus round, oldest first.
    public private(set) var fingerFocusEvents: [FingerFocusEvent] = []
    /// Every saved finger check, oldest first.
    public private(set) var assessmentEvents: [FingerAssessmentEvent] = []
    /// Every saved Typing Mechanics round, oldest first.
    public private(set) var mechanicsEvents: [MechanicsEvent] = []
    /// Every completed Key Repetition session, oldest first.
    public private(set) var keyRepetitionEvents: [KeyRepetitionEvent] = []
    /// Every finished Daily Flow passage, oldest first.
    public private(set) var dailyFlowEvents: [DailyFlowEvent] = []

    @ObservationIgnored private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    public init(container: ModelContainer) throws {
        self.container = container
        try reload()
    }

    public static func inMemory() throws -> TrainingStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try TrainingStore(container: ModelContainer(for: TrainingRecord.self, configurations: configuration))
    }

    public static func onDisk(at url: URL) throws -> TrainingStore {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: url)
        return try TrainingStore(container: ModelContainer(for: TrainingRecord.self, configurations: configuration))
    }

    /// `~/Library/Application Support/Keyflow/MuscleMemory.store`
    public static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "Keyflow/MuscleMemory.store")
    }

    public func record(_ event: TrainingEvent) throws {
        let record = try TrainingRecord(event)
        context.insert(record)
        do {
            try context.save()
        } catch {
            context.delete(record)
            throw error
        }
        let index = events.lastIndex { $0.date <= event.date }.map { $0 + 1 } ?? 0
        events.insert(event, at: index)
    }

    public func record(_ event: FingerFocusEvent) throws {
        let record = try TrainingRecord(event)
        context.insert(record)
        do {
            try context.save()
        } catch {
            context.delete(record)
            throw error
        }
        let index = fingerFocusEvents.lastIndex { $0.date <= event.date }.map { $0 + 1 } ?? 0
        fingerFocusEvents.insert(event, at: index)
    }

    public func record(_ event: FingerAssessmentEvent) throws {
        let record = try TrainingRecord(event)
        context.insert(record)
        do {
            try context.save()
        } catch {
            context.delete(record)
            throw error
        }
        let index = assessmentEvents.lastIndex { $0.date <= event.date }.map { $0 + 1 } ?? 0
        assessmentEvents.insert(event, at: index)
    }

    public func record(_ event: MechanicsEvent) throws {
        let record = try TrainingRecord(event)
        context.insert(record)
        do {
            try context.save()
        } catch {
            context.delete(record)
            throw error
        }
        let index = mechanicsEvents.lastIndex { $0.date <= event.date }.map { $0 + 1 } ?? 0
        mechanicsEvents.insert(event, at: index)
    }

    public func record(_ event: KeyRepetitionEvent) throws {
        let record = try TrainingRecord(event)
        context.insert(record)
        do {
            try context.save()
        } catch {
            context.delete(record)
            throw error
        }
        let index = keyRepetitionEvents.lastIndex { $0.date <= event.date }.map { $0 + 1 } ?? 0
        keyRepetitionEvents.insert(event, at: index)
    }

    public func record(_ event: DailyFlowEvent) throws {
        let record = try TrainingRecord(event)
        context.insert(record)
        do {
            try context.save()
        } catch {
            context.delete(record)
            throw error
        }
        let index = dailyFlowEvents.lastIndex { $0.date <= event.date }.map { $0 + 1 } ?? 0
        dailyFlowEvents.insert(event, at: index)
    }

    public func deleteAll() throws {
        for record in try context.fetch(FetchDescriptor<TrainingRecord>()) { context.delete(record) }
        try context.save()
        try reload()
    }

    private func reload() throws {
        let records = try context.fetch(FetchDescriptor<TrainingRecord>(sortBy: [SortDescriptor(\.date)]))
        events = records.compactMap(\.event)
        fingerFocusEvents = records.compactMap(\.fingerFocusEvent)
        assessmentEvents = records.compactMap(\.assessmentEvent)
        mechanicsEvents = records.compactMap(\.mechanicsEvent)
        keyRepetitionEvents = records.compactMap(\.keyRepetitionEvent)
        dailyFlowEvents = records.compactMap(\.dailyFlowEvent)
    }
}
