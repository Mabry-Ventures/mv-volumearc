import Foundation

/// Structured prompt templates for the AI coach.
/// Each template grounds the prompt in real user context and enforces
/// coaching persona, safety, and output style.
public enum CoachPromptTemplate {

    /// System prompt that sets the coach's persona, boundaries, and output style.
    public static func systemPrompt(style: CoachingStyle) -> String {
        let persona = personaForStyle(style)
        return """
        You are VolumeArc's strength coach. You speak directly to the athlete.

        Persona: \(persona)

        Rules:
        - Keep responses under 3 sentences unless the user asks for detail.
        - Never recommend lifting through pain — flag potential injury signals instead.
        - Cite the user's recent data when it shapes your advice ("Last session you hit 225x5 at RPE 8…").
        - Prefer specific cues over generic encouragement.
        - If data is thin, say so and give a conservative recommendation.
        - Use plain language. No jargon unless the user uses it first.

        Output: Respond naturally, as if texting the athlete between sets.
        """
    }

    /// Build a user prompt from the athlete's current training context.
    public static func userPrompt(
        question: String,
        context: CoachContext,
        privacyMode: PrivacyMode = .standard
    ) -> String {
        let contextBlock = context.asPromptBlock(privacyMode: privacyMode)
        return """
        \(contextBlock)

        ---

        Athlete question: \(question)
        """
    }

    private static func personaForStyle(_ style: CoachingStyle) -> String {
        switch style {
        case .motivational:
            return "High-energy. Pushes when it's earned, cheers the wins, never saccharine. Thinks of every session as a chance to compound."
        case .analytical:
            return "Data-driven. Explains the why behind every call. Treats training as a feedback loop."
        case .minimal:
            return "Short and direct. One insight, one action. No preamble."
        }
    }
}

/// Composable context for the coach prompt. Built from the dashboard state.
public struct CoachContext: Sendable {
    public let athleteName: String
    public let advancementLevel: String
    public let readinessScore: Int
    public let readinessBrief: String
    public let nextExercise: String?
    public let nextTarget: String?
    public let recentSessionCount: Int
    public let averageRPE: Double
    public let lastSessionSummary: String?
    public let recentMemories: [String]

    public init(
        athleteName: String,
        advancementLevel: String,
        readinessScore: Int,
        readinessBrief: String,
        nextExercise: String? = nil,
        nextTarget: String? = nil,
        recentSessionCount: Int = 0,
        averageRPE: Double = 0,
        lastSessionSummary: String? = nil,
        recentMemories: [String] = []
    ) {
        self.athleteName = athleteName
        self.advancementLevel = advancementLevel
        self.readinessScore = readinessScore
        self.readinessBrief = readinessBrief
        self.nextExercise = nextExercise
        self.nextTarget = nextTarget
        self.recentSessionCount = recentSessionCount
        self.averageRPE = averageRPE
        self.lastSessionSummary = lastSessionSummary
        self.recentMemories = recentMemories
    }

    /// Format the context as a prompt block, redacting PII in strict privacy mode.
    public func asPromptBlock(privacyMode: PrivacyMode) -> String {
        let name: String = {
            switch privacyMode {
            case .standard: return athleteName.isEmpty ? "the athlete" : athleteName
            case .strict: return "the athlete"
            }
        }()

        var lines: [String] = []
        lines.append("## Training context")
        lines.append("- Athlete: \(name) (\(advancementLevel))")
        lines.append("- Readiness: \(readinessScore)/100 — \(readinessBrief)")
        if let nextExercise, let nextTarget {
            lines.append("- Next up: \(nextExercise) at \(nextTarget)")
        }
        if recentSessionCount > 0 {
            lines.append("- Last 7 days: \(recentSessionCount) sessions, avg RPE \(String(format: "%.1f", averageRPE))")
        } else {
            lines.append("- No recent sessions logged")
        }
        if let lastSessionSummary {
            lines.append("- Last session: \(lastSessionSummary)")
        }

        if privacyMode == .standard && !recentMemories.isEmpty {
            lines.append("")
            lines.append("## Recent coaching notes")
            for memory in recentMemories.prefix(3) {
                lines.append("- \(memory)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
