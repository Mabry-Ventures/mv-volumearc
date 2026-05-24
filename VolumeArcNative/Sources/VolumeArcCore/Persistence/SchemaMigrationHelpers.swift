#if canImport(SwiftData)
import CryptoKit
import Foundation
import SwiftData

extension VolumeArcSchemaMigrationPlan {
    public static func isSeededDefaultProfile(_ profile: UserProfileRecord) -> Bool {
        matchesSeededDefaultProfile(SeededProfileFields(
            name: profile.name,
            coachingStyle: profile.coachingStyle,
            privacyMode: profile.privacyMode,
            advancementLevel: profile.advancementLevel,
            availableEquipmentCSV: profile.availableEquipmentCSV,
            preferredRepRangeLower: profile.preferredRepRangeLower,
            preferredRepRangeUpper: profile.preferredRepRangeUpper,
            sessionTimeBudgetMinutes: profile.sessionTimeBudgetMinutes,
            weeklyTrainingDays: profile.weeklyTrainingDays,
            onboardingCompleted: profile.onboardingCompleted
        ))
    }

    static func isSeededDefaultProfile(_ profile: VolumeArcSchemaV4.UserProfileRecord) -> Bool {
        matchesSeededDefaultProfile(SeededProfileFields(
            name: profile.name,
            coachingStyle: profile.coachingStyle,
            privacyMode: profile.privacyMode,
            advancementLevel: profile.advancementLevel,
            availableEquipmentCSV: profile.availableEquipmentCSV,
            preferredRepRangeLower: profile.preferredRepRangeLower,
            preferredRepRangeUpper: profile.preferredRepRangeUpper,
            sessionTimeBudgetMinutes: profile.sessionTimeBudgetMinutes,
            weeklyTrainingDays: profile.weeklyTrainingDays,
            onboardingCompleted: profile.onboardingCompleted
        ))
    }

    public static func isSeededDefaultPlan(_ plan: TrainingPlanRecord) -> Bool {
        matchesSeededDefaultPlan(workoutsJSON: plan.workoutsJSON)
    }

    static func isSeededDefaultPlan(_ plan: VolumeArcSchemaV4.TrainingPlanRecord) -> Bool {
        matchesSeededDefaultPlan(workoutsJSON: plan.workoutsJSON)
    }

    static func deterministicLegacyMemoryIdentifier(
        createdAt: Date,
        content: String,
        theme: String
    ) -> String {
        let timestamp = String(
            format: "%.6f",
            locale: Locale(identifier: "en_US_POSIX"),
            createdAt.timeIntervalSince1970
        )
        let canonical = "ts=\(timestamp)|c=\(content.utf8.count):\(content)|t=\(theme.utf8.count):\(theme)"
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return "legacy-" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func matchesSeededDefaultPlan(workoutsJSON: String) -> Bool {
        let defaultPlanJSON = SyncPayloadCodec.encode(VolumeArcProductDefaults.weeklySchedule) ?? "[]"
        return workoutsJSON == defaultPlanJSON
    }

    private struct SeededProfileFields {
        let name: String
        let coachingStyle: String
        let privacyMode: String
        let advancementLevel: String
        let availableEquipmentCSV: String
        let preferredRepRangeLower: Int
        let preferredRepRangeUpper: Int
        let sessionTimeBudgetMinutes: Int
        let weeklyTrainingDays: Int
        let onboardingCompleted: Bool
    }

    private static func matchesSeededDefaultProfile(_ profile: SeededProfileFields) -> Bool {
        let defaults = VolumeArcProductDefaults.userProfile
        let defaultEquipmentCSV = defaults.availableEquipment
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
        return profile.name == defaults.name
            && profile.coachingStyle == defaults.coachingStyle.rawValue
            && profile.privacyMode == defaults.privacyMode.rawValue
            && profile.advancementLevel == defaults.advancementLevel.rawValue
            && profile.availableEquipmentCSV == defaultEquipmentCSV
            && profile.preferredRepRangeLower == defaults.preferredRepRangeLower
            && profile.preferredRepRangeUpper == defaults.preferredRepRangeUpper
            && profile.sessionTimeBudgetMinutes == defaults.sessionTimeBudgetMinutes
            && profile.weeklyTrainingDays == defaults.weeklyTrainingDays
            && profile.onboardingCompleted == false
    }
}
#endif
