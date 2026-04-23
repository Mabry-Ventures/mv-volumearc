import Foundation

/// Structured prompt templates for the AI coach.
///
/// Every concrete `AICoachProvider` routes its outbound prompt through this
/// template before handing it to its model (relay, on-device, or rule-based).
/// This keeps the system prompt, context block, intent envelope, and final
/// rendered shape identical across providers — and gives us a single place
/// to evolve coaching style without touching three call sites.
///
/// Pure renderer. No state, no I/O, no async. Deterministic for a given
/// `(intent, context, question)` triple so the integration test can pin a
/// marker string and assert downstream callers actually invoke `render`
/// rather than silently regressing to ad-hoc string interpolation.
public enum CoachPromptTemplate {

    /// Marker baked into every rendered prompt. Providers that route through
    /// `render` propagate this marker to whatever the model sees, so a
    /// regression that bypasses the template (e.g., concatenating context +
    /// question by hand again) drops the marker and fails the integration
    /// test. Versionless on purpose — VOL-64 is about adoption, not a
    /// version-bump mechanism.
    public static let templateMarker = "[VAC:tmpl]"

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
    ///
    /// Kept as the lower-level renderer for the structured `CoachContext` path.
    /// Most callers should use `render(intent:context:question:style:)` instead,
    /// which wraps this in a system prompt + intent envelope + template marker.
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

    /// Render the full prompt a provider sends to its model. This is the
    /// single entry point providers should use — it bakes in the system
    /// prompt, intent-specific framing, the structured context block, the
    /// athlete's question, and a template marker that proves the call went
    /// through this code path.
    ///
    /// Use this overload when you have a structured `CoachContext`. Providers
    /// that only see the dashboard's already-rendered context string (because
    /// the protocol passes `(prompt: String, context: String)` not the typed
    /// context) should call `render(intent:contextBlock:question:style:)`.
    public static func render(
        intent: CoachIntent,
        context: CoachContext,
        question: String,
        style: CoachingStyle = .motivational,
        privacyMode: PrivacyMode = .standard
    ) -> String {
        render(
            intent: intent,
            contextBlock: context.asPromptBlock(privacyMode: privacyMode),
            question: question,
            style: style
        )
    }

    /// Render the full prompt from a pre-rendered context block string.
    /// Used by `AICoachProvider` implementations, since the protocol passes
    /// the dashboard's already-formatted context block as a `String` rather
    /// than the structured `CoachContext`. The dashboard builds that block
    /// from `CoachContext.asPromptBlock(privacyMode:)`, so the contract is
    /// preserved without changing the protocol surface.
    public static func render(
        intent: CoachIntent,
        contextBlock: String,
        question: String,
        style: CoachingStyle = .motivational
    ) -> String {
        let system = systemPrompt(style: style)
        let envelope = intentEnvelope(intent)
        let trimmedContext = contextBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)

        return """
        \(templateMarker) intent=\(intent.rawValue) style=\(style.rawValue)

        ## System
        \(system)

        \(trimmedContext)

        ## Coaching focus
        \(envelope)

        ## Athlete question
        \(trimmedQuestion)
        """
    }

    /// Convenience that infers the intent from the question text and renders.
    /// Providers that don't have access to a typed intent (most of them) call
    /// this so the same heuristic that powers `LocalHeuristicAICoachProvider`'s
    /// dispatch is also what shapes the prompt sent to the cloud relay or
    /// on-device model.
    public static func render(
        question: String,
        contextBlock: String,
        style: CoachingStyle = .motivational
    ) -> String {
        render(
            intent: inferIntent(from: question),
            contextBlock: contextBlock,
            question: question,
            style: style
        )
    }

    /// Pattern-match the question to a coaching intent. The mapping intentionally
    /// mirrors `LocalHeuristicAICoachProvider`'s dispatch keywords so an offline
    /// answer and an online answer route through the same intent envelope.
    public static func inferIntent(from question: String) -> CoachIntent {
        let lowered = question.lowercased()
        if lowered.contains("ready") || lowered.contains("recovery")
            || lowered.contains("tired") || lowered.contains("fatigue")
            || lowered.contains("sleep") {
            return .recovery
        }
        if lowered.contains("deload") || lowered.contains("back off")
            || lowered.contains("easier") {
            return .deload
        }
        if lowered.contains("form") || lowered.contains("cue")
            || lowered.contains("technique") {
            return .form
        }
        if lowered.contains("substitute") || lowered.contains("swap")
            || lowered.contains("alternative") || lowered.contains("instead of") {
            return .substitution
        }
        if lowered.contains("heavy") || lowered.contains("heavier")
            || lowered.contains("more weight") || lowered.contains("add ")
            || lowered.contains(" up") || lowered.contains("push") {
            return .progression
        }
        return .free
    }

    private static func intentEnvelope(_ intent: CoachIntent) -> String {
        switch intent {
        case .progression:
            return """
            The athlete is asking about pushing load or volume. Anchor the answer in
            the most recent session's RPE and bar speed signals from the context.
            Recommend a small, concrete jump only if the prior set moved cleanly;
            otherwise hold and explain why.
            """
        case .deload:
            return """
            The athlete is considering a deload. Use readiness score + recent RPE
            trend from the context to decide. If a deload is warranted, name the
            specific intensity and volume cut. If not, propose a lighter top set
            and reassess tomorrow.
            """
        case .form:
            return """
            The athlete is asking about technique. Give one or two cues tied to the
            specific lift in the context if present. Avoid generic advice; flag
            anything that looks like a pain or injury signal.
            """
        case .recovery:
            return """
            The athlete is asking about readiness or recovery. Read the readiness
            score, recent session count, and average RPE from the context, then
            give a short read on whether to push, hold, or back off today.
            """
        case .substitution:
            return """
            The athlete wants an exercise substitution. Use the next-up exercise
            from the context as the anchor. Recommend a substitute that hits the
            same primary movement pattern with the equipment they have.
            """
        case .free:
            return """
            Open question — answer directly using the training context provided.
            Stay specific to the athlete's data; avoid generic coaching platitudes.
            """
        }
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

/// Coaching intent inferred from the athlete's question. Each case maps to a
/// dedicated envelope inside `CoachPromptTemplate.render(...)` that shapes
/// how the model should approach the answer.
public enum CoachIntent: String, Sendable, CaseIterable {
    case progression
    case deload
    case form
    case recovery
    case substitution
    case free
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
        if privacyMode == .standard {
            if recentSessionCount > 0 {
                lines.append("- Last 7 days: \(recentSessionCount) sessions, avg RPE \(String(format: "%.1f", averageRPE))")
            } else {
                lines.append("- No recent sessions logged")
            }
            if let lastSessionSummary {
                lines.append("- Last session: \(lastSessionSummary)")
            }
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
