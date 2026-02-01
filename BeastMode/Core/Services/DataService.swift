import Foundation
import SwiftData

/// Service for managing SwiftData CRUD operations
@MainActor
final class DataService: ObservableObject {
    static let shared = DataService()

    private var modelContext: ModelContext?

    private init() {}

    /// Configure the service with a model context
    func configure(with context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - User Profile

    /// Get or create the current user profile
    func getCurrentProfile() throws -> UserProfile {
        guard let context = modelContext else {
            throw DataServiceError.notConfigured
        }

        let descriptor = FetchDescriptor<UserProfile>()
        let profiles = try context.fetch(descriptor)

        if let profile = profiles.first {
            return profile
        }

        // Create default profile
        let newProfile = UserProfile()
        context.insert(newProfile)
        try context.save()
        return newProfile
    }

    /// Update user profile
    func updateProfile(_ profile: UserProfile) throws {
        guard let context = modelContext else {
            throw DataServiceError.notConfigured
        }
        try context.save()
    }

    // MARK: - Workout Plans

    /// Get the active workout plan
    func getActivePlan() throws -> WorkoutPlan? {
        guard let context = modelContext else {
            throw DataServiceError.notConfigured
        }

        var descriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate { $0.isActive }
        )
        descriptor.fetchLimit = 1

        return try context.fetch(descriptor).first
    }

