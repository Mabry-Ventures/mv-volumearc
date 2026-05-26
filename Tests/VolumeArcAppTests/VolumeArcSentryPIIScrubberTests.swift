#if canImport(Sentry)
import XCTest
import Sentry

/// VOL-72: verify the Sentry PII scrubber installed in
/// `VolumeArcSentryConfiguration.bootstrapIfNeeded` removes the things
/// it's supposed to and leaves the things it shouldn't touch alone.
///
/// Layered from cheap (pure string / dict helpers) up to real
/// `Event` / `Breadcrumb` instances, so a regression in any layer is
/// isolated to a small set of failing tests.
final class VolumeArcSentryPIIScrubberTests: XCTestCase {
    // MARK: - Text scrubbing (regexes)

    func testTextScrubReplacesSimpleEmailAddress() {
        let input = "Contact user@example.com for help."
        let output = SentryPIIScrubber.scrub(text: input)
        XCTAssertFalse(output.contains("user@example.com"))
        XCTAssertTrue(output.contains("[REDACTED]"))
        XCTAssertTrue(output.contains("Contact"))
        XCTAssertTrue(output.contains("for help"))
    }

    func testTextScrubReplacesPlusAddressingEmail() {
        let input = "jared+sentry@mabryventures.com reported a crash"
        let output = SentryPIIScrubber.scrub(text: input)
        XCTAssertFalse(output.contains("jared+sentry@mabryventures.com"))
        XCTAssertFalse(output.contains("mabryventures.com"))
        XCTAssertTrue(output.contains("[REDACTED]"))
        XCTAssertTrue(output.contains("reported a crash"))
    }

    func testTextScrubReplacesMultipleEmailsInSameString() {
        let input = "From a@x.io to b.c-d@y.co.uk"
        let output = SentryPIIScrubber.scrub(text: input)
        XCTAssertFalse(output.contains("a@x.io"))
        XCTAssertFalse(output.contains("b.c-d@y.co.uk"))
        XCTAssertTrue(output.contains("From [REDACTED] to [REDACTED]"))
    }

    func testTextScrubReplacesPhoneWithDashes() {
        let input = "Call 415-555-0199 to escalate"
        let output = SentryPIIScrubber.scrub(text: input)
        XCTAssertFalse(output.contains("415-555-0199"))
        XCTAssertTrue(output.contains("[REDACTED]"))
    }

    func testTextScrubReplacesInternationalPhone() {
        let input = "phone +44 7700 900123 inbound"
        let output = SentryPIIScrubber.scrub(text: input)
        XCTAssertFalse(output.contains("+44 7700 900123"))
        XCTAssertTrue(output.contains("[REDACTED]"))
    }

    func testTextScrubPreservesStackFrameLookingText() {
        // Stack-trace-ish text has colons, angle brackets, and file
        // paths — it must survive untouched.
        let input = "0x0000000104b8c0a0 -[NSArray count] (NSArray.m:93)"
        let output = SentryPIIScrubber.scrub(text: input)
        XCTAssertEqual(output, input)
    }

    func testTextScrubPreservesApplePaths() {
        // An Apple framework path contains `/` and `.` but no `@`, so
        // it should not match the email pattern.
        let input = "/Applications/Xcode.app/Contents/Developer/..."
        let output = SentryPIIScrubber.scrub(text: input)
        XCTAssertEqual(output, input)
    }

    func testTextScrubDoesNotTouchShortDigitStrings() {
        // Status codes, line numbers, retry counts — all numeric but
        // too short to plausibly be a phone number.
        let input = "Retry 3 of 5 after 500 error"
        let output = SentryPIIScrubber.scrub(text: input)
        XCTAssertEqual(output, input)
    }

    func testTextScrubPreservesEmptyString() {
        XCTAssertEqual(SentryPIIScrubber.scrub(text: ""), "")
    }

    // MARK: - Key-name matching

    func testKeyTriggersRedactionExactDeviceId() {
        XCTAssertTrue(SentryPIIScrubber.keyTriggersRedaction("device_id"))
        XCTAssertTrue(SentryPIIScrubber.keyTriggersRedaction("device_token"))
        XCTAssertTrue(SentryPIIScrubber.keyTriggersRedaction("apns_token"))
        XCTAssertTrue(SentryPIIScrubber.keyTriggersRedaction("push_token"))
    }

