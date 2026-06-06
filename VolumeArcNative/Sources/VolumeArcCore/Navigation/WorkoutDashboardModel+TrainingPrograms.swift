#if canImport(Combine)
import Foundation

extension WorkoutDashboardModel {
    /// Persist a co-designed workout draft into the weekly plan for tomorrow.
    /// Replaces any existing workout on that weekday and refreshes the
    /// dashboard so Today/Workouts pick up the change immediately.
    @discardableResult
    public func scheduleCoDesignedWorkoutForTomorrow(
        title rawTitle: String,
        durationMinutes: Int? = nil,
        targetRPE: Int? = nil,
        exercises: [WeeklyWorkoutExercise] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) async -> Bool {
        let plan = WorkoutSessionPlan(
            title: rawTitle,
            durationMinutes: durationMinutes,
            targetRPE: targetRPE,
            exercises: exercises
        )
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return await scheduleWorkoutPlan(plan, on: tomorrow, source: "coach", calendar: calendar)
    }

    /// Persist a draft workout into the weekly plan for a specific day.
    /// Replaces any existing workout on that weekday and refreshes the
    /// dashboard so Today and Workouts immediately show the schedule.
    @discardableResult
    public func scheduleWorkoutPlan(
        _ plan: WorkoutSessionPlan,
        on date: Date,
        source: String = "workouts_builder",
        calendar: Calendar = .current
    ) async -> Bool {
        #if canImport(SwiftData)
        guard let trainingPlanRepository else {
            recordCoDesignedPlanScheduleFailure(
                title: plan.title,
                reason: "training_plan_repository_unavailable"
            )
            return false
        }

        let title = normalizedCoDesignedWorkoutTitle(plan.title)
        let dayOfWeek = WeeklyWorkout.trainingWeekday(for: date, calendar: calendar)

        do {
            var workouts = try trainingPlanRepository.weeklyWorkouts()
            let scheduledWorkout = WeeklyWorkout(
                dayOfWeek: dayOfWeek,
                title: title,
                durationMinutes: plan.durationMinutes,
                targetRPE: plan.targetRPE,
                exercises: plan.exercises
            )
            if let index = workouts.firstIndex(where: { $0.dayOfWeek == dayOfWeek }) {
                workouts[index] = scheduledWorkout
            } else {
                workouts.append(scheduledWorkout)
            }
            try trainingPlanRepository.upsertPlan(workouts.sorted { $0.dayOfWeek < $1.dayOfWeek })
            telemetrySink.record(TelemetryEvent(
                category: "coach",
                name: "plan_scheduled",
                severity: .info,
                message: "Co-designed workout scheduled for tomorrow.",
                metadata: [
                    "dayOfWeek": "\(dayOfWeek)",
                    "title_present": title.isEmpty ? "false" : "true",
                    "title_length_bucket": coDesignedTitleLengthBucket(title),
                    "exerciseCount": "\(plan.exercises.count)",
                    "source": source,
                ]
            ))
            await refresh()
            return true
        } catch {
            recordCoDesignedPlanScheduleFailure(title: title, reason: String(describing: type(of: error)))
            return false
        }
        #else
        recordCoDesignedPlanScheduleFailure(title: plan.title, reason: "swiftdata_unavailable")
        return false
        #endif
    }

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

    private func normalizedCoDesignedWorkoutTitle(_ rawTitle: String) -> String {
        let trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return String(localized: "Co-designed Workout", comment: "Fallback title for a scheduled co-designed plan")
        }
        return String(trimmed.prefix(80))
    }

    private func recordCoDesignedPlanScheduleFailure(title: String, reason: String) {
        telemetrySink.record(TelemetryEvent(
            category: "coach",
            name: "plan_schedule_failed",
            severity: .warning,
            message: "Failed to schedule co-designed workout.",
            metadata: [
                "title_present": title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "false" : "true",
                "title_length_bucket": coDesignedTitleLengthBucket(title),
                "error_type": reason,
            ]
        ))
    }

    private func coDesignedTitleLengthBucket(_ title: String) -> String {
        switch normalizedCoDesignedWorkoutTitle(title).count {
        case 0:
            return "0"
        case 1...20:
            return "1-20"
        case 21...80:
            return "21-80"
        default:
            return ">80"
        }
    }
}
#endif
