#if canImport(SwiftData)
import Foundation
import SwiftData

public struct SwiftDataTrainingProgramRepository: Sendable {
    public let container: ModelContainer
    private let trainingPlanRepository: SwiftDataTrainingPlanRepository?

    public init(
        container: ModelContainer,
        trainingPlanRepository: SwiftDataTrainingPlanRepository? = nil
    ) {
        self.container = container
        self.trainingPlanRepository = trainingPlanRepository
    }

    @MainActor
    public func loadPrograms() throws -> [TrainingProgramDefinition] {
        let context = ModelContext(container)
        try hydrateCatalogIfNeeded(in: context)
        return try fetchProgramRecords(in: context)
            .compactMap(TrainingProgramDefinition.init(record:))
            .sorted(by: TrainingProgramCatalog.sortingCatalogFirst)
    }

    @MainActor
    public func createProgram(_ definition: TrainingProgramDefinition) throws {
        let context = ModelContext(container)
        guard try record(for: definition.id, in: context) == nil else {
            try updateProgram(definition)
            return
        }
        context.insert(TrainingProgramRecord(definition: definition))
        try context.save()
    }

    @MainActor
    public func updateProgram(_ definition: TrainingProgramDefinition) throws {
        let context = ModelContext(container)
        if let existing = try record(for: definition.id, in: context) {
            existing.apply(definition)
            existing.updatedAt = .now
        } else {
            context.insert(TrainingProgramRecord(definition: definition))
        }
        try context.save()
    }

    @MainActor
    public func deleteProgram(identifier: String) throws {
        let context = ModelContext(container)
        guard let existing = try record(for: identifier, in: context) else { return }
        context.delete(existing)
        try context.save()
    }

    @MainActor
    @discardableResult
    public func assignProgram(
        catalogIdentifier: String,
        startDate: Date = .now,
        calendar: Calendar = .current
    ) throws -> ActiveTrainingProgramContext {
        let context = ModelContext(container)
        try hydrateCatalogIfNeeded(in: context)
        guard let selected = try record(for: catalogIdentifier, in: context),
              let definition = TrainingProgramDefinition(record: selected),
              let activeContext = definition.scheduledSession(on: startDate, assignedAt: startDate, calendar: calendar)
        else {
            throw TrainingProgramRepositoryError.programNotFound(catalogIdentifier)
        }

        let selectedModelID = selected.persistentModelID
        let records = try fetchProgramRecords(in: context)
        for record in records {
            let isSelected = record.persistentModelID == selectedModelID
            record.isActive = isSelected
            record.assignedAt = isSelected ? startDate : record.assignedAt
            record.currentWeek = isSelected ? activeContext.weekNumber : record.currentWeek
            record.currentDay = isSelected ? activeContext.dayNumber : record.currentDay
            record.updatedAt = .now
        }

        try trainingPlanRepository?.stageUpsertPlan(definition.weeklyWorkouts(startingOn: startDate, calendar: calendar), in: context)
        try context.save()
        return activeContext
    }

    @MainActor
    public func activeProgramContext(on date: Date = .now, calendar: Calendar = .current) throws -> ActiveTrainingProgramContext? {
        let context = ModelContext(container)
        guard let record = try activeProgramRecord(in: context),
              let definition = TrainingProgramDefinition(record: record)
        else {
            return nil
        }
        let assignedAt = record.assignedAt ?? record.updatedAt
        return definition.scheduledSession(on: date, assignedAt: assignedAt, calendar: calendar)
    }

    @MainActor
    public func activeProgram() throws -> TrainingProgramDefinition? {
        let context = ModelContext(container)
        guard let record = try activeProgramRecord(in: context) else { return nil }
        return TrainingProgramDefinition(record: record)
    }

    @MainActor
    private func hydrateCatalogIfNeeded(in context: ModelContext) throws {
        let records = try fetchProgramRecords(in: context)
        let existingIDs = Set(records.map(\.identifier))
        var insertedAny = false

        for definition in TrainingProgramCatalog.curated where !existingIDs.contains(definition.id) {
            context.insert(TrainingProgramRecord(definition: definition))
            insertedAny = true
        }

        if insertedAny {
            try context.save()
        }
    }

    @MainActor
    private func fetchProgramRecords(in context: ModelContext) throws -> [TrainingProgramRecord] {
        try context.fetch(FetchDescriptor<TrainingProgramRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))
    }

    @MainActor
    private func record(for identifier: String, in context: ModelContext) throws -> TrainingProgramRecord? {
        try fetchProgramRecords(in: context).first { record in
            record.identifier == identifier || record.catalogIdentifier == identifier
        }
    }

    @MainActor
    private func activeProgramRecord(in context: ModelContext) throws -> TrainingProgramRecord? {
        var descriptor = FetchDescriptor<TrainingProgramRecord>(
            predicate: #Predicate<TrainingProgramRecord> { program in
                program.isActive
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}

public enum TrainingProgramRepositoryError: Error, Equatable {
    case programNotFound(String)
    case invalidSessionsJSON(String)
}

extension TrainingProgramDefinition {
    init?(record: TrainingProgramRecord) {
        guard let sessions = SyncPayloadCodec.decode([TrainingProgramSessionTemplate].self, from: record.sessionsJSON),
              let difficulty = TrainingProgramDifficulty(rawValue: record.difficultyTier),
              let equipment = TrainingProgramEquipmentRequirement(rawValue: record.equipmentRequirement),
              TrainingProgramDefinition.isValid(
                weeks: record.weeks,
                sessionsPerWeek: record.sessionsPerWeek,
                sessions: sessions
              )
        else {
            return nil
        }

        self.init(
            id: record.identifier,
            name: record.name,
            author: record.author,
            weeks: record.weeks,
            sessionsPerWeek: record.sessionsPerWeek,
            advancementCriteria: record.advancementCriteria,
            difficulty: difficulty,
            equipmentRequirement: equipment,
            sessions: sessions
        )
    }
}

extension TrainingProgramRecord {
    convenience init(definition: TrainingProgramDefinition) {
        self.init(
            identifier: definition.id,
            catalogIdentifier: definition.id,
            name: definition.name,
            author: definition.author,
            weeks: definition.weeks,
            sessionsPerWeek: definition.sessionsPerWeek,
            advancementCriteria: definition.advancementCriteria,
            difficultyTier: definition.difficulty.rawValue,
            equipmentRequirement: definition.equipmentRequirement.rawValue,
            sessionsJSON: SyncPayloadCodec.encode(definition.sessions) ?? "[]",
            updatedAt: .now
        )
    }

    func apply(_ definition: TrainingProgramDefinition) {
        identifier = definition.id
        catalogIdentifier = definition.id
        name = definition.name
        author = definition.author
        weeks = definition.weeks
        sessionsPerWeek = definition.sessionsPerWeek
        advancementCriteria = definition.advancementCriteria
        difficultyTier = definition.difficulty.rawValue
        equipmentRequirement = definition.equipmentRequirement.rawValue
        sessionsJSON = SyncPayloadCodec.encode(definition.sessions) ?? "[]"
    }
}

private extension TrainingProgramCatalog {
    static func sortingCatalogFirst(_ lhs: TrainingProgramDefinition, _ rhs: TrainingProgramDefinition) -> Bool {
        let lhsIndex = curated.firstIndex { $0.id == lhs.id } ?? Int.max
        let rhsIndex = curated.firstIndex { $0.id == rhs.id } ?? Int.max
        if lhsIndex != rhsIndex {
            return lhsIndex < rhsIndex
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}
#endif
