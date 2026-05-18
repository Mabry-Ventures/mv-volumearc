// VOL-197: contract tests for `PromptPrivacyRedactor`. These pin the
// patterns the strict-mode redactor catches so a future regex change
// can't silently weaken what the user-facing privacy copy promises.
//
// Audit reference: F-C-005 in 2026-05-18 REPORT.md.

import XCTest
@testable import VolumeArcCore

final class PromptPrivacyRedactorTests: XCTestCase {

    // MARK: - Standard mode is a no-op

    func testStandardModeReturnsInputUnchanged() {
        let inputs = [
            "my email is jared@mabryventures.com",
            "+1 (615) 555-0123",
            "I live at 123 Music Square Nashville TN",
            "my name is Jared Mabry",
            "shoulder hurts on bench press",
        ]
        for input in inputs {
            XCTAssertEqual(
                PromptPrivacyRedactor.redactQuestion(input, privacyMode: .standard),
                input,
                "Standard mode must pass through input unchanged: \(input)"
            )
        }
    }

    // MARK: - Email patterns

    func testStrictRedactsBareEmail() {
        let out = PromptPrivacyRedactor.redactQuestion(
            "should I push today? reach me at jared@mabryventures.com",
            privacyMode: .strict
        )
        XCTAssertFalse(out.contains("jared@mabryventures.com"))
        XCTAssertTrue(out.contains("[REDACTED]"))
    }

    func testStrictRedactsLabelIntroducedEmail() {
        let out = PromptPrivacyRedactor.redactQuestion(
            "my email is foo@bar.example",
            privacyMode: .strict
        )
        XCTAssertFalse(out.contains("foo@bar.example"))
        XCTAssertTrue(out.contains("my email is [REDACTED]"),
                      "Expected the 'my email is ' prefix preserved with the value redacted, got: \(out)")
    }

    // MARK: - Phone patterns

    func testStrictRedactsUSPhone() {
        let out = PromptPrivacyRedactor.redactQuestion(
            "call me at +1 (615) 555-0123 after this set",
            privacyMode: .strict
        )
        XCTAssertFalse(out.contains("555-0123"))
        XCTAssertFalse(out.contains("(615)"))
        XCTAssertTrue(out.contains("[REDACTED]"))
    }

    func testStrictPreservesHexAddressLookalike() {
        // A hex pointer pasted from a crash log should not get
        // misclassified as a phone number. The "0x" prefix is the
        // disambiguating signal.
        let out = PromptPrivacyRedactor.redactQuestion(
            "EXC_BAD_ACCESS at 0x1234567890ab in the watchKit extension",
            privacyMode: .strict
        )
        XCTAssertTrue(out.contains("0x1234567890ab"), "0x-prefixed hex pointer must not be redacted as a phone number, got: \(out)")
    }

    // MARK: - Address patterns

    func testStrictRedactsLabelIntroducedAddress() {
        let out = PromptPrivacyRedactor.redactQuestion(
            "I live at 1100 Music Square East, Nashville TN — knee is sore",
            privacyMode: .strict
        )
        XCTAssertFalse(out.contains("Music Square"))
        XCTAssertTrue(out.contains("I live at [REDACTED]"),
                      "Expected 'I live at ' preserved with value redacted, got: \(out)")
        // The injury context after the address should survive.
        XCTAssertTrue(out.contains("knee is sore"))
    }

    // MARK: - Name patterns

    func testStrictRedactsLabelIntroducedName() {
        let out = PromptPrivacyRedactor.redactQuestion(
            "my name is Jared Mabry, should I deload?",
            privacyMode: .strict
        )
        XCTAssertFalse(out.contains("Jared Mabry"))
        XCTAssertTrue(out.contains("my name is [REDACTED]"))
        XCTAssertTrue(out.contains("should I deload?"))
    }

    // MARK: - Injury / medical preservation (deliberate non-redaction)

    func testStrictPreservesInjuryContext() {
        // The point of the coach prompt is to give programming advice
        // around injury context. Stripping it would defeat the
        // feature. The privacy page explicitly discloses that injury
        // text travels (because it has to for the coach to be useful).
        let inputs = [
            "my left shoulder hurts on overhead press",
            "tweaked my lower back, can I still squat?",
            "knee pain on the descent of every rep",
        ]
        for input in inputs {
            let out = PromptPrivacyRedactor.redactQuestion(input, privacyMode: .strict)
            XCTAssertEqual(out, input, "Injury context must survive strict redaction (disclosed in privacy policy): \(input)")
        }
    }

    // MARK: - Multi-pattern composition

    func testStrictRedactsCompoundQuestion() {
        // A pathological input mixing every category. The redactor
        // walks patterns in order; later patterns operate on the
        // already-redacted intermediate string but the marker is
        // benign in every pattern's input.
        let input = """
        my name is Jared Mabry, my email is jared@mabryventures.com, \
        I live at 1100 Music Square East, you can call me at +1 (615) 555-0123 \
        — my left shoulder hurts on overhead press, should I deload?
        """
        let out = PromptPrivacyRedactor.redactQuestion(input, privacyMode: .strict)
        XCTAssertFalse(out.contains("Jared Mabry"))
        XCTAssertFalse(out.contains("jared@mabryventures.com"))
        XCTAssertFalse(out.contains("Music Square"))
        XCTAssertFalse(out.contains("555-0123"))
        XCTAssertTrue(out.contains("shoulder hurts on overhead press"),
                      "Injury context must survive in a compound input, got: \(out)")
        XCTAssertTrue(out.contains("should I deload?"))
    }
}
