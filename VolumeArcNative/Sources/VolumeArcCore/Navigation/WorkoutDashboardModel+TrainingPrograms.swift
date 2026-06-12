#if canImport(Combine)
import Foundation

extension WorkoutDashboardModel {
    /// VOL-284: extract a coach-proposed plan AND clamp it against the
    /// athlete's demonstrated history in one step. Used by flows that
    /// need clamped numbers up front (draft editors, tests). CoachView's
    /// inline transcript preview deliberately does NOT route through this
    /// — it runs per message per render and shows no load figures, so it
    /// uses the cheap extractor and relies on the authoritative re-clamp
    /// at the `scheduleWorkoutPlan` coach-source backstop below.
    public func clampedCoachWorkoutPlan(from response: String, title: String) -> WorkoutSessionPlan? {
        guard let extracted = CoachWorkoutPlanExtractor.plan(from: response, title: title) else {
            return nil
        }
        let (clamped, events) = CoachPrescriptionClamp.clamp(
            extracted,
            input: coachPrescriptionClampInput()
        )
        recordPrescriptionClampEvents(events, source: "coach_extraction")
        return clamped
    }

    /// Build the clamp context from live dashboard state: demonstrated
    /// top weights from logged history, the largest recent session
    /// volume, and whether the session carries symptom or red-flag
    /// context.
    func coachPrescriptionClampInput() -> CoachPrescriptionClamp.Input {
        var topWeights: [String: Double] = [:]
        // PR #363 review (CodeRabbit): the session-volume guard reads the
        // PERSISTED sessions, not the published snapshot — before the
        // first refresh `recentSessions` is empty and the volume cap
        // would silently skip on the start/schedule/template backstops.
        // The snapshot is only the fallback when no repository exists.
        var maxRecentVolume = recentSessions.map(\.totalVolumeLoad).max()
        #if canImport(SwiftData)
        if let workoutRepository {
            if let persisted = try? workoutRepository.recentSessions(limit: 20),
               let persistedMax = persisted.map(\.totalVolumeLoad).max() {
                maxRecentVolume = persistedMax
            }
            // PR #363 review (Codex P1, two rounds): never truncate
            // history — dropping a logged exercise would swap the
            // athlete's demonstrated-top cap for the HIGHER
            // first-exposure cap. The table covers EVERY logged exercise
            // ID, built in a single repository pass — the per-ID
            // history() loop decoded every workout once per exercise and
            // stalled the plan-draft render long enough to break the
            // co-design UI journey.
            let loggedTopWeights = (try? workoutRepository.topWeightByExerciseID()) ?? [:]
            for (exerciseID, topWeight) in loggedTopWeights {
                guard !exerciseID.hasPrefix("healthkit-"), topWeight > 0 else { continue }
                let key = CoachPrescriptionClamp.normalizedExerciseKey(exerciseID)
                topWeights[key] = max(topWeights[key] ?? 0, topWeight)
                // PR #363 review (Codex P2): catalog IDs ("back-squat")
                // carry no implement token, but coach plans usually name
                // one ("Barbell Back Squat") — and the matcher refuses
                // qualified-plan vs unqualified-history on purpose. The
                // catalog knows the implement, so logged catalog lifts
                // ALSO key under their implement-qualified name and the
                // athlete's demonstrated top survives coach phrasing.
                if let definition = VolumeArcExerciseCatalog.exercise(withID: exerciseID) {
                    let qualified = CoachPrescriptionClamp.normalizedExerciseKey(
                        "\(definition.primaryEquipment.rawValue) \(definition.name)"
                    )
                    topWeights[qualified] = max(topWeights[qualified] ?? 0, topWeight)
                }
            }
        }
        #endif
        // PR #363 review (CodeRabbit): symptom context is session-sticky —
        // ANY user message in the current transcript or the structured
        // training context carrying symptom/red-flag language keeps the
        // conservative clamp, so re-parsing an older coach reply after a
        // benign follow-up can never shed the stricter bounds. The
        // GENERATED response is deliberately NOT scanned (PR #363 review,
        // Codex P2): every athlete symptom that could shape a reply
        // arrives through a user message or the training context — both
        // covered above — while coach boilerplate ("stop at any pain")
        // would false-trip the symptom ceiling on ordinary plans.
        let userSymptom = coachMessages.contains { message in
            message.sender == .user
                && CoachSafetyFilter.shouldBufferResponse(prompt: message.content, context: "")
        }
        // Coach-authored lines are excluded before the scan (PR #363
        // review, Codex P2): persisted memories render as "User asked:" /
        // "Coach said:" pairs, and a prior reply's prudence boilerplate
        // ("stop at any pain") must not arm the symptom ceiling. Athlete
        // text and training data keep full coverage.
        let athleteAuthoredContext = buildCoachContext()
            .components(separatedBy: .newlines)
            .filter { !$0.contains("Coach said:") }
            .joined(separator: "\n")
        let contextSymptom = CoachSafetyFilter.shouldBufferResponse(prompt: "", context: athleteAuthoredContext)
        return CoachPrescriptionClamp.Input(
            topWeightByExerciseKey: topWeights,
            maxRecentSessionVolume: maxRecentVolume,
            hasSymptomContext: userSymptom || contextSymptom
        )
    }

