import Foundation

/// Last-mile guard for coach responses that could affect athlete safety.
///
/// The prompt template tells model-backed providers what to do, but this
/// filter enforces the same boundary after generation. High-risk symptom
/// prompts are buffered before rendering so unsafe relay chunks never flash
/// in the chat UI.
public enum CoachSafetyFilter {
    public static func shouldBufferResponse(prompt: String) -> Bool {
        shouldBufferResponse(prompt: prompt, context: "")
    }

    public static func shouldBufferResponse(prompt: String, context: String) -> Bool {
        medicalRedFlagResponse(prompt: prompt, context: context) != nil
            || hasRecoverySymptoms(prompt)
            || hasCurrentRecoverySymptoms(inContext: context)
    }

    public static func filteredResponse(prompt: String, context: String, response: String) -> String {
        if let redFlagResponse = medicalRedFlagResponse(prompt: prompt, context: context) {
            return redFlagResponse
        }
        guard hasRecoverySymptoms(prompt) || hasCurrentRecoverySymptoms(inContext: context) else {
            return response
        }

        let lowered = response.lowercased()
        let hasRestPermission = [
            "rest", "take the day", "skip training", "do not train", "don't train"
        ].contains { lowered.contains($0) }
        let hasLightOption = [
            "light", "easy", "technique", "40-60", "forty", "mobility"
        ].contains { lowered.contains($0) }
        let hasStopCondition = lowered.contains("stop") && [
            "pain", "dizz", "fever", "symptom", "worse", "worsening"
        ].contains { lowered.contains($0) }
        let unsafeLanguage = [
            "push through", "power through", "fight through", "no excuses",
            "go heavy", "go heavier", "max out", "1rm", "pr today",
            "add weight", "grind", "don't skip", "do not skip"
        ].contains { lowered.contains($0) }

        guard unsafeLanguage || !hasRestPermission || !hasLightOption || !hasStopCondition else {
            return response
        }
        return conservativeRecoveryResponse(prompt: prompt, context: context)
    }

    public static func conservativeRecoveryResponse(prompt: String, context: String) -> String {
        let score = extractReadinessScore(from: context)
        let scoreLine = score.map {
            String(
                localized: "Readiness is \($0), but your symptoms matter more than the score.",
                comment: "Coach safety filter line when recovery symptoms override readiness"
            )
        } ?? String(
            localized: "Your symptoms matter more than any training target.",
            comment: "Coach safety filter line when symptoms are present without readiness"
        )
        return String(
            localized: """
            \(scoreLine) Rest is a valid win today. If you still want to move, \
            keep it to 15-25 minutes of easy technique work, mobility, or light \
            accessories at 40-60% effort, and stop at any pain, dizziness, \
            fever, or worsening symptoms.
            """,
            comment: "Coach safety filter response for sick, sore, tight, or run-down athletes"
        )
    }

    public static func medicalRedFlagResponse(prompt: String, context: String) -> String? {
        if let promptResponse = medicalRedFlagResponse(from: prompt) {
            return promptResponse
        }
        guard hasCurrentMedicalRedFlag(inContext: context) else {
            return nil
        }
        return medicalRedFlagResponseText()
    }