    func testKeyTriggersRedactionCaseInsensitiveDeviceId() {
        // `deviceId` (camelCase) should match because `deviceid` is in
        // the exact-key list after lowercasing.
        XCTAssertTrue(SentryPIIScrubber.keyTriggersRedaction("deviceId"))
        XCTAssertTrue(SentryPIIScrubber.keyTriggersRedaction("DEVICE_ID"))
    }

    func testKeyTriggersRedactionForEmailSubstring() {
        XCTAssertTrue(SentryPIIScrubber.keyTriggersRedaction("user_email"))
        XCTAssertTrue(SentryPIIScrubber.keyTriggersRedaction("DeviceEmail"))
        XCTAssertTrue(SentryPIIScrubber.keyTriggersRedaction("contactEmail"))
    }

    func testKeyTriggersRedactionForPhoneSubstring() {
        XCTAssertTrue(SentryPIIScrubber.keyTriggersRedaction("phone_number"))
        XCTAssertTrue(SentryPIIScrubber.keyTriggersRedaction("mobilePhone"))
    }

    func testKeyTriggersRedactionForSessionId() {
        XCTAssertTrue(SentryPIIScrubber.keyTriggersRedaction("session_id"))
        XCTAssertTrue(SentryPIIScrubber.keyTriggersRedaction("sessionId"))
        XCTAssertTrue(SentryPIIScrubber.keyTriggersRedaction("X-Session-Id"))
    }

    func testKeyTriggersRedactionForApiKey() {
        XCTAssertTrue(SentryPIIScrubber.keyTriggersRedaction("api_key"))
        XCTAssertTrue(SentryPIIScrubber.keyTriggersRedaction("apiKey"))
        XCTAssertTrue(SentryPIIScrubber.keyTriggersRedaction("X-API-KEY"))
    }

    func testKeyTriggersRedactionForTokenSubstring() {
        XCTAssertTrue(SentryPIIScrubber.keyTriggersRedaction("auth_token"))
        XCTAssertTrue(SentryPIIScrubber.keyTriggersRedaction("refreshToken"))
    }

    func testKeyTriggersRedactionFalseForBenignKeys() {
        XCTAssertFalse(SentryPIIScrubber.keyTriggersRedaction("user_id"))
        XCTAssertFalse(SentryPIIScrubber.keyTriggersRedaction("workout_count"))
        XCTAssertFalse(SentryPIIScrubber.keyTriggersRedaction("timestamp"))
        XCTAssertFalse(SentryPIIScrubber.keyTriggersRedaction("severity"))
    }

    // MARK: - Dict scrubbing

    func testScrubDictRedactsByKeyAndValue() {
        let input: [String: Any] = [
            "device_id": "ABCDEF-device-1234",
            "user_email": "me@example.com",
            "message": "Contact support at help@example.com",
            "workout_count": 5,
        ]
        let output = SentryPIIScrubber.scrub(dict: input)

        XCTAssertEqual(output["device_id"] as? String, "[REDACTED]")
        XCTAssertEqual(output["user_email"] as? String, "[REDACTED]")
        // Benign message field keeps its structure but has email scrubbed.
        XCTAssertEqual(output["message"] as? String, "Contact support at [REDACTED]")
        // Non-PII numeric preserved untouched.
        XCTAssertEqual(output["workout_count"] as? Int, 5)
    }

    func testScrubDictWalksNestedDicts() {
        let input: [String: Any] = [
            "user": [
                "id": "abc123",
                "email": "leak@example.com",
                "nested": [
                    "device_id": "deadbeef",
                    "note": "phone 415-555-0199",
                ],
            ],
        ]
        let output = SentryPIIScrubber.scrub(dict: input)

        guard let user = output["user"] as? [String: Any] else {
            XCTFail("nested user dict missing")
            return
        }
        XCTAssertEqual(user["id"] as? String, "abc123")
        XCTAssertEqual(user["email"] as? String, "[REDACTED]")

        guard let nested = user["nested"] as? [String: Any] else {
            XCTFail("double-nested dict missing")
            return
        }
        XCTAssertEqual(nested["device_id"] as? String, "[REDACTED]")
        XCTAssertEqual(nested["note"] as? String, "phone [REDACTED]")
    }