    /// VOL-284 backstop for the workout-START path (PR #363 review,
    /// Codex P1): the coach handoff's Start button begins an active
    /// session directly instead of scheduling, so it must re-clamp the
    /// same way `scheduleWorkoutPlan(source: .coach)` does — otherwise a
    /// raw extracted prescription could go live unclamped. Idempotent for
    /// plans already clamped upstream.
    func clampedForCoachStart(_ plan: WorkoutSessionPlan) -> WorkoutSessionPlan {
        let (clamped, events) = CoachPrescriptionClamp.clamp(plan, input: coachPrescriptionClampInput())
        recordPrescriptionClampEvents(events, source: "coach_start")
        return clamped
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

    /// VOL-275: persist a co-designed plan as a reusable template. The
    /// plan re-clamps through the coach-source backstop before saving —
    /// a template is stored numbers, so it gets the same deterministic
    /// bounds as scheduling and starting.
    @discardableResult
    public func saveCoachTemplate(named rawName: String, plan: WorkoutSessionPlan) async -> Bool {
        #if canImport(SwiftData)
        guard let workoutTemplateRepository else {
            telemetrySink.record(TelemetryEvent(
                category: "coach",
                name: "template_save_failed",
                severity: .warning,
                message: "Template repository unavailable.",
                metadata: [:]
            ))
            return false
        }
        let (clamped, events) = CoachPrescriptionClamp.clamp(plan, input: coachPrescriptionClampInput())
        recordPrescriptionClampEvents(events, source: "coach_template")

        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty
            ? String(localized: "Co-designed Template", comment: "Fallback name for a saved co-designed template")
            : String(trimmedName.prefix(80))
        do {
            try workoutTemplateRepository.saveTemplate(SavedWorkoutTemplate(
                name: name,
                durationMinutes: clamped.durationMinutes,
                targetRPE: clamped.targetRPE,
                exercises: clamped.exercises
            ))
            savedTemplates = (try? workoutTemplateRepository.templates()) ?? savedTemplates
            telemetrySink.record(TelemetryEvent(
                category: "coach",
                name: "template_saved",
                severity: .info,
                message: "Co-designed plan saved as a template.",
                metadata: ["exerciseCount": "\(clamped.exercises.count)"]
            ))
            return true
        } catch {
            telemetrySink.record(TelemetryEvent(
                category: "coach",
                name: "template_save_failed",
                severity: .warning,
                message: "Failed to save co-designed template.",
                metadata: ["error_type": String(describing: type(of: error))]
            ))
            return false
        }
        #else
        return false
        #endif
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
        return await scheduleWorkoutPlan(plan, on: tomorrow, source: .coach, calendar: calendar)
    }

    /// Persist a draft workout into the weekly plan for a specific day.
    /// Replaces any existing workout on that weekday and refreshes the
    /// dashboard so Today and Workouts immediately show the schedule.
    @discardableResult
    public func scheduleWorkoutPlan(
        _ plan: WorkoutSessionPlan,
        on date: Date,
        source: WorkoutPlanSource = .workoutsBuilder,
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
        if source == .coach {
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
                    "source": source.rawValue,
                ]
            ))
            await sendScheduledPlanToWatch(scheduledWorkout, scheduledFor: date)
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

    /// VOL-275: mirror the just-scheduled co-designed plan to the watch so
    /// tomorrow's session is visible there. The payload carries the
    /// POST-CLAMP prescription (the caller schedules `scheduledWorkout`
    /// only after the coach-source backstop has bounded it). Send failures
    /// are tolerated here — the coordinator enqueues the payload and
    /// replays it on the next reconnect, which is the same guarantee every
    /// other watch payload relies on.
    private func sendScheduledPlanToWatch(_ workout: WeeklyWorkout, scheduledFor date: Date) async {
        guard let watchConnectivityCoordinator else { return }
        let payload = WatchScheduledPlanPayload(
            title: workout.title,
            dayOfWeek: workout.dayOfWeek,
            scheduledFor: date,
            durationMinutes: workout.durationMinutes,
            targetRPE: workout.targetRPE,
            exercises: workout.exercises.map {
                WatchScheduledPlanPayload.Exercise(
                    name: $0.name,
                    sets: $0.sets,
                    reps: $0.reps,
                    weight: $0.weight
                )
            }
        )
        try? await watchConnectivityCoordinator.send(WatchPayload(
            kind: .scheduledPlan,
            workoutID: "scheduled-plan-day-\(workout.dayOfWeek)",
            body: WatchScheduledPlanPayload.encode(payload)
        ))
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