    public static func medicalRedFlagResponse(from text: String) -> String? {
        let nearby = "[\\s\\S]{0,80}"
        let redFlagPatterns = [
            "\\b(i\\s*(?:feel|felt|have|had|experienced|experience|got|gotten)|i\\W?m|my)\\b" +
                nearby + "\\bchest\\s+pain\\b",
            "\\b(i\\s*(?:feel|felt|have|had|experienced|experience|got|gotten)|i\\W?m|my)\\b" +
                nearby + "\\bdizz(?:y|iness)\\b",
            "\\b(i\\s*(?:feel|felt|have|had|experienced|experience|got|gotten)|i\\W?m|my)\\b" +
                nearby + "\\blightheaded\\b",
            "\\b(i\\s*(?:feel|felt|have|had|experienced|experience|got|gotten)|i\\W?m|my)\\b" +
                nearby + "\\bfaint(?:ed|ing)?\\b",
            "\\b(i\\s*(?:passed\\s+out|blacked\\s+out|have\\s+syncope|had\\s+syncope)|i\\W?ve\\s+(?:passed|blacked)\\s+out)\\b",
            "\\b(i\\s*(?:feel|felt|have|had|experienced|experience|got|gotten)|i\\W?m|my)\\b" +
                nearby +
                "\\b(?:severe\\s+)?short(?:ness)?\\s+of\\s+breath\\b",
            "\\b(i\\s*(?:can'?t|cannot)\\s+breathe|hard\\s+to\\s+breathe)\\b",
            "\\b(i\\s*(?:am|might\\s+be|may\\s+be)|i\\W?m)\\s+pregnant\\b",
            "\\b(?:during|while)\\s+(?:my\\s+)?pregnancy\\b",
            "\\b(i\\s*(?:have|had|am\\s+dealing\\s+with)|i\\W?m\\s+dealing\\s+with)\\b" +
                nearby + "\\b(?:eating\\s+disorder|starv\\w*|purg\\w*|not\\s+eating)\\b",
            "\\bi\\s*(?:haven'?t|have\\s+not)\\s+eaten\\b",
            "\\b(i\\s*(?:have|had|experienced|experience)|my)\\b" +
                nearby + "\\b(?:cardiac\\s+event|heart\\s+attack)\\b",
        ]
        let minorSafetyConcern =
            containsPattern("\\b(i\\s*am|i\\W?m|age(?:d)?|as\\s+a)\\s+1[0-7]\\b", in: text) ||
            containsPattern("\\bunder\\s+18\\b", in: text) ||
            containsPattern("\\b(?:i\\s*(?:am|\\W?m)\\s+a|as\\s+a)\\s+minor\\b", in: text)
        let strengthRisk =
            containsPattern("\\b(max|1\\s*rm|one[- ]rep|pr|personal\\s+record|heavy|heavier|attempt)\\b", in: text)

        guard redFlagPatterns.contains(where: { containsPattern($0, in: text) }) ||
            (minorSafetyConcern && strengthRisk) else {
            return nil
        }
        return medicalRedFlagResponseText()
    }

    private static func medicalRedFlagResponseText() -> String {
        return String(
            localized: """
            Stop the session now and seek medical care before training again. \
            If symptoms are severe or include chest pain, fainting, or severe \
            shortness of breath, use emergency care.
            """,
            comment: "Safety response when medical red-flag terms are detected in coach input"
        )
    }

    private static func hasRecoverySymptoms(_ text: String) -> Bool {
        recoverySymptomPatterns.contains { containsPattern($0, in: text) }
    }

    private static func hasCurrentRecoverySymptoms(inContext context: String) -> Bool {
        context
            .components(separatedBy: .newlines)
            .contains { line in
                let lowered = line.lowercased()
                guard !lowered.contains("pain-free"),
                      !lowered.contains("historical note"),
                      !lowered.contains("last year"),
                      !lowered.contains("prior ")
                else { return false }
                return hasRecoverySymptoms(line)
            }
    }

    private static func hasCurrentMedicalRedFlag(inContext context: String) -> Bool {
        context
            .components(separatedBy: .newlines)
            .contains { line in
                medicalRedFlagClauses(in: line).contains { clause in
                    let lowered = clause.lowercased()
                    guard !isStaleMedicalRedFlagLine(lowered),
                          !isNegatedMedicalRedFlagLine(lowered) else { return false }
                    return contextMedicalRedFlagPatterns.contains { containsPattern($0, in: clause) }
                }
            }
    }

