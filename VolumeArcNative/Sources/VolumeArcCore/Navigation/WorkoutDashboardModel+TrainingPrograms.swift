#if canImport(Combine)
import Foundation

extension WorkoutDashboardModel {
    /// VOL-284: extract a coach-proposed plan AND clamp it against the
    /// athlete's demonstrated history before anything previews or
    /// persists it. CoachView routes through this instead of calling
    /// `CoachWorkoutPlanExtractor` directly so the numbers the athlete
    /// sees are the numbers that get scheduled.
    public func clampedCoachWorkoutPlan(from response: String, title: String) -> WorkoutSessionPlan? {
        guard let extracted = CoachWorkoutPlanExtractor.plan(from: response, title: title) else {
            return nil
        }
        let (clamped, events) = CoachPrescriptionClamp.clamp(
            extracted,
            input: coachPrescriptionClampInput(planResponse: response)
        )
        recordPrescriptionClampEvents(events, source: "coach_extraction")
        return clamped
    }

    /// Build the clamp context from live dashboard state: demonstrated
    /// top weights from logged history, the largest recent session
    /// volume, and whether the session carries symptom or red-flag
    /// context.
    func coachPrescriptionClampInput(planResponse: String? = nil) -> CoachPrescriptionClamp.Input {
        var topWeights: [String: Double] = [:]
        #if canImport(SwiftData)
        if let workoutRepository {
            // PR #363 review (Codex P1): never truncate history — dropping
            // a logged exercise would swap the athlete's demonstrated-top
            // cap for the HIGHER first-exposure cap. Sorted for
            // deterministic table construction.
            let loggedIDs = Set(
                recentSessions
                    .flatMap(\.exerciseIDs)
                    .filter { !$0.hasPrefix("healthkit-") }
            ).sorted()
            for exerciseID in loggedIDs {
                guard let history = try? workoutRepository.history(forExercise: exerciseID),
                      history.topWeight > 0 else { continue }
                topWeights[CoachPrescriptionClamp.normalizedExerciseKey(exerciseID)] = history.topWeight
            }
        }
        #endif
        // PR #363 review (CodeRabbit): symptom context is session-sticky.
        // ANY user message in the current transcript, the structured
        // training context, or the plan-bearing response itself carrying
        // symptom/red-flag language keeps the conservative clamp, so
        // re-parsing an older coach reply after a benign follow-up can
        // never silently shed the stricter bounds.
        let userSymptom = coachMessages.contains { message in
            message.sender == .user
                && CoachSafetyFilter.shouldBufferResponse(prompt: message.content, context: "")
        }
        let contextSymptom = CoachSafetyFilter.shouldBufferResponse(prompt: "", context: buildCoachContext())
        let responseSymptom = planResponse.map {
            CoachSafetyFilter.shouldBufferResponse(prompt: "", context: $0)
        } ?? false
        return CoachPrescriptionClamp.Input(
            topWeightByExerciseKey: topWeights,
            maxRecentSessionVolume: recentSessions.map(\.totalVolumeLoad).max(),
            hasSymptomContext: userSymptom || contextSymptom || responseSymptom
        )
    }

    private func recordPrescriptionClampEvents(_ events: [CoachPrescriptionClamp.Event], source: String) {
        guard !events.isEmpty else { return }
        var metadata: [String: String] = ["source": source, "total": "\(events.count)"]
        for event in events {
            let key = "kind_\(event.kind.rawValue)"
            metadata[key] = "\((Int(metadata[key] ?? "0") ?? 0) + 1)"
        }
        telemetrySink.record(TelemetryEvent(
            category: "coach.safety",
            name: "clamp",
            severity: .warning,
            message: "Coach prescription clamped to safety bounds.",
            metadata: metadata
        ))
    }

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
        let trimmedRawTitle = plan.title.trimmingCharacters(in: .whitespacesAndNewlines)
        #if canImport(SwiftData)
        guard let trainingPlanRepository else {
            recordCoDesignedPlanScheduleFailure(
                title: trimmedRawTitle,
                reason: "training_plan_repository_unavailable"
            )
            return false
        }

        let title = normalizedCoDesignedWorkoutTitle(plan.title)
        let dayOfWeek = WeeklyWorkout.trainingWeekday(for: date, calendar: calendar)

        // VOL-284 backstop: coach-sourced plans are re-clamped at the
        // persistence chokepoint, so no caller can route a model-derived
        // prescription around the safety bounds. Clamping is idempotent;
        // plans already clamped at extraction pass through unchanged.
        var persistedPlan = plan
        if source == "coach" {
            let (clamped, events) = CoachPrescriptionClamp.clamp(plan, input: coachPrescriptionClampInput())
            recordPrescriptionClampEvents(events, source: "coach_schedule")
            persistedPlan = clamped
        }

        do {
            var workouts = try trainingPlanRepository.weeklyWorkouts()
            let scheduledWorkout = WeeklyWorkout(
                dayOfWeek: dayOfWeek,
                title: title,
                durationMinutes: persistedPlan.durationMinutes,
                targetRPE: persistedPlan.targetRPE,
                exercises: persistedPlan.exercises
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
                    "title_present": trimmedRawTitle.isEmpty ? "false" : "true",
                    "title_length_bucket": coDesignedTitleLengthBucket(trimmedRawTitle),
                    "exerciseCount": "\(persistedPlan.exercises.count)",
                    "source": source,
                ]
            ))
            await refresh()
            return true
        } catch {
            recordCoDesignedPlanScheduleFailure(title: trimmedRawTitle, reason: String(describing: type(of: error)))
            return false
        }
        #else
        recordCoDesignedPlanScheduleFailure(title: trimmedRawTitle, reason: "swiftdata_unavailable")
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
