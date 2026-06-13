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

    // Third-party pregnancy guard shared by the prompt-scan patterns
    // (redFlagPatterns) and the context-scan patterns
    // (contextMedicalRedFlagPatterns): "my wife is pregnant" routes to
    // normal coaching, a bare or first-person mention escalates.
    // Mirrored in relay/src/worker.ts.
    private static let thirdPartyPregnancyGuard =
        "(?<!\\b(?:wife|partner|girlfriend|husband|spouse|sister|mom|mother|daughter|friend|client|teammate|she)" +
        "\\s(?:is|was|might\\sbe|may\\sbe|could\\sbe|will\\sbe|just\\sgot|got|became)\\s)(?<!she'?s\\s)" +
        "(?<!\\b(?:wife|partner|girlfriend|husband|spouse|sister|mom|mother|daughter|friend|client|teammate)(?:'|\u{2019})s\\s)"
    private static let pregnancySubjectLookahead =
        "(?!\\s+(?:wife|partner|girlfriend|husband|spouse|sister|mom|mother|daughter|friend|client|teammate)\\b)"

    /// Built once: this array is consulted on every coach turn, and
    /// per-call string assembly was a measurable slice of the breached
    /// coach first-token budget (PR #363 perf, VOL-99).
    private static let redFlagPatterns: [String] = {
        let nearby = "[\\s\\S]{0,80}"
        // An unowned pregnancy term describes the asker ("20 weeks
        // pregnant and still squatting"), so pregnancy patterns exclude
        // third-party owners instead of demanding an explicit
        // first-person marker: a possessor immediately before the term
        // ("my wife is pregnant", "she's pregnant") or right after it
        // ("my pregnant wife") routes to normal coaching. Mirrored in
        // relay/src/worker.ts.
        let thirdPartyPregnancyGuard = Self.thirdPartyPregnancyGuard
        let pregnancySubjectLookahead = Self.pregnancySubjectLookahead
        return [
            "\\b(i\\s*(?:feel|felt|have|had|experienced|experience|got|gotten)|i\\W?m|i\\s+am|my)\\b" +
                nearby + "\\bchest\\s+pain\\b",
            "\\b(i\\s*(?:feel|felt|have|had|experienced|experience|got|gotten)|i\\W?m|i\\s+am|my)\\b" +
                nearby + "\\bpain\\s+in\\s+(?:(?:the|my|your|his|her|their|its)\\s+)?chest\\b",
            "\\b(i\\s*(?:feel|felt|have|had|experienced|experience|got|gotten)|i\\W?m|i\\s+am|my)\\b" +
                nearby + "\\bdizz(?:y|iness)\\b",
            "\\b(i\\s*(?:feel|felt|have|had|experienced|experience|got|gotten)|i\\W?m|i\\s+am|my)\\b" +
                nearby + "\\blightheaded\\b",
            "\\b(i\\s*(?:feel|felt|have|had|experienced|experience|got|gotten)|i\\W?m|i\\s+am|my)\\b" +
                nearby + "\\bfaint(?:ed|ing)?\\b",
            "\\b(i\\s*(?:passed\\s+out|blacked\\s+out|have\\s+syncope|had\\s+syncope)|i\\W?ve\\s+(?:passed|blacked)\\s+out)\\b",
            "\\b(i\\s*(?:feel|felt|have|had|experienced|experience|got|gotten)|i\\W?m|i\\s+am|my)\\b" +
                nearby +
                "\\b(?:severe\\s+)?short(?:ness)?\\s+of\\s+breath\\b",
            "\\b(i\\s*(?:can'?t|cannot)\\s+breathe|hard\\s+to\\s+breathe|" +
                "(?:having\\s+|have\\s+|had\\s+|got\\s+)?trouble\\s+breathing|" +
                "breathing\\s+trouble|struggling\\s+to\\s+breathe)\\b",
            // The wide gap means the guard must sit on the term itself:
            // "I am careful since my wife is pregnant" stays coaching.
            "\\b(i\\s*(?:am|might\\s+be|may\\s+be)|i\\W?m)\\b" + nearby +
                thirdPartyPregnancyGuard + "\\bpregnant\\b" + pregnancySubjectLookahead,
            thirdPartyPregnancyGuard + "\\b\\d+\\s+(?:weeks?|months?)\\s+pregnant\\b" + pregnancySubjectLookahead,
            // "while pregnant" / "during my pregnancy" — the adverbial
            // phrasing always describes the asker, so it needs no
            // first-person marker ("while my wife is pregnant" does not
            // match: the possessive consumes the optional "my" and the
            // next word must be the pregnancy term itself).
            "\\b(?:during|while)\\s+(?:my\\s+)?pregnan(?:cy|t)\\b",
            // PR #363 review (Codex P2 parity): proximity fallback for
            // phrasings the explicit patterns miss ("pregnant and still
            // chasing heavy squats"). Third-party ownership is excluded
            // by the guard; bare phrasing escalates.
            thirdPartyPregnancyGuard + "\\bpregnan(?:t|cy)\\b" + pregnancySubjectLookahead +
                nearby + "\\b(?:train|training|lift|lifting|heavy|squat|deadlift|workout)\\b",
            "\\b(i\\s*(?:have|had|am\\s+dealing\\s+with)|(?:i\\W?m|i\\s+am)\\s+dealing\\s+with)\\b" +
                nearby + "\\b(?:eating\\s+disorder|restrict\\w*|starv\\w*|purg\\w*|not\\s+eating)\\b",
            // Both branches require the eating verb — a bare "I haven't"
            // must never escalate ("I haven't trained in a week" is a
            // routine coaching prompt, not a disordered-eating signal).
            "\\bi\\s*(?:haven'?t|have\\s+not|hadn'?t)\\s+eaten\\b",
            "\\bi\\s*(?:didn'?t|did\\s+not)\\s+eat(?:en)?\\b",
            "\\b(?:restrict\\w*|skip(?:ping)?\\s+(?:meals?|food)|fast(?:ing|ed)?)\\b" +
                nearby + "\\b(?:cut|weight|fat|cardio|train|training|squat|lift|workout)\\b",
            "\\b(i\\s*(?:have|had|experienced|experience)|my)\\b" +
                nearby + "\\b(?:cardiac\\s+event|heart\\s+attack)\\b",
            "\\b(i\\s*(?:feel|felt|have|had|get|got|notice|noticed)|(?:i\\W?m|i\\s+am)\\s+having|my)\\b" +
                nearby + "\\b(?:palpitations?|arrhythmia)\\b",
        ]
    }()

    public static func medicalRedFlagResponse(from text: String) -> String? {
        let minorSafetyConcern =
            containsPattern("\\b(i\\s*am|i\\W?m|age(?:d)?|as\\s+a)\\s+1[0-7]\\b", in: text) ||
            containsPattern("\\bunder\\s+18\\b", in: text) ||
            containsPattern("\\b(?:i\\s*(?:am|\\W?m)\\s+a|as\\s+a)\\s+minor\\b", in: text)
        let strengthRisk =
            containsPattern("\\b(max|1\\s*rm|one[- ]rep|pr|personal\\s+record|heavy|heavier|attempt)\\b", in: text)

        guard hasMedicalRedFlag(in: text, matching: redFlagPatterns) ||
            (minorSafetyConcern && strengthRisk) else {
            return nil
        }
        return medicalRedFlagResponseText()
    }

    private static func hasMedicalRedFlag(in text: String, matching patterns: [String]) -> Bool {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if lines.contains(where: { hasMedicalRedFlagInLine($0, matching: patterns) }) {
            return true
        }

        for index in lines.indices.dropLast() {
            let line = lines[index]
            let nextLine = lines[index + 1]
            guard !line.isEmpty, !nextLine.isEmpty else { continue }
            if hasMedicalRedFlagInLine("\(line) \(nextLine)", matching: patterns) {
                return true
            }
        }
        return false
    }

    private static func hasMedicalRedFlagInLine(_ line: String, matching patterns: [String]) -> Bool {
        // PR #363 review (Codex P1): the clause splitter strips the
        // first-person subject from later clauses ("I have no chest pain
        // but dizziness" splits to "dizziness"), so the subject-dependent
        // prompt patterns can no longer match. Only clauses that FOLLOW a
        // negation-suppressed clause in a strictly-first-person line (not
        // "my", which also introduces third parties) fall back to the
        // subject-free symptom patterns used for context lines — scoping
        // the fallback this way keeps descriptive prose ("this tempo
        // block feels dizzying on paper") from escalating. Clauses that
        // name someone else's symptoms are excluded either way.
        let lineIsFirstPerson = containsPattern(#"\bi\b|\bi'm\b|\bi've\b"#, in: line)
        var sharedNegationCarries = false
        var followsSuppressedClause = false
        for clause in medicalRedFlagClauses(in: line) {
            if !clause.separatorAllowsSharedNegation {
                sharedNegationCarries = false
            }

            let lowered = clause.text.lowercased()
            if isStaleMedicalRedFlagLine(lowered) {
                sharedNegationCarries = false
                // PR #363 review (Codex P1): a stale clause suppresses
                // ITSELF, not what follows — "I had chest pain last year,
                // dizziness now during squats" must keep scanning the
                // subject-bare continuation through the same first-person
                // fallback negated clauses use.
                followsSuppressedClause = true
                continue
            }
            if isNegatedMedicalRedFlagLine(lowered) {
                sharedNegationCarries = isSharedNegationCarrier(lowered)
                followsSuppressedClause = true
                continue
            }
            if sharedNegationCarries,
               clause.separatorAllowsSharedNegation,
               isBareSharedNegationContinuation(lowered) {
                continue
            }
            sharedNegationCarries = false
            if patterns.contains(where: { containsPattern($0, in: clause.text) }) {
                return true
            }
            guard followsSuppressedClause, lineIsFirstPerson else { continue }
            let mentionsThirdParty = containsPattern(
                #"\b(?:my|his|her|their)\s+(?:wife|husband|partner|friend|buddy|client|coach|"#
                    + #"brother|sister|mom|mother|dad|father|son|daughter|teammate)\b"#,
                in: clause.text
            )
            if !mentionsThirdParty,
               contextMedicalRedFlagPatterns.contains(where: { containsPattern($0, in: clause.text) }) {
                return true
            }
        }
        return false
    }

    private static func medicalRedFlagResponseText() -> String {
        return String(
            localized: """
            Stop the session now and seek medical care before training again. \
            If symptoms are severe or include chest pain, fainting, or severe \
            shortness of breath, call 911 or your local emergency number.
            """,
            comment: "Safety response when medical red-flag terms are detected in coach input"
        )
    }

    private static func hasRecoverySymptoms(_ text: String) -> Bool {
        let scrubbed = strippingNegatedRecoveryCheckIns(text)
        return recoverySymptomPatterns.contains { containsPattern($0, in: scrubbed) }
    }

    /// "No pain today, can we add five pounds?" is a recovery check-in,
    /// not a symptom report — negated symptom mentions are removed
    /// before matching so they cannot arm conservative buffering or the
    /// clamp's symptom ceiling, while "knee pain" keeps full coverage.
    private static func strippingNegatedRecoveryCheckIns(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\b(?:no|not|without|zero|denies?|denied|free\s+of)\s+(?:any\s+|more\s+|new\s+)?"# +
                #"(?:pain|sore(?:ness)?|tight(?:ness)?|aches?|aching|injur(?:y|ies)|symptoms?|twinge|strain)\b"# +
                #"|\b(?:pain|sore(?:ness)?|tight(?:ness)?|injury|symptom)[-\s]free\b"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
    }

    /// A coach-authored memory line ("Coach said: ..."), optionally
    /// bulleted or "Memory:"-prefixed. Anchored to the line start so a
    /// mid-line mention does not hide a current symptom on the same line.
    /// Mirrored in relay/src/worker.ts.
    private static func isCoachAuthoredMemoryLine(_ line: String) -> Bool {
        containsPattern(#"^\s*(?:[-*]\s*)?(?:memory:\s*)?coach\s+said:"#, in: line)
    }

    private static func hasCurrentRecoverySymptoms(inContext context: String) -> Bool {
        context
            .components(separatedBy: .newlines)
            .filter { !isCoachAuthoredMemoryLine($0) }
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
        // Coach-authored memory lines are excluded: a prior safety reply
        // contains the very phrases these scans match, and one red-flag
        // turn must not poison every later benign turn until the memory
        // ages out. Athlete-authored lines keep full coverage.
        context
            .components(separatedBy: .newlines)
            .filter { !isCoachAuthoredMemoryLine($0) }
            .contains { line in
                var sharedNegationCarries = false
                for clause in medicalRedFlagClauses(in: line) {
                    if !clause.separatorAllowsSharedNegation {
                        sharedNegationCarries = false
                    }

                    let lowered = clause.text.lowercased()
                    if isStaleMedicalRedFlagLine(lowered) {
                        sharedNegationCarries = false
                        continue
                    }
                    if isNegatedMedicalRedFlagLine(lowered) {
                        sharedNegationCarries = isSharedNegationCarrier(lowered)
                        continue
                    }
                    if sharedNegationCarries,
                       clause.separatorAllowsSharedNegation,
                       isBareSharedNegationContinuation(lowered) {
                        continue
                    }
                    sharedNegationCarries = false
                    if contextMedicalRedFlagPatterns.contains(where: { containsPattern($0, in: clause.text) }) {
                        return true
                    }
                }
                return false
            }
    }

    private struct MedicalRedFlagClause {
        let text: String
        let separatorAllowsSharedNegation: Bool
    }

    private static func medicalRedFlagClauses(in line: String) -> [MedicalRedFlagClause] {
        let pattern = #"(?i)\b(?:but|however|and|or)\b|[.,;]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? [] : [
                MedicalRedFlagClause(text: trimmed, separatorAllowsSharedNegation: false)
            ]
        }

        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        var clauses: [MedicalRedFlagClause] = []
        var start = 0
        var nextSeparatorAllowsSharedNegation = false

        for match in regex.matches(in: line, range: range) {
            let clauseRange = NSRange(location: start, length: match.range.location - start)
            let clause = nsLine
                .substring(with: clauseRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !clause.isEmpty {
                clauses.append(
                    MedicalRedFlagClause(
                        text: clause,
                        separatorAllowsSharedNegation: nextSeparatorAllowsSharedNegation
                    )
                )
            }

            let separator = nsLine.substring(with: match.range).lowercased()
            nextSeparatorAllowsSharedNegation = separator == "," || separator == "and" || separator == "or"
            start = match.range.location + match.range.length
        }

        let tail = nsLine
            .substring(from: start)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            clauses.append(
                MedicalRedFlagClause(
                    text: tail,
                    separatorAllowsSharedNegation: nextSeparatorAllowsSharedNegation
                )
            )
        }
        return clauses
    }

    private static func isStaleMedicalRedFlagLine(_ loweredLine: String) -> Bool {
        // PR #363 review (CodeRabbit, critical): "prior cardiac event" /
        // "prior heart attack" are hard red flags in the safety contract —
        // the blanket "prior " staleness match must never swallow them.
        if containsPattern(#"\bprior\s+(?:cardiac|heart)\b"#, in: loweredLine) {
            return false
        }
        return [
            "historical note",
            "last year",
            "prior ",
            "previously cleared",
            "cleared by",
        ].contains { loweredLine.contains($0) }
    }

    private static func isNegatedMedicalRedFlagLine(_ loweredLine: String) -> Bool {
        negatedMedicalRedFlagPhrases.contains { loweredLine.contains($0) }
    }

    private static let negatedMedicalRedFlagPhrases: [String] = [
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
            "no prior cardiac event",
            "denies prior cardiac event",
            "no prior heart attack",
            "denies prior heart attack",
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
    ]

    private static func isSharedNegationCarrier(_ loweredLine: String) -> Bool {
        let negatedStatePattern =
            #"\bnot\s+(?:experiencing|having|short|lightheaded|fainting|"# +
            #"pregnant|restricting|purging|starving)\b"#
        return containsPattern(#"\b(?:no|denies|without)\b"#, in: loweredLine) ||
            containsPattern(negatedStatePattern, in: loweredLine)
    }

    private static func isBareSharedNegationContinuation(_ loweredLine: String) -> Bool {
        var trimmed = loweredLine.trimmingCharacters(in: .whitespacesAndNewlines)
        // PR #363 review (Codex P2): a pure time qualifier on the tail of a
        // shared-negation list ("no chest pain or dizziness today") still
        // describes the negated check-in, so strip it before matching.
        // Event markers (after/felt/mid-set/...) stay escalation-worthy —
        // "dizziness after squats" is a fresh occurrence, not a qualifier.
        let trailingTimeQualifier =
            #"(?:\s+(?:today|now|right\s+now|currently|at\s+the\s+moment|"# +
            #"this\s+(?:morning|afternoon|evening|week)))+$"#
        trimmed = trimmed.replacingOccurrences(
            of: trailingTimeQualifier,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let currentEventPattern =
            #"\b(?:after|during|while|reported|"# +
            #"showed|shows|felt|feel|got|became|under\s+load|episode|"# +
            #"mid[- ]?set|following)\b"#
        guard !containsPattern(
            currentEventPattern,
            in: trimmed
        ) else {
            return false
        }

        return [
            #"^(?:severe\s+)?short(?:ness)?\s+of\s+breath$"#,
            #"^dizz(?:y|iness)$"#,
            #"^lightheaded(?:ness)?$"#,
            #"^fainting$"#,
            #"^syncope$"#,
            #"^chest\s+pain$"#,
            #"^pain\s+in\s+(?:(?:the|my|your|his|her|their|its)\s+)?chest$"#,
            #"^pregnan(?:t|cy)$"#,
            #"^eating\s+disorder$"#,
            #"^(?:cardiac\s+event|heart\s+attack|palpitations|arrhythmia)$"#,
        ].contains { containsPattern($0, in: trimmed) }
    }

    // Compiled-regex cache. `String.range(of:options:)` recompiles the
    // ICU pattern on every call, and the safety scans run hundreds of
    // matches per coach turn across per-clause and per-line loops —
    // enough to put coach first-token p50 over its budget (PR #363
    // perf, VOL-99). Scans run from the main actor and streaming tasks.
    // NSCache is documented thread-safe ("you can add, remove, and query
    // items in the cache from different threads without having to lock
    // the cache yourself"), which is exactly the shared-mutable-state
    // guarantee the strict-concurrency checker can't see.
    nonisolated(unsafe) private static let compiledPatternCache = NSCache<NSString, NSRegularExpression>()

    private static func containsPattern(_ pattern: String, in text: String) -> Bool {
        let key = pattern as NSString
        let regex: NSRegularExpression
        if let cached = compiledPatternCache.object(forKey: key) {
            regex = cached
        } else if let compiled = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            compiledPatternCache.setObject(compiled, forKey: key)
            regex = compiled
        } else {
            return false
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
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
        #"\bpain\s+in\s+(?:(?:the|my|your|his|her|their|its)\s+)?chest\b"#,
        #"\bdizz(?:y|iness)\b"#,
        #"\blightheaded\b"#,
        #"\bfaint(?:ed|ing)?\b"#,
        #"\bsyncope\b"#,
        #"\bpassed\s+out\b"#,
        #"\bblacked\s+out\b"#,
        #"\b(?:severe\s+)?short(?:ness)?\s+of\s+breath\b"#,
        #"\b(can'?t|cannot)\s+breathe\b"#,
        #"\bhard\s+to\s+breathe\b"#,
        Self.thirdPartyPregnancyGuard + #"\bpregnan(?:t|cy)\b"# + Self.pregnancySubjectLookahead,
        #"\b(?:eating\s+disorder|restrict\w*|starv\w*|purg\w*|not\s+eating)\b"#,
        #"\bhaven'?t\s+eaten\b"#,
        #"\bhadn'?t\s+eaten\b"#,
        #"\b(?:didn'?t|did\s+not)\s+eat(?:en)?\b"#,
        #"\b(?:cardiac\s+event|heart\s+attack)\b"#,
        #"\b(?:palpitations?|arrhythmia)\b"#,
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
    private let telemetrySink: (any TelemetrySink)?

    public init(base: AICoachProvider, telemetrySink: (any TelemetrySink)? = nil) {
        self.base = base
        self.telemetrySink = telemetrySink
    }

    public func coachResponse(for prompt: String, context: String) async throws -> String {
        if let redFlagResponse = CoachSafetyFilter.medicalRedFlagResponse(prompt: prompt, context: context) {
            recordSafetyEvent(name: "gate.short_circuit", path: "non_streaming")
            return redFlagResponse
        }
        let response = try await base.coachResponse(for: prompt, context: context)
        let filtered = CoachSafetyFilter.filteredResponse(prompt: prompt, context: context, response: response)
        if filtered != response {
            recordSafetyEvent(name: "filter.replaced", path: "non_streaming")
        }
        return filtered
    }

    public func streamCoachResponse(for prompt: String, context: String) -> AsyncThrowingStream<String, Error> {
        if let redFlagResponse = CoachSafetyFilter.medicalRedFlagResponse(prompt: prompt, context: context) {
            recordSafetyEvent(name: "gate.short_circuit", path: "streaming")
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
                    if filtered != accumulated {
                        recordSafetyEvent(name: "filter.replaced", path: "streaming")
                    }
                    continuation.yield(filtered)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// VOL-286: safety interventions are observable without ever logging
    /// prompt or response content — names and paths only.
    private func recordSafetyEvent(name: String, path: String) {
        telemetrySink?.record(TelemetryEvent(
            category: "coach.safety",
            name: name,
            severity: .warning,
            message: "Coach safety boundary intervened.",
            metadata: ["path": path]
        ))
    }
}