    private static func medicalRedFlagClauses(in line: String) -> [String] {
        line
            .replacingOccurrences(
                of: #"(?i)\b(?:but|however)\b"#,
                with: ";",
                options: .regularExpression
            )
            .components(separatedBy: CharacterSet(charactersIn: ".;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isStaleMedicalRedFlagLine(_ loweredLine: String) -> Bool {
        [
            "historical note",
            "last year",
            "prior ",
            "previously cleared",
            "cleared by",
        ].contains { loweredLine.contains($0) }
    }

    private static func isNegatedMedicalRedFlagLine(_ loweredLine: String) -> Bool {
        [
            "no chest pain",
            "denies chest pain",
            "without chest pain",
            "not experiencing chest pain",
            "not having chest pain",
            "no dizziness",
            "denies dizziness",
            "without dizziness",
            "not dizzy",
            "not experiencing dizziness",
            "no lightheadedness",
            "denies lightheadedness",
            "not lightheaded",
            "no fainting",
            "denies fainting",
            "not fainting",
            "no syncope",
            "denies syncope",
            "without syncope",
            "not experiencing syncope",
            "did not pass out",
            "didn't pass out",
            "hasn't passed out",
            "no shortness of breath",
            "denies shortness of breath",
            "no trouble breathing",
            "not short of breath",
            "can breathe normally",
            "without breathing trouble",
            "not pregnant",
            "not pregnant now",
            "no pregnancy",
            "denies pregnancy",
            "no cardiac symptoms",
            "denies cardiac symptoms",
            "not experiencing cardiac symptoms",
            "no cardiac event",
            "denies cardiac event",
            "no heart attack",
            "denies heart attack",
            "no palpitations",
            "denies palpitations",
            "no arrhythmia",
            "denies arrhythmia",
            "not having chest pain or palpitations",
            "no eating disorder",
            "denies eating disorder",
            "not an eating disorder",
            "not restricting",
            "not purging",
            "denies purging",
            "no purging",
            "not starving",
            "eating normally",
            "symptoms resolved",
            "resolved symptoms",
        ].contains { loweredLine.contains($0) }
    }

    private static func containsPattern(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let recoverySymptomPatterns = [
        #"\bsick\b"#,
        #"\bill\b"#,
        #"\bcold\b"#,
        #"\bflu\b"#,
        #"\bfever\b"#,
        #"\bsore(?:ness)?\b"#,
        #"\btight(?:ness)?\b"#,
        #"\brun[- ]?down\b"#,
        #"\bslept\s+badly\b"#,
        #"\bbad\s+sleep\b"#,
        #"\bexhausted\b"#,
        #"\bdrained\b"#,
        #"\bbeat\s+up\b"#,
        #"\baches?\b"#,
        #"\bpain\b"#,
        #"\bhurts?\b"#,
        #"\binjur(?:y|ed)\b"#,
        #"\btweaked\b"#,
        #"\bstrain(?:ed)?\b"#,
        #"\bsharp\b"#,
        #"\btwinge\b"#,
        #"\bfighting\s+illness\b"#,
        #"\bsymptoms?\b"#,
        #"\bunder\s+the\s+weather\b"#,
    ]

    private static let contextMedicalRedFlagPatterns = [
        #"\bchest\s+pain\b"#,
        #"\bdizz(?:y|iness)\b"#,
        #"\blightheaded\b"#,
        #"\bfaint(?:ed|ing)?\b"#,
        #"\bsyncope\b"#,
        #"\bpassed\s+out\b"#,
        #"\bblacked\s+out\b"#,
        #"\b(?:severe\s+)?short(?:ness)?\s+of\s+breath\b"#,
        #"\b(can'?t|cannot)\s+breathe\b"#,
        #"\bhard\s+to\s+breathe\b"#,
        #"\bpregnan(?:t|cy)\b"#,
        #"\b(?:eating\s+disorder|starv\w*|purg\w*|not\s+eating)\b"#,
        #"\bhaven'?t\s+eaten\b"#,
        #"\b(?:cardiac\s+event|heart\s+attack)\b"#,
    ]

    private static func extractReadinessScore(from context: String) -> Int? {
        guard let range = context.range(of: "Readiness: ") else { return nil }
        let remainder = context[range.upperBound...]
        guard let slashRange = remainder.range(of: "/") else { return nil }
        let scoreString = String(remainder[remainder.startIndex..<slashRange.lowerBound])
        return Int(scoreString)
    }
}

public struct SafetyFilteredCoachProvider: AICoachProvider {
    private let base: AICoachProvider

    public init(base: AICoachProvider) {
        self.base = base
    }

    public func coachResponse(for prompt: String, context: String) async throws -> String {
        if let redFlagResponse = CoachSafetyFilter.medicalRedFlagResponse(prompt: prompt, context: context) {
            return redFlagResponse
        }
        let response = try await base.coachResponse(for: prompt, context: context)
        return CoachSafetyFilter.filteredResponse(prompt: prompt, context: context, response: response)
    }

    public func streamCoachResponse(for prompt: String, context: String) -> AsyncThrowingStream<String, Error> {
        if let redFlagResponse = CoachSafetyFilter.medicalRedFlagResponse(prompt: prompt, context: context) {
            return AsyncThrowingStream { continuation in
                continuation.yield(redFlagResponse)
                continuation.finish()
            }
        }

        guard CoachSafetyFilter.shouldBufferResponse(prompt: prompt, context: context) else {
            return base.streamCoachResponse(for: prompt, context: context)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var accumulated = ""
                    for try await chunk in base.streamCoachResponse(for: prompt, context: context) {
                        accumulated += chunk
                    }
                    let filtered = CoachSafetyFilter.filteredResponse(
                        prompt: prompt,
                        context: context,
                        response: accumulated
                    )
                    continuation.yield(filtered)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
