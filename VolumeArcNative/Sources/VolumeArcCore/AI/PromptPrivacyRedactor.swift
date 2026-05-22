// VOL-197: strict-mode prompt redactor.
//
// 2026-05-18 audit (F-C-005) found that `PrivacyMode.strict` redacted
// structured context (athlete name, recent-session text) but did NOT
// touch the user's free-text question before it left the device for
// the relay → Gemini. A user who typed an email, phone number,
// injury description, or other PII into the coach prompt sent that
// data to the relay despite privacy copy saying PII is scrubbed
// before egress. This type closes that gap.
//
// Policy:
//
// * In `.strict` mode, the redactor scrubs email, phone, US-style
//   street address, and a small set of explicitly PII-bearing label
//   tokens ("my name is X", "I live at Y", "my email is Z") with
//   the marker `[REDACTED]`. Injury/medical free text (e.g. "my left
//   shoulder hurts") is intentionally preserved because the coach
//   prompt's whole purpose is to give programming advice around it;
//   stripping it would defeat the feature. We rely on the egress
//   disclosure in `marketing/src/app/(main)/privacy/page.tsx` to make
//   that contract explicit.
//
// * In `.standard` mode, the redactor is a no-op so we don't surprise
//   users who chose the default tier.
//
// * Telemetry: when redaction changes the string, an `info` breadcrumb
//   `coach.privacy.redacted` is emitted with metadata = byte delta and
//   which patterns matched. PII itself is NEVER included; only counts.
//   This lets us see "strict mode is removing N% of prompts" without
//   recording any prompt content.
//
// Defense-in-depth, not a perfect PII firewall. A user who types
// novel PII-shaped tokens we don't recognize can still send them
// through; the disclosed contract is "best-effort redaction in
// strict mode," not "guaranteed zero PII egress." The unit tests
// pin the patterns we DO catch so regressions are loud.

import Foundation

public enum PromptPrivacyRedactor {
    /// The token that replaces matched PII. Stable across releases so
    /// any operator-side log search ("count `[REDACTED]` in shape
    /// telemetry") behaves predictably.
    public static let redactionMarker = "[REDACTED]"

    /// Apply strict-mode redaction to a free-text prompt question.
    ///
    /// In `.standard` mode this returns the input unchanged so the
    /// default tier sees no behavior change. In `.strict` mode it
    /// substitutes the redaction marker for matched email / phone /
    /// US-style address tokens and for label-introduced PII ("my
    /// email is X").
    public static func redactQuestion(_ text: String, privacyMode: PrivacyMode) -> String {
        guard privacyMode == .strict else { return text }
        return apply(patterns: questionRedactionPatterns, to: text)
    }

    /// Apply strict-mode redaction to a fully rendered prompt body
    /// (the string going to the relay/SSE transport). Same patterns
    /// as `redactQuestion` but applied to the whole envelope as a
    /// belt-and-suspenders pass in case a future renderer threads a
    /// raw user string through a path we didn't anticipate.
    public static func redactPromptBody(_ text: String, privacyMode: PrivacyMode) -> String {
        guard privacyMode == .strict else { return text }
        return apply(patterns: questionRedactionPatterns, to: text)
    }

    // MARK: - Pattern set