    func testScrubDictWalksArraysOfDicts() {
        let input: [String: Any] = [
            "breadcrumbs": [
                ["email": "one@example.com"],
                ["email": "two@example.com"],
            ],
        ]
        let output = SentryPIIScrubber.scrub(dict: input)

        guard let crumbs = output["breadcrumbs"] as? [[String: Any]] else {
            XCTFail("expected array of dicts")
            return
        }
        XCTAssertEqual(crumbs.count, 2)
        XCTAssertEqual(crumbs[0]["email"] as? String, "[REDACTED]")
        XCTAssertEqual(crumbs[1]["email"] as? String, "[REDACTED]")
    }

    func testScrubDictPreservesScalarTypes() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let input: [String: Any] = [
            "count": 42,
            "rate": 0.8,
            "active": true,
            "timestamp": timestamp,
        ]
        let output = SentryPIIScrubber.scrub(dict: input)

        XCTAssertEqual(output["count"] as? Int, 42)
        XCTAssertEqual(output["rate"] as? Double, 0.8)
        XCTAssertEqual(output["active"] as? Bool, true)
        XCTAssertEqual(output["timestamp"] as? Date, timestamp)
    }

    // MARK: - Event scrubbing

    func testScrubEventNilsUserEmailAndUsername() {
        let event = Event(level: .error)
        let user = User(userId: "user-abc")
        user.email = "leak@example.com"
        user.username = "volume-arc-user"
        user.ipAddress = "192.0.2.7"
        user.name = "Alex Example"
        event.user = user

        _ = SentryPIIScrubber.scrub(event: event)

        XCTAssertEqual(event.user?.userId, "user-abc", "userId must survive; only identifying PII is nilled")
        XCTAssertNil(event.user?.email)
        XCTAssertNil(event.user?.username)
        XCTAssertNil(event.user?.ipAddress)
        XCTAssertNil(event.user?.name)
    }

    func testScrubEventRedactsExtraDict() {
        let event = Event(level: .error)
        event.extra = [
            "device_id": "ABC-device-1234",
            "note": "email user@example.com had a problem",
            "count": 3,
        ]

        _ = SentryPIIScrubber.scrub(event: event)

        XCTAssertEqual(event.extra?["device_id"] as? String, "[REDACTED]")
        XCTAssertEqual(event.extra?["note"] as? String, "email [REDACTED] had a problem")
        XCTAssertEqual(event.extra?["count"] as? Int, 3)
    }

    func testScrubEventRedactsTags() {
        let event = Event(level: .error)
        event.tags = [
            "apns_token": "some-long-apns-token",
            "feature": "workout-logging",
            "session_id": "sess-abc-123",
        ]

        _ = SentryPIIScrubber.scrub(event: event)

        XCTAssertEqual(event.tags?["apns_token"], "[REDACTED]")
        XCTAssertEqual(event.tags?["feature"], "workout-logging")
        XCTAssertEqual(event.tags?["session_id"], "[REDACTED]")
    }

    func testScrubEventRedactsMessageBody() {
        let event = Event(level: .error)
        let message = SentryMessage(formatted: "initial")
        message.message = "Crash reported by user+tag@example.com on device"
        event.message = message

        _ = SentryPIIScrubber.scrub(event: event)

        XCTAssertEqual(
            event.message?.message,
            "Crash reported by [REDACTED] on device"
        )
    }

    func testScrubEventRedactsNestedContextDict() {
        let event = Event(level: .error)
        event.context = [
            "runtime": [
                "name": "iOS",
                "version": "26.0",
            ],
            "profile": [
                "email": "pii@example.com",
                "device_id": "device-xyz",
                "tier": "premium",
            ],
        ]

        _ = SentryPIIScrubber.scrub(event: event)

        let runtime = event.context?["runtime"]
        XCTAssertEqual(runtime?["name"] as? String, "iOS")
        XCTAssertEqual(runtime?["version"] as? String, "26.0")

        let profile = event.context?["profile"]
        XCTAssertEqual(profile?["email"] as? String, "[REDACTED]")
        XCTAssertEqual(profile?["device_id"] as? String, "[REDACTED]")
        XCTAssertEqual(profile?["tier"] as? String, "premium")
    }

    func testScrubEventRedactsRequestFieldsAndDropsCookies() {
        let event = Event(level: .error)
        let request = SentryRequest()
        request.url = "https://api.example.com/users/admin@example.com/profile"
        request.cookies = "session=abc123; email=user%40example.com"
        request.headers = [
            "Content-Type": "application/json",
            "X-Api-Key": "sk_live_abcdef",
        ]
        event.request = request

        _ = SentryPIIScrubber.scrub(event: event)

        XCTAssertNil(event.request?.cookies, "cookies are always dropped")
        XCTAssertEqual(
            event.request?.url,
            "https://api.example.com/users/[REDACTED]/profile"
        )
        XCTAssertEqual(event.request?.headers?["Content-Type"], "application/json")
        XCTAssertEqual(event.request?.headers?["X-Api-Key"], "[REDACTED]")
    }

    func testScrubEventPreservesNonPIIFields() {
        // Scrubbing must not mangle OS/version/environment metadata.
        let event = Event(level: .error)
        event.environment = "production"
        event.releaseName = "VolumeArc@1.2.3+456"
        event.dist = "456"
        event.platform = "cocoa"

        _ = SentryPIIScrubber.scrub(event: event)

        XCTAssertEqual(event.environment, "production")
        XCTAssertEqual(event.releaseName, "VolumeArc@1.2.3+456")
        XCTAssertEqual(event.dist, "456")
        XCTAssertEqual(event.platform, "cocoa")
    }

    // MARK: - Breadcrumb scrubbing

    func testScrubBreadcrumbDropsUserInputCategory() {
        let crumb = Breadcrumb(level: .info, category: "user-input")
        crumb.message = "User typed their email: pii@example.com"
        XCTAssertNil(SentryPIIScrubber.scrub(breadcrumb: crumb))
    }

    func testScrubBreadcrumbDropsCoachMemoryCategory() {
        let crumb = Breadcrumb(level: .info, category: "coach.memory")
        crumb.message = "Coach memory appended"
        XCTAssertNil(SentryPIIScrubber.scrub(breadcrumb: crumb))
    }

    func testScrubBreadcrumbDropsWorkoutNotesCategory() {
        let crumb = Breadcrumb(level: .info, category: "workout.notes")
        crumb.message = "Left knee felt sharp on set 3"
        XCTAssertNil(SentryPIIScrubber.scrub(breadcrumb: crumb))
    }

    func testScrubBreadcrumbDropsProfileNameCategory() {
        let crumb = Breadcrumb(level: .info, category: "profile.name")
        crumb.message = "Updated athlete name to Jane Lifter"
        XCTAssertNil(SentryPIIScrubber.scrub(breadcrumb: crumb))
    }

    func testScrubBreadcrumbKeepsOtherCategoriesButScrubsMessage() {
        let crumb = Breadcrumb(level: .info, category: "navigation")
        crumb.message = "Opened coach with email user@example.com"
        crumb.type = "navigation"
        let originalTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
        crumb.timestamp = originalTimestamp

        let output = SentryPIIScrubber.scrub(breadcrumb: crumb)
        XCTAssertNotNil(output)
        XCTAssertEqual(output?.category, "navigation")
        XCTAssertEqual(output?.type, "navigation")
        XCTAssertEqual(output?.timestamp, originalTimestamp)
        XCTAssertEqual(
            output?.message,
            "Opened coach with email [REDACTED]"
        )
    }

    func testScrubBreadcrumbScrubsDataDict() {
        let crumb = Breadcrumb(level: .info, category: "http")
        crumb.data = [
            "url": "https://api.example.com/?email=leak%40example.com",
            "device_id": "device-abc",
            "status_code": 200,
        ]

        let output = SentryPIIScrubber.scrub(breadcrumb: crumb)
        XCTAssertNotNil(output)
        XCTAssertEqual(output?.data?["device_id"] as? String, "[REDACTED]")
        XCTAssertEqual(output?.data?["status_code"] as? Int, 200)
        // URL query string contains an encoded email — host path survives.
        let url = output?.data?["url"] as? String ?? ""
        XCTAssertTrue(url.contains("api.example.com"))
    }

    func testScrubEventCompactsDroppedAttachedBreadcrumbs() {
        let event = Event(level: .error)
        let keeper = Breadcrumb(level: .info, category: "navigation")
        keeper.message = "opened dashboard"
        let dropper = Breadcrumb(level: .info, category: "user-input")
        dropper.message = "typed something"
        event.breadcrumbs = [keeper, dropper]

        _ = SentryPIIScrubber.scrub(event: event)

        XCTAssertEqual(event.breadcrumbs?.count, 1)
        XCTAssertEqual(event.breadcrumbs?.first?.category, "navigation")
    }
}
#endif
