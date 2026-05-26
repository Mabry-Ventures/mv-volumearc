#if canImport(Sentry)
import Foundation
import Sentry

/// Scrubs personally identifiable information from Sentry events and
/// breadcrumbs before they leave the device.
///
/// VOL-72. Installed via `options.beforeSend` and `options.beforeBreadcrumb`
/// on the Sentry SDK. Two layers:
///
/// - `scrub(event:)` walks the event's message, user, tags, extra, context,
///   request, and breadcrumbs, replacing email/phone/device-identifier
///   patterns with `[REDACTED]` and nilling `user.email` / `user.username`
///   / `user.ipAddress` entirely (the user object's PII fields are not
///   regex-candidate strings — they're structured fields that should not
///   leave the device at all).
/// - `scrub(breadcrumb:)` drops any breadcrumb from a deny-listed category
///   (`user-input`, `coach.memory`) by returning nil, and otherwise
///   scrubs `message` and `data` the same way.
///
/// Stack traces, OS metadata, app version, breadcrumb timestamps, and
/// category/type tags are preserved untouched so crashes remain
/// actionable.
enum SentryPIIScrubber {
    // MARK: - Configuration

    /// Redaction marker used in place of scrubbed values. Preserving the
    /// key with a marker (rather than deleting it outright) keeps the
    /// event structure intact for debugging — a missing `extra.user_email`
    /// looks like a schema change; `extra.user_email = "[REDACTED]"`
    /// looks like what it is.
    static let redactionMarker = "[REDACTED]"

    /// Breadcrumb categories that are dropped entirely. These are
    /// user-generated content streams where the payload is intrinsically
    /// PII-bearing — scrubbing them field-by-field is worse than dropping
    /// the breadcrumb, because the structural context (which field the
    /// user typed into) is itself a leak.
    static let breadcrumbCategoryDenyList: Set<String> = [
        "user-input",
        "coach.memory",
        "profile.name",
        "workout.notes",
    ]

    /// Exact-match keys whose values are always redacted, regardless of
    /// content. These are device/session identifiers that are never
    /// actionable in a crash report.
    static let redactedExactKeys: Set<String> = [
        "device_id",
        "deviceid",
        "device_token",
        "apns_token",
        "push_token",
    ]

    /// Case-insensitive substrings that, if contained in a key name, cause
    /// the value to be redacted. Broader than the exact-match list so we
    /// catch variants like `DeviceEmail`, `session_id`, `sessionId`, or
    /// `api_key`.
    static let redactedKeySubstrings: [String] = [
        "email",
        "phone",
        "token",
        "session_id",
        "sessionid",
        "api_key",
        "apikey",
    ]

    // MARK: - Event scrubbing

    /// Scrub an event in place and return it. Never returns nil — we
    /// want the crash report to reach Sentry even if the payload was
    /// entirely PII; we just want the PII gone.
    static func scrub(event: Event) -> Event {
        // Message body. `SentryMessage.formatted` is read-only and derived
        // from `message`/`params` at serialize time, so scrubbing the raw
        // `message` is enough — we don't need to rebuild `formatted` here.
        if let message = event.message, let raw = message.message {
            message.message = scrub(text: raw)
        }

        // User object — these fields are categorically unwelcome in
        // crashes. Nil them rather than regex-scrubbing so there's no
        // residual like "[REDACTED]" for the Sentry UI to tag-group on.
        if let user = event.user {
            user.email = nil
            user.username = nil
            user.ipAddress = nil
            user.name = nil
            user.data = user.data.map { scrub(dict: $0) }
        }

        // Tags: string:string, scrubbed by key and value.
        if let tags = event.tags {
            event.tags = scrubStringStringDict(tags)
        }

        // Extra: string:Any, recursively walked.
        if let extra = event.extra {
            event.extra = scrub(dict: extra)
        }

        // Context: string:(string:Any), also recursively walked.
        if let context = event.context {
            var scrubbedContext: [String: [String: Any]] = [:]
            for (ctxKey, ctxDict) in context {
                scrubbedContext[ctxKey] = scrub(dict: ctxDict)
            }
            event.context = scrubbedContext
        }

        // Request: URL, headers, cookies, body size.
        if let request = event.request {
            if let url = request.url {
                request.url = scrub(text: url)
            }
            if let queryString = request.queryString {
                request.queryString = scrub(text: queryString)
            }
            if let fragment = request.fragment {
                request.fragment = scrub(text: fragment)
            }
            // Cookies are always PII — drop entirely.
            request.cookies = nil
            if let headers = request.headers {
                request.headers = scrubStringStringDict(headers)
            }
        }

        // Breadcrumbs attached to the event get the same treatment as
        // live breadcrumbs. `scrub(breadcrumb:)` may return nil to drop
        // the breadcrumb entirely.
        if let breadcrumbs = event.breadcrumbs {
            event.breadcrumbs = breadcrumbs.compactMap { scrub(breadcrumb: $0) }
        }

        return event
    }

    // MARK: - Breadcrumb scrubbing