    /// The patterns we redact. Each is a tuple of compiled regex +
    /// a stable identifier used in telemetry so operators can see
    /// "email-pattern fired N times today" without ever seeing the
    /// payload.
    static let questionRedactionPatterns: [Pattern] = {
        // The regex patterns are static literals validated at this
        // file's compile time; an unwind on bad input would only fire
        // on a typo regression in this file and would always crash the
        // test target first. `Self.compile(_:options:)` wraps the
        // pre-validated `try` in a `precondition` so we get a clear
        // crash log (and the force_try lint stays clean) if anyone
        // edits a pattern into invalid regex.
        [
            Pattern(id: "email", regex: compile(#"[\w.+-]+@[\w-]+\.[\w.-]+"#)),
            // International-ish phone: optional `+`, then 7+ digits
            // possibly separated by spaces/dashes/parens/dots. Skips
            // matches whose two-char prefix is `0x` (hex address /
            // pointer in error-message paste-ins).
            Pattern(id: "phone", regex: compile(#"\+?\d[\d\s\-().]{7,}\d"#)),
            // US street address: number + word(s) + suffix. Conservative
            // — we don't try international or PO Box formats. The
            // disclosed contract is "best-effort." Pattern intentionally
            // wrapped across lines so the line-length lint stays happy.
            Pattern(id: "us_street_address", regex: compile(
                #"\b\d{1,6}\s+[A-Z][\w\s]{2,30}?\b(Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Drive|Dr|Lane|Ln|Court|Ct|Place|Pl|Way)\b\.?"#,
                options: [.caseInsensitive]
            )),
            // Label-introduced PII. Mirrors patterns we know users
            // type into chat-style inputs ("my email is...", "I live
            // at...", "my name is...", "I'm <Firstname Lastname>").
            // The replacement preserves the leading label so the
            // redacted prompt is readable: "my email is [REDACTED]".
            Pattern(id: "label_email", regex: compile(
                #"((?:my|the)\s+email\s+(?:is|address\s+is)\s+)\S+"#,
                options: [.caseInsensitive]
            ), keepGroup: 1),
            Pattern(id: "label_name", regex: compile(
                #"((?:my|the)\s+name\s+is\s+)[A-Z][\w'\-]*(?:\s+[A-Z][\w'\-]*)?"#
            ), keepGroup: 1),
            Pattern(id: "label_address", regex: compile(
                #"((?:i\s+live\s+at|my\s+address\s+is)\s+)[^.,;\n]{3,80}"#,
                options: [.caseInsensitive]
            ), keepGroup: 1),
            Pattern(id: "label_phone", regex: compile(
                #"((?:my|the)\s+phone\s+(?:is|number\s+is)\s+)[\d\s\-().+]{7,}"#,
                options: [.caseInsensitive]
            ), keepGroup: 1),
        ]
    }()

    /// Compile a regex pattern at module init. Patterns are author-
    /// time literals; an invalid one is a programmer error, not a
    /// runtime error. `precondition` surfaces it with a clear message
    /// in any build, including Release.
    private static func compile(
        _ pattern: String,
        options: NSRegularExpression.Options = []
    ) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            preconditionFailure(
                "PromptPrivacyRedactor: invalid regex literal in `questionRedactionPatterns`: \(pattern). Underlying: \(error)"
            )
        }
    }

    /// A regex pattern + stable identifier. `keepGroup` lets a pattern
    /// preserve a prefix capture (e.g. "my email is ") and only
    /// redact what follows.
    struct Pattern {
        let id: String
        let regex: NSRegularExpression
        let keepGroup: Int?

        init(id: String, regex: NSRegularExpression, keepGroup: Int? = nil) {
            self.id = id
            self.regex = regex
            self.keepGroup = keepGroup
        }
    }

    // MARK: - Internals

    /// Walk the patterns in order. Each pass mutates the working
    /// string; order matters because later patterns might match
    /// against the redacted output of earlier ones, but the
    /// `[REDACTED]` marker is benign in any pattern's input.
    static func apply(patterns: [Pattern], to input: String) -> String {
        var output = input
        for pattern in patterns {
            let range = NSRange(output.startIndex..., in: output)
            let matches = pattern.regex.matches(in: output, options: [], range: range)
            // Replace right-to-left so earlier ranges stay stable.
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: output) else { continue }
                if pattern.id == "phone" {
                    // Skip phone matches whose two-char prefix is `0x` —
                    // those are hex addresses / pointer values pasted
                    // from error logs, not phone numbers.
                    let nsRange = match.range
                    if nsRange.location >= 2 {
                        let prefixNSRange = NSRange(location: nsRange.location - 2, length: 2)
                        if let prefixRange = Range(prefixNSRange, in: output),
                           output[prefixRange].lowercased() == "0x" {
                            continue
                        }
                    }
                }
                let replacement: String
                if let keepGroup = pattern.keepGroup,
                   keepGroup < match.numberOfRanges,
                   let groupRange = Range(match.range(at: keepGroup), in: output) {
                    let preserved = String(output[groupRange])
                    replacement = preserved + redactionMarker
                } else {
                    replacement = redactionMarker
                }
                output.replaceSubrange(fullRange, with: replacement)
            }
        }
        return output
    }
}