    /// Get all workout plans
    func getAllPlans() throws -> [WorkoutPlan] {
        guard let context = modelContext else {
            throw DataServiceError.notConfigured
        }

        let descriptor = FetchDescriptor<WorkoutPlan>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// Create a new workout plan
    func createPlan(name: String, setActive: Bool = true) throws -> WorkoutPlan {
        guard let context = modelContext else {
            throw DataServiceError.notConfigured
        }

        // Deactivate other plans if setting this one active
        if setActive {
            let existingPlans = try getAllPlans()
            for plan in existingPlans {
                plan.isActive = false
            }
        }

        let plan = WorkoutPlan(name: name, isActive: setActive)
        context.insert(plan)
        try context.save()
        return plan
    }

    /// Delete a workout plan
    func deletePlan(_ plan: WorkoutPlan) throws {
        guard let context = modelContext else {
            throw DataServiceError.notConfigured
        }

        context.delete(plan)
        try context.save()
    }

    // MARK: - Daily Logs

    /// Get or create a daily log for a specific date
    func getDailyLog(for date: Date) throws -> DailyLog {
        guard let context = modelContext else {
            throw DataServiceError.notConfigured
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate { log in
                log.date >= startOfDay && log.date < endOfDay
            }
        )

        let logs = try context.fetch(descriptor)

        if let log = logs.first {
            return log
        }

        // Create new log
        let newLog = DailyLog(date: startOfDay, weekday: date.weekday)
        context.insert(newLog)
        try context.save()
        return newLog
    }

    /// Get daily logs for a date range
    func getDailyLogs(from startDate: Date, to endDate: Date) throws -> [DailyLog] {
        guard let context = modelContext else {
            throw DataServiceError.notConfigured
        }

        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate { log in
                log.date >= startDate && log.date <= endDate
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        return try context.fetch(descriptor)
    }

    /// Get daily logs for the current week
    func getCurrentWeekLogs() throws -> [DailyLog] {
        let calculator = WeekCalculator()
        let weekInfo = calculator.weekInfo(for: Date())
        return try getDailyLogs(from: weekInfo.startDate, to: weekInfo.endDate)
    }

    /// Save changes to a daily log
    func saveDailyLog(_ log: DailyLog) throws {
        guard let context = modelContext else {
            throw DataServiceError.notConfigured
        }
        try context.save()
    }

    // MARK: - Exercise Logs

    /// Add an exercise log to a daily log
    func addExerciseLog(
        to dailyLog: DailyLog,
        exerciseName: String,
        exerciseType: ExerciseType
    ) throws -> ExerciseLog {
        guard let context = modelContext else {
            throw DataServiceError.notConfigured
        }

        let sortOrder = dailyLog.exerciseLogs.count
        let exerciseLog = ExerciseLog(
            exerciseName: exerciseName,
            exerciseType: exerciseType,
            sortOrder: sortOrder
        )

        exerciseLog.dailyLog = dailyLog
        dailyLog.exerciseLogs.append(exerciseLog)

        try context.save()
        return exerciseLog
    }

    /// Delete an exercise log
    func deleteExerciseLog(_ exerciseLog: ExerciseLog) throws {
        guard let context = modelContext else {
            throw DataServiceError.notConfigured
        }

        context.delete(exerciseLog)
        try context.save()
    }

    // MARK: - Set Logs

    /// Add a set to an exercise log
    func addSet(to exerciseLog: ExerciseLog) throws -> SetLog {
        guard let context = modelContext else {
            throw DataServiceError.notConfigured
        }

        let setNumber = exerciseLog.sets.count + 1
        let setLog = SetLog(setNumber: setNumber)

        setLog.exerciseLog = exerciseLog
        exerciseLog.sets.append(setLog)

        try context.save()
        return setLog
    }

    /// Update a set log
    func updateSet(_ setLog: SetLog) throws {
        guard let context = modelContext else {
            throw DataServiceError.notConfigured
        }
        try context.save()
    }

    /// Delete a set log
    func deleteSet(_ setLog: SetLog) throws {
        guard let context = modelContext else {
            throw DataServiceError.notConfigured
        }

        context.delete(setLog)
        try context.save()
    }

    // MARK: - Personal Records

    /// Get all personal records
    func getAllPRs() throws -> [PersonalRecord] {
        guard let context = modelContext else {
            throw DataServiceError.notConfigured
        }

        let descriptor = FetchDescriptor<PersonalRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// Get personal records for a specific exercise
    func getPRs(for exerciseName: String) throws -> [PersonalRecord] {
        guard let context = modelContext else {
            throw DataServiceError.notConfigured
        }

        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.exerciseName == exerciseName },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    /// Get the current PR for an exercise
    func getCurrentPR(for exerciseName: String) throws -> PersonalRecord? {
        guard let context = modelContext else {
            throw DataServiceError.notConfigured
        }

        var descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate { $0.exerciseName == exerciseName },
            sortBy: [SortDescriptor(\.estimatedOneRepMax, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        return try context.fetch(descriptor).first
    }

    /// Check if a set is a new PR and save it if so
    func checkAndSavePR(setLog: SetLog, exerciseName: String) throws -> PersonalRecord? {
        guard let weight = setLog.weight, let reps = setLog.reps else {
            return nil
        }

        let currentPR = try getCurrentPR(for: exerciseName)
        let newE1RM = PersonalRecord.calculateE1RM(weight: weight, reps: reps)

        // Check if this beats the current PR
        if let currentPR = currentPR, newE1RM <= currentPR.estimatedOneRepMax {
            return nil
        }

        // This is a new PR!
        guard let context = modelContext else {
            throw DataServiceError.notConfigured
        }

        let newPR = PersonalRecord(
            exerciseName: exerciseName,
            weight: weight,
            reps: reps,
            sourceSetId: setLog.id
        )

        context.insert(newPR)

        // Mark the set as a PR
        setLog.isPR = true

        try context.save()
        return newPR
    }

    /// Delete a personal record
    func deletePR(_ pr: PersonalRecord) throws {
        guard let context = modelContext else {
            throw DataServiceError.notConfigured
        }

        context.delete(pr)
        try context.save()
    }

    // MARK: - Utility

    /// Save any pending changes
    func save() throws {
        guard let context = modelContext else {
            throw DataServiceError.notConfigured
        }
        try context.save()
    }
}

// MARK: - Errors

enum DataServiceError: LocalizedError {
    case notConfigured
    case saveFailed
    case fetchFailed

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Data service has not been configured with a model context"
        case .saveFailed:
            return "Failed to save data"
        case .fetchFailed:
            return "Failed to fetch data"
        }
    }
}
