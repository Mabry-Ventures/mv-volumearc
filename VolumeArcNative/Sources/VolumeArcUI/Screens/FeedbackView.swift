#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// VOL-146 Phase 1B (VOL-176): in-app feedback sheet reachable from
/// `Profile → Send feedback`. Pairs with the model layer that landed in
/// Phase 1A (`FeedbackBundle`, `FeedbackBundleAssembler`,
/// `FeedbackTextScrubber` in `VolumeArcCore/Diagnostics/`).
///
/// Architectural shape: the view is pure SwiftUI with no Sentry import.
/// The App layer wires the submit closure to assemble the bundle (using
/// runtime `Bundle.main` / `ProcessInfo` / `UIDevice` values plus recent
/// telemetry from the live sink), encode JSON via
/// `FeedbackBundleAssembler.encodeJSON(_:)`, and forward to
/// `SentrySDK.captureUserFeedback(_:)` plus a `feedback.submitted`
/// telemetry event. Tests + non-Sentry builds substitute a closure that
/// records the bundle and asserts on it.
///
/// Surface contract for XCUITest (Phase 1C / VOL-179):
/// - `accessibilityIdentifier("feedback.sheet")` on the form root.
/// - `accessibilityIdentifier("feedback.category.<rawValue>")` on each
///   category chip.
/// - `accessibilityIdentifier("feedback.description")` on the editor.
/// - `accessibilityIdentifier("feedback.submit")` on the submit button.
/// - `accessibilityIdentifier("feedback.cancel")` on the cancel button.
public struct FeedbackView: View {
    @Binding var isPresented: Bool

    /// Receives the user-typed `(category, description)` pair. The App
    /// layer turns this into a `FeedbackBundle` and forwards to Sentry
    /// + telemetry. Sheet dismisses after the closure returns.
    public let onSubmit: (FeedbackBundle.Category, String) -> Void

    @State private var category: FeedbackBundle.Category = .bug
    @State private var userDescription: String = ""
    @FocusState private var isDescriptionFocused: Bool

    public init(
        isPresented: Binding<Bool>,
        onSubmit: @escaping (FeedbackBundle.Category, String) -> Void
    ) {
        self._isPresented = isPresented
        self.onSubmit = onSubmit
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VA.Space.xl) {
                    intro
                    categoryPicker
                    descriptionField
                    submitButton
                    disclaimer
                }
                .padding(VA.Space.lg)
                .padding(.bottom, VA.Space.xxl)
            }
            .background(VA.Colors.surfaceGrouped)
            .accessibilityIdentifier("feedback.sheet")
            .navigationTitle(Text(String(
                localized: "Send feedback",
                comment: "Feedback sheet navigation title"
            )))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        VAHaptics.tap()
                        isPresented = false
                    } label: {
                        Text(String(localized: "Cancel", comment: "Feedback sheet cancel"))
                    }
                    .accessibilityIdentifier("feedback.cancel")
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: VA.Space.xs) {
            Text(String(
                localized: "We read every note.",
                comment: "Feedback sheet headline"
            ))
                .font(VA.Typography.title2)
                .foregroundStyle(VA.Colors.textPrimary)
            Text(String(
                localized: "Your message helps us prioritize the next release. "
                    + "We attach recent app activity to make bugs easier to "
                    + "reproduce — emails and phone numbers are scrubbed before "
                    + "the report leaves your device.",
                comment: "Feedback sheet sub-headline explaining what's attached"
            ))
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: VA.Space.sm) {
            Text(String(localized: "What's this about?", comment: "Feedback category prompt"))
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)

            // Wrap chip-style buttons so on narrow widths the categories
            // wrap instead of compressing the label text.
            FeedbackCategoryRow(selection: $category)
        }
        .accessibilityElement(children: .contain)
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: VA.Space.sm) {
            Text(String(localized: "Description", comment: "Feedback description field label"))
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
            TextEditor(text: $userDescription)
                .font(VA.Typography.body)
                .foregroundStyle(VA.Colors.textPrimary)
                .frame(minHeight: 140)
                .padding(VA.Space.sm)
                .background(VA.Colors.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous)
                        .stroke(VA.Colors.textTertiary.opacity(0.18), lineWidth: 0.5)
                }
                .accessibilityIdentifier("feedback.description")
                .accessibilityLabel(String(
                    localized: "Feedback description",
                    comment: "VoiceOver label for the feedback description field"
                ))
                .focused($isDescriptionFocused)
        }
    }

    private var submitButton: some View {
        Button {
            VAHaptics.success()
            let trimmed = userDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            onSubmit(category, trimmed)
            isPresented = false
        } label: {
            Text(String(localized: "Submit feedback", comment: "Feedback sheet submit"))
                .font(VA.Typography.button)
                .foregroundStyle(VA.Colors.textOnPrimary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(submitButtonBackground, in: RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSubmitDisabled)
        .accessibilityIdentifier("feedback.submit")
        .accessibilityHint(String(
            localized: "Sends your feedback and recent app activity to the VolumeArc team",
            comment: "VoiceOver hint for the feedback submit button"
        ))
    }

    private var disclaimer: some View {
        Text(String(
            localized: "Submitting attaches your recent app events, build version, "
                + "and device model. Nothing else leaves your device.",
            comment: "Feedback sheet privacy disclaimer"
        ))
            .font(VA.Typography.caption)
            .foregroundStyle(VA.Colors.textTertiary)
    }

    private var isSubmitDisabled: Bool {
        userDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var submitButtonBackground: Color {
        isSubmitDisabled ? VA.Colors.primary.opacity(0.45) : VA.Colors.primary
    }
}

private struct FeedbackCategoryRow: View {
    @Binding var selection: FeedbackBundle.Category

    var body: some View {
        // A wrapping HStack — under Dynamic Type, chips may need to flow
        // to multiple lines. SwiftUI's `Layout` would be cleaner but
        // adds compile cost; a `LazyVGrid` with `adaptive` columns is
        // good-enough.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 130), spacing: VA.Space.xs)],
            alignment: .leading,
            spacing: VA.Space.xs
        ) {
            ForEach(FeedbackBundle.Category.allCases, id: \.self) { category in
                Button {
                    VAHaptics.tap()
                    selection = category
                } label: {
                    Text(LocalizedLabels.feedbackCategoryDisplayName(category))
                        .font(VA.Typography.button)
                        .foregroundStyle(selection == category ? VA.Colors.textOnPrimary : VA.Colors.textPrimary)
                        .padding(.horizontal, VA.Space.md)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(
                            selection == category ? VA.Colors.primary : VA.Colors.surfacePrimary,
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(VA.Colors.textTertiary.opacity(selection == category ? 0 : 0.2), lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("feedback.category.\(category.rawValue)")
                .accessibilityAddTraits(selection == category ? [.isSelected, .isButton] : .isButton)
            }
        }
    }
}
#endif
