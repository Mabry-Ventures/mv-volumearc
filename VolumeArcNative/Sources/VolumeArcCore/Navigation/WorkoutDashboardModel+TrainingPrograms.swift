#if canImport(SwiftUI)
import Foundation

extension WorkoutDashboardModel {
    /// Assign a curated multi-week program and replace the weekly schedule
    /// so today's Workouts tab card reflects the selected curriculum.
    @discardableResult
    public func assignTrainingProgram(_ catalogIdentifier: String) async -> Bool {
        #if canImport(SwiftData)
        guard let trainingProgramRepository else { return false }
        do {
            let context = try trainingProgramRepository.assignProgram(catalogIdentifier: catalogIdentifier)
            telemetrySink.record(TelemetryEvent(
                category: "program",
                name: "program_assigned",
                severity: .info,
                message: "Assigned \(context.programName)",
                metadata: [
                    "programID": context.programID,
                    "week": "\(context.weekNumber)",
                    "day": "\(context.dayNumber)",
                ]
            ))
            await refresh()
            return true
        } catch {
            telemetrySink.record(TelemetryEvent(
                category: "program",
                name: "program_assign_failed",
                severity: .error,
                message: error.localizedDescription,
                metadata: ["programID": catalogIdentifier]
            ))
            return false
        }
        #else
        return false
        #endif
    }
}
#endif
