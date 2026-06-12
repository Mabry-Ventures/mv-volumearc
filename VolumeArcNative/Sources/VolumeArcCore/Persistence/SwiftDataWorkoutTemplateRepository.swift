#if canImport(SwiftData)
import Foundation
import SwiftData

/// VOL-275: a saved, reusable workout template — the domain face of
/// `WorkoutTemplateRecord`. Templates are created from co-designed plans
/// (already clamped at save by the coach-source backstop) and can be
/// started or scheduled like any plan.
public struct SavedWorkoutTemplate: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public var name: String
    public var durationMinutes: Int?
    public var targetRPE: Int?
    public var exercises: [WeeklyWorkoutExercise]
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        durationMinutes: Int? = nil,
        targetRPE: Int? = nil,
        exercises: [WeeklyWorkoutExercise],
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.durationMinutes = durationMinutes
        self.targetRPE = targetRPE
        self.exercises = exercises
        self.createdAt = createdAt
    }

    public var sessionPlan: WorkoutSessionPlan {
        WorkoutSessionPlan(
            title: name,
            durationMinutes: durationMinutes,
            targetRPE: targetRPE,
            exercises: exercises
        )
    }
}

/// SwiftData-backed store for saved workout templates.
///
/// Local-only in v1 by design: templates do not stage to the CloudKit
/// outbound queue. The weekly plan must follow the athlete across
/// devices; a saved template library is a tracked post-v1 sync
/// refinement, and keeping it out of the sync contract avoids growing
/// the CloudKit record surface right before launch.
public final class SwiftDataWorkoutTemplateRepository {
    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    @MainActor
    public func templates() throws -> [SavedWorkoutTemplate] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<WorkoutTemplateRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).compactMap(Self.template(from:))
    }

    @MainActor
    @discardableResult
    public func saveTemplate(_ template: SavedWorkoutTemplate) throws -> SavedWorkoutTemplate {
        let context = ModelContext(container)
        guard let exercisesJSON = SyncPayloadCodec.encode(template.exercises) else {
            throw WorkoutTemplateRepositoryError.encodingFailed
        }

        let identifier = template.id
        var descriptor = FetchDescriptor<WorkoutTemplateRecord>(
            predicate: #Predicate { $0.identifier == identifier }
        )
        descriptor.fetchLimit = 1

        var persistedCreatedAt = template.createdAt
        if let existing = try context.fetch(descriptor).first {
            existing.name = template.name
            existing.durationMinutes = template.durationMinutes ?? 0
            existing.targetRPE = template.targetRPE ?? 0
            existing.exercisesJSON = exercisesJSON
            existing.updatedAt = .now
            persistedCreatedAt = existing.createdAt
        } else {
            context.insert(WorkoutTemplateRecord(
                identifier: template.id,
                name: template.name,
                durationMinutes: template.durationMinutes ?? 0,
                targetRPE: template.targetRPE ?? 0,
                exercisesJSON: exercisesJSON,
                createdAt: template.createdAt
            ))
        }
        try context.save()
        // Return the STORED creation date — an update keeps the original
        // record's createdAt, and the template list sorts by it, so the
        // returned value must agree with storage (PR #363 review).
        return SavedWorkoutTemplate(
            id: template.id,
            name: template.name,
            durationMinutes: template.durationMinutes,
            targetRPE: template.targetRPE,
            exercises: template.exercises,
            createdAt: persistedCreatedAt
        )
    }

    @MainActor
    public func deleteTemplate(id: String) throws {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<WorkoutTemplateRecord>(
            predicate: #Predicate { $0.identifier == id }
        )
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { return }
        context.delete(record)
        try context.save()
    }

    private static func template(from record: WorkoutTemplateRecord) -> SavedWorkoutTemplate? {
        guard let data = record.exercisesJSON.data(using: .utf8),
              let exercises = try? JSONDecoder().decode([WeeklyWorkoutExercise].self, from: data)
        else { return nil }
        return SavedWorkoutTemplate(
            id: record.identifier,
            name: record.name,
            durationMinutes: record.durationMinutes > 0 ? record.durationMinutes : nil,
            targetRPE: record.targetRPE > 0 ? record.targetRPE : nil,
            exercises: exercises,
            createdAt: record.createdAt
        )
    }
}

public enum WorkoutTemplateRepositoryError: Error {
    case encodingFailed
}
#endif
