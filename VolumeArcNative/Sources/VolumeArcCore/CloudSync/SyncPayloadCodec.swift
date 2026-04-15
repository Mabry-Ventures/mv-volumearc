import Foundation
#if canImport(SwiftData)
import SwiftData
#endif

public enum SyncPayloadCodec {
    public struct UserProfilePayload: Codable, Equatable, Sendable {
        public let name: String
        public let coachingStyle: String
        public let privacyMode: String
        public let advancementLevel: String
        public let availableEquipmentCSV: String
        public let preferredRepRangeLower: Int
        public let preferredRepRangeUpper: Int
        public let sessionTimeBudgetMinutes: Int
        public let weeklyTrainingDays: Int
        public let onboardingCompleted: Bool
        public let updatedAt: Date
    }

    public struct WorkoutPayload: Codable, Equatable, Sendable {
        public let title: String
        public let startedAt: Date
        public let completedAt: Date?
        public let durationMinutes: Int
        public let exerciseIDsCSV: String
        public let setsJSON: String
        public let totalVolumeLoad: Double
        public let averageRPE: Double
        public let completedSetCount: Int
        public let summary: String
        public let updatedAt: Date
    }

    public struct TrainingPlanPayload: Codable, Equatable, Sendable {
        public let workoutsJSON: String
        public let updatedAt: Date
    }

    public struct CoachMemoryPayload: Codable, Equatable, Sendable {
        public let content: String
        public let theme: String
        public let createdAt: Date
    }

    private struct UserProfileEnvelope: Codable, Equatable, Sendable {
        let profile: UserProfilePayload
    }

    private struct WorkoutEnvelope: Codable, Equatable, Sendable {
        let workout: WorkoutPayload
    }

    private struct TrainingPlanEnvelope: Codable, Equatable, Sendable {
        let plan: TrainingPlanPayload
    }

    private struct CoachMemoryEnvelope: Codable, Equatable, Sendable {
        let memory: CoachMemoryPayload
    }

    public static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from string: String) -> T? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    public static func encodeUserProfilePayload(from record: UserProfileRecord) -> String? {
        encode(UserProfileEnvelope(profile: UserProfilePayload(
            name: record.name,
            coachingStyle: record.coachingStyle,
            privacyMode: record.privacyMode,
            advancementLevel: record.advancementLevel,
            availableEquipmentCSV: record.availableEquipmentCSV,
            preferredRepRangeLower: record.preferredRepRangeLower,
            preferredRepRangeUpper: record.preferredRepRangeUpper,
            sessionTimeBudgetMinutes: record.sessionTimeBudgetMinutes,
            weeklyTrainingDays: record.weeklyTrainingDays,
            onboardingCompleted: record.onboardingCompleted,
            updatedAt: record.updatedAt
        )))
    }

    public static func decodeUserProfilePayload(from string: String) -> UserProfilePayload? {
        decode(UserProfileEnvelope.self, from: string)?.profile
    }

    public static func encodeWorkoutPayload(from record: WorkoutRecord) -> String? {
        encode(WorkoutEnvelope(workout: WorkoutPayload(
            title: record.title,
            startedAt: record.startedAt,
            completedAt: record.completedAt,
            durationMinutes: record.durationMinutes,
            exerciseIDsCSV: record.exerciseIDsCSV,
            setsJSON: record.setsJSON,
            totalVolumeLoad: record.totalVolumeLoad,
            averageRPE: record.averageRPE,
            completedSetCount: record.completedSetCount,
            summary: record.summary,
            updatedAt: record.updatedAt
        )))
    }

    public static func decodeWorkoutPayload(from string: String) -> WorkoutPayload? {
        decode(WorkoutEnvelope.self, from: string)?.workout
    }

    public static func encodeTrainingPlanPayload(from record: TrainingPlanRecord) -> String? {
        encode(TrainingPlanEnvelope(plan: TrainingPlanPayload(
            workoutsJSON: record.workoutsJSON,
            updatedAt: record.updatedAt
        )))
    }

    public static func decodeTrainingPlanPayload(from string: String) -> TrainingPlanPayload? {
        decode(TrainingPlanEnvelope.self, from: string)?.plan
    }

    public static func encodeCoachMemoryPayload(from record: CoachMemoryRecord) -> String? {
        encode(CoachMemoryEnvelope(memory: CoachMemoryPayload(
            content: record.content,
            theme: record.theme,
            createdAt: record.createdAt
        )))
    }

    public static func decodeCoachMemoryPayload(from string: String) -> CoachMemoryPayload? {
        decode(CoachMemoryEnvelope.self, from: string)?.memory
    }

    public static func modifiedAt(for kind: CloudSyncRecord.Kind, payloadJSON: String) -> Date? {
        switch kind {
        case .workout:
            return decodeWorkoutPayload(from: payloadJSON)?.updatedAt
        case .userProfile:
            return decodeUserProfilePayload(from: payloadJSON)?.updatedAt
        case .trainingPlan:
            return decodeTrainingPlanPayload(from: payloadJSON)?.updatedAt
        case .coachMemory:
            return decodeCoachMemoryPayload(from: payloadJSON)?.createdAt
        }
    }

    public static func makeRecord(
        for workout: WorkoutRecord,
        operation: CloudSyncRecord.Operation = .upsert
    ) -> CloudSyncRecord? {
        guard let payloadJSON = encodeWorkoutPayload(from: workout) else { return nil }
        return CloudSyncRecord(
            kind: .workout,
            identifier: workout.identifier,
            operation: operation,
            payloadJSON: payloadJSON,
            modifiedAt: workout.updatedAt
        )
    }

    public static func makeRecord(
        for profile: UserProfileRecord,
        operation: CloudSyncRecord.Operation = .upsert
    ) -> CloudSyncRecord? {
        guard let payloadJSON = encodeUserProfilePayload(from: profile) else { return nil }
        return CloudSyncRecord(
            kind: .userProfile,
            identifier: CloudSyncRecord.Kind.userProfile.defaultIdentifier,
            operation: operation,
            payloadJSON: payloadJSON,
            modifiedAt: profile.updatedAt
        )
    }

    public static func makeRecord(
        for plan: TrainingPlanRecord,
        operation: CloudSyncRecord.Operation = .upsert
    ) -> CloudSyncRecord? {
        guard let payloadJSON = encodeTrainingPlanPayload(from: plan) else { return nil }
        return CloudSyncRecord(
            kind: .trainingPlan,
            identifier: CloudSyncRecord.Kind.trainingPlan.defaultIdentifier,
            operation: operation,
            payloadJSON: payloadJSON,
            modifiedAt: plan.updatedAt
        )
    }

    public static func makeRecord(
        for memory: CoachMemoryRecord,
        operation: CloudSyncRecord.Operation = .upsert
    ) -> CloudSyncRecord? {
        guard let payloadJSON = encodeCoachMemoryPayload(from: memory) else { return nil }
        return CloudSyncRecord(
            kind: .coachMemory,
            identifier: memory.identifier,
            operation: operation,
            payloadJSON: payloadJSON,
            modifiedAt: memory.createdAt
        )
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}