    /// Scrub a breadcrumb. Returns nil if the breadcrumb should be
    /// dropped entirely (deny-listed category). Otherwise returns the
    /// scrubbed breadcrumb.
    static func scrub(breadcrumb: Breadcrumb) -> Breadcrumb? {
        if breadcrumbCategoryDenyList.contains(breadcrumb.category) {
            return nil
        }

        if let message = breadcrumb.message {
            breadcrumb.message = scrub(text: message)
        }

        if let data = breadcrumb.data {
            breadcrumb.data = scrub(dict: data)
        }

        return breadcrumb
    }

    // MARK: - Internal helpers (exposed for testing)

    /// Scrub a free-form string: emails, phones, etc. Stack trace lines
    /// and file paths are left alone — regexes only match the specific
    /// PII shapes, so e.g. `/Applications/Xcode.app/...` doesn't get
    /// touched.
    static func scrub(text: String) -> String {
        var scrubbed = text
        scrubbed = emailRegex.stringByReplacingMatches(
            in: scrubbed,
            options: [],
            range: NSRange(scrubbed.startIndex..., in: scrubbed),
            withTemplate: redactionMarker
        )
        // Phone scrubbing replaces matches in reverse so later edits
        // don't shift earlier NSRanges. Skips any match whose context
        // looks like a hex address (`0x...`) so stack-trace lines and
        // pointer values are preserved.
        let phoneRange = NSRange(scrubbed.startIndex..., in: scrubbed)
        let matches = phoneRegex.matches(in: scrubbed, options: [], range: phoneRange)
        for match in matches.reversed() where !isHexAddressContext(scrubbed, match: match.range) {
            if let substringRange = Range(match.range, in: scrubbed) {
                scrubbed.replaceSubrange(substringRange, with: redactionMarker)
            }
        }
        return scrubbed
    }

    /// Walk an arbitrary `[String: Any]` dict and scrub values. Exposed
    /// so tests can exercise the key-matching and recursive-descent
    /// logic without instantiating Sentry types. Also reused internally
    /// by event/breadcrumb scrubbing.
    static func scrub(dict: [String: Any]) -> [String: Any] {
        var output: [String: Any] = [:]
        for (key, value) in dict {
            if keyTriggersRedaction(key) {
                output[key] = redactionMarker
                continue
            }

            output[key] = scrub(value: value)
        }
        return output
    }

    /// Whether a key name alone is enough to redact its value, before
    /// looking at the value's contents.
    ///
    /// Both hyphens and underscores in the input key are normalized to
    /// underscores before matching, so `X-Api-Key`, `X_API_KEY`, and
    /// `apikey` all hit `api_key`. This lets HTTP-style headers and
    /// snake_case extras share the same deny-list.
    static func keyTriggersRedaction(_ key: String) -> Bool {
        let normalized = key.lowercased().replacingOccurrences(of: "-", with: "_")
        if redactedExactKeys.contains(normalized) {
            return true
        }
        for substring in redactedKeySubstrings where normalized.contains(substring) {
            return true
        }
        return false
    }

    // MARK: - Private

    /// Returns `true` when the candidate match is likely a hex address
    /// rather than a phone number — specifically, when the 2 characters
    /// immediately preceding the match are `0x` (case-insensitive),
    /// which is the standard prefix for hex-formatted pointers that
    /// show up in stack traces and debug output.
    private static func isHexAddressContext(_ haystack: String, match: NSRange) -> Bool {
        guard match.location >= 2 else { return false }
        let prefixRange = NSRange(location: match.location - 2, length: 2)
        guard let range = Range(prefixRange, in: haystack) else { return false }
        let prefix = haystack[range].lowercased()
        return prefix == "0x"
    }

    /// Recursive scrub for an arbitrary value inside a dict. Strings are
    /// regex-scrubbed; nested dicts/arrays are walked; everything else
    /// passes through unchanged (so numbers, bools, dates survive).
    private static func scrub(value: Any) -> Any {
        if let string = value as? String {
            return scrub(text: string)
        }
        if let nested = value as? [String: Any] {
            return scrub(dict: nested)
        }
        if let array = value as? [Any] {
            return array.map { scrub(value: $0) }
        }
        return value
    }

    /// Tag-style `[String: String]` dicts. Matches the stricter type
    /// Sentry uses for `event.tags` and `request.headers`.
    private static func scrubStringStringDict(_ dict: [String: String]) -> [String: String] {
        var output: [String: String] = [:]
        for (key, value) in dict {
            if keyTriggersRedaction(key) {
                output[key] = redactionMarker
            } else {
                output[key] = scrub(text: value)
            }
        }
        return output
    }

    /// Email regex. Matches the common `local@domain.tld` shape, where
    /// local allows `+-._` (so plus-addressing survives detection) and
    /// domain has at least one dot. Deliberately conservative — we're
    /// not trying to match RFC 5322; we're trying to catch strings a
    /// human would call an email without false-positiving on UUIDs.
    private static let emailRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"[\w.+-]+@[\w-]+\.[\w.-]+"#, options: [])
    }()

    /// Phone regex. Conservative: at least 9 digits total, optional
    /// leading `+`, with `- . ( ) space` as permitted separators. Won't
    /// match short codes or 8-digit numbers, won't match 32-hex device
    /// tokens (no separators), won't match stack-trace addresses
    /// (`0x...`).
    private static let phoneRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"\+?\d[\d\s\-().]{7,}\d"#, options: [])
    }()
}
#endif
