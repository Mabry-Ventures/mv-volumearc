#if canImport(SwiftUI)
import Foundation

/// VOL-181 Phase 1B: coach-context construction extracted from
/// `WorkoutDashboardModel` so the main class stays under the
/// SwiftLint `file_length` / `type_body_length` caps (750 lines /
/// 520 type-body lines respectively). Both methods are still part
/// of the class via this extension — moving them changes their
/// physical location, not their access level or behavior.
extension WorkoutDashboardModel {

    /// Pull the latest recovery snapshot from the injected
    /// `RecoveryReader`. Per the protocol contract, implementations
    /// absorb their own HK errors and return an empty / partial
    /// `RecoveryContext` rather than throwing — the dashboard treats
    /// the result as "no recovery section" when `hasAnyData == false`.
    func refreshRecovery() async {
        self.recovery = await recoveryReader.currentRecovery(now: .now)
    }

    /// Build the grounded context block for coach prompts using real
    /// dashboard state and recent coach memories for continuity across
    /// conversations.
    func buildCoachContext() -> String {
        let athleteName = athlete.name.isEmpty ? "the athlete" : athlete.name
        let avgRPE = recentSessions.isEmpty
            ? 0
            : recentSessions.map(\.averageRPE).reduce(0, +) / Double(recentSessions.count)

        let lastSessionSummary: String? = recentSessions
            .max(by: { $0.date < $1.date })
            .map { session in
                let volume = Int(session.totalVolumeLoad)
                let rpe = String(format: "%.1f", session.averageRPE)
                return "\(session.completedSetCount) sets, \(volume)lb total, RPE \(rpe)"
            }

        var memories: [String] = []
        #if canImport(SwiftData)
        if let coachMemoryRepository, let memory = try? coachMemoryRepository.coachMemory() {
            memories = memory.mostRecent.map(\.summary)
        }
        #endif

        let nextExercise = autopilot?.nextExerciseName
        let nextTarget: String? = autopilot.map { state in
            let weight = Int(state.nextTarget.weight)
            let reps = state.nextTarget.repRange
            return "\(weight)lb × \(reps.lowerBound)-\(reps.upperBound)"
        }

        let context = CoachContext(
            athleteName: athleteName,
            advancementLevel: athlete.advancementLevel.rawValue,
            readinessScore: readiness.score,
            readinessBrief: readiness.brief,
            nextExercise: nextExercise,
            nextTarget: nextTarget,
            recentSessionCount: recentSessions.count,
            averageRPE: avgRPE,
            lastSessionSummary: lastSessionSummary,
            recentMemories: memories,
            program: activeProgram,
            // VOL-181 Phase 1B: cached recovery snapshot fed into the
            // coach prompt. `RecoveryContext.hasAnyData` gates the
            // section so empty contexts render as no-op.
            recovery: recovery
        )

        return context.asPromptBlock(privacyMode: athlete.privacyMode)
    }
}
#endif
