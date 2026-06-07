#if canImport(Combine)
import Foundation

extension WorkoutDashboardModel {
    #if canImport(SwiftData)
    static func recentSession(_ workout: WorkoutRecord) -> RecentSession {
        RecentSession(
            identifier: workout.identifier,
            title: workout.title.isEmpty ? nil : workout.title,
            date: workout.completedAt ?? workout.startedAt,
            durationMinutes: workout.durationMinutes,
            exerciseIDs: workout.exerciseIDsCSV.split(separator: ",").map(String.init),
            totalVolumeLoad: workout.totalVolumeLoad,
            averageRPE: workout.averageRPE,
            completedSetCount: workout.completedSetCount
        )
    }
    #endif

    func externalHealthWorkoutSessions(limit: Int, now: Date = .now) async -> [RecentSession] {
        let startDate = Calendar.current.date(byAdding: .day, value: -90, to: now)
            ?? now.addingTimeInterval(-90 * 86_400)
        do {
            let workouts = try await healthWorkoutImporter.completedWorkouts(since: startDate, now: now)
            let uniqueWorkouts = Self.dedupeExternalHealthWorkouts(workouts)
            if workouts.isEmpty == false {
                telemetrySink.record(TelemetryEvent(
                    category: "health",
                    name: "workouts_loaded",
                    severity: .info,
                    message: "Loaded external Health workouts for readiness.",
                    metadata: [
                        "seen": "\(workouts.count)",
                        "included": "\(uniqueWorkouts.count)"
                    ]
                ))
            }
            return Array(uniqueWorkouts.prefix(limit).map(\.readinessSession))
        } catch {
            telemetrySink.record(TelemetryEvent(
                category: "health",
                name: "workout_import_failed",
                severity: .warning,
                message: "Health workout import failed: \(error.localizedDescription)"
            ))
            return []
        }
    }

    private static func dedupeExternalHealthWorkouts(_ workouts: [ImportedHealthWorkout]) -> [ImportedHealthWorkout] {
        var seen = Set<String>()
        var unique: [ImportedHealthWorkout] = []
        for workout in workouts.sorted(by: { $0.endedAt > $1.endedAt }) {
            guard seen.insert(workout.localWorkoutIdentifier).inserted else { continue }
            unique.append(workout)
        }
        return unique
    }
}
#endif
