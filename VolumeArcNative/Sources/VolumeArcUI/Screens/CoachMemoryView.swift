#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

public struct CoachMemoryView: View {
    @ObservedObject private var model: WorkoutDashboardModel
    @Environment(\.dismiss) private var dismiss
    @State private var draftMemory = ""
    @State private var draftTheme = ""
    @State private var isSaving = false
    @State private var saveFailed = false

    public init(model: WorkoutDashboardModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VA.Space.xl) {
                    explanationSection
                    editorSection
                    if !model.coachMemory.mostRecent.isEmpty {
                        recentSection
                    }
                }
                .padding(VA.Space.lg)
                .padding(.bottom, VA.Space.xxl)
            }
            .background(VA.Colors.surfaceGrouped)
            .navigationTitle(String(localized: "Coach Memory", comment: "Coach memory editor title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done", comment: "Dismiss coach memory sheet")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("coachMemory.root")
    }

    private var explanationSection: some View {
        VACard(style: .accent) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                HStack(alignment: .top, spacing: VA.Space.md) {
                    Image(systemName: "brain.head.profile")
                        .font(VA.Typography.title2)
                        .foregroundStyle(VA.Colors.primary)
                        .frame(width: 38, height: 38)
                        .background(VA.Colors.primary.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: VA.Space.xxs) {
                        Text(String(localized: "What the coach remembers", comment: "Coach memory explanation title"))
                            .font(VA.Typography.headline)
                            .foregroundStyle(VA.Colors.textPrimary)
                        Text(String(
                            localized: """
                            Save durable coaching context the app should remember \
                            across sessions: equipment limits, lift cues, training \
                            preferences, or constraints you do not want to repeat.
                            """,
                            comment: "Coach memory explanation body"
                        ))
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: VA.Space.sm) {
                    CoachMemoryFactRow(
                        icon: "target",
                        title: String(localized: "Shapes future calls", comment: "Coach memory fact title"),
                        detail: String(
                            localized: "Used when the coach picks substitutions, load guidance, and session planning context.",
                            comment: "Coach memory fact detail"
                        )
                    )
                    CoachMemoryFactRow(
                        icon: "pencil.and.list.clipboard",
                        title: String(localized: "You control it", comment: "Coach memory fact title"),
                        detail: String(
                            localized: "Add concise notes here and review recent saved memory before relying on it.",
                            comment: "Coach memory fact detail"
                        )
                    )
                    CoachMemoryFactRow(
                        icon: "lock.shield.fill",
                        title: String(localized: "Keep it training-specific", comment: "Coach memory fact title"),
                        detail: String(
                            localized: "Do not store medical records, secrets, or anything you would not want in training context.",
                            comment: "Coach memory fact detail"
                        )
                    )
                }
            }
        }
    }

    private var editorSection: some View {
        VStack(alignment: .leading, spacing: VA.Space.sm) {
            Text(String(localized: "ADD MEMORY", comment: "Coach memory editor section label"))
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
                .padding(.horizontal, VA.Space.xs)

            VACard(style: .elevated) {
                VStack(alignment: .leading, spacing: VA.Space.md) {
                    TextField(
                        String(localized: "Theme", comment: "Coach memory theme field placeholder"),
                        text: $draftTheme
                    )
                    .textFieldStyle(.plain)
                    .font(VA.Typography.body)
                    .padding(.horizontal, VA.Space.md)
                    .frame(height: 44)
                    .background(VA.Colors.surfaceSecondary, in: RoundedRectangle(cornerRadius: VA.Radius.md))
                    .accessibilityIdentifier("coachMemory.theme")

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $draftMemory)
                            .font(VA.Typography.body)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 148)
                            .padding(.horizontal, VA.Space.sm)
                            .padding(.vertical, VA.Space.xs)
                            .coachMemoryWritingTools()
                            .accessibilityIdentifier("coachMemory.editor")

                        if draftMemory.isEmpty {
                            Text(String(
                                localized: "What should the coach remember?",
                                comment: "Coach memory text editor placeholder"
                            ))
                            .font(VA.Typography.body)
                            .foregroundStyle(VA.Colors.textTertiary)
                            .padding(.horizontal, VA.Space.md)
                            .padding(.vertical, VA.Space.md)
                            .allowsHitTesting(false)
                        }
                    }
                    .background(VA.Colors.surfaceSecondary, in: RoundedRectangle(cornerRadius: VA.Radius.md))

                    if saveFailed {
                        Text(String(localized: "Memory was not saved.", comment: "Coach memory save failure"))
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.error)
                    }

                    VAButton(
                        isSaving
                            ? String(localized: "Saving", comment: "Coach memory saving button label")
                            : String(localized: "Save memory", comment: "Coach memory save button label"),
                        icon: "checkmark",
                        style: .primary,
                        accessibilityIdentifier: "coachMemory.save"
                    ) {
                        saveMemory()
                    }
                    .disabled(isSaving || draftMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: VA.Space.sm) {
            Text(String(localized: "RECENT", comment: "Coach memory recent section label"))
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
                .padding(.horizontal, VA.Space.xs)

            VStack(spacing: 0) {
                ForEach(model.coachMemory.mostRecent) { entry in
                    CoachMemoryEntryRow(entry: entry)
                    if entry.id != model.coachMemory.mostRecent.last?.id {
                        Divider().padding(.leading, VA.Space.lg)
                    }
                }
            }
            .background(VA.Colors.surfacePrimary, in: RoundedRectangle(cornerRadius: VA.Radius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: VA.Radius.lg)
                    .stroke(VA.Colors.textTertiary.opacity(0.14), lineWidth: 0.5)
            }
        }
    }

    private func saveMemory() {
        Task {
            isSaving = true
            saveFailed = false
            let saved = await model.appendCoachMemory(content: draftMemory, theme: draftTheme)
            isSaving = false
            saveFailed = !saved
            if saved {
                draftMemory = ""
                draftTheme = ""
            }
        }
    }
}

private struct CoachMemoryEntryRow: View {
    let entry: CoachMemory.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: VA.Space.xs) {
            HStack(spacing: VA.Space.xs) {
                if let theme = entry.theme, !theme.isEmpty {
                    Text(theme.uppercased())
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.primary)
                }
                Text(entry.createdAt, style: .date)
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textTertiary)
            }
            Text(entry.summary)
                .font(VA.Typography.body)
                .foregroundStyle(VA.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VA.Space.lg)
    }
}

private struct CoachMemoryFactRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: VA.Space.sm) {
            Image(systemName: icon)
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.primary)
                .frame(width: 24, height: 24)
                .background(VA.Colors.primary.opacity(VA.Opacity.iconPanelAccent), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textPrimary)
                Text(detail)
                    .font(VA.Typography.captionLarge)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func coachMemoryWritingTools() -> some View {
        #if os(iOS)
        if #available(iOS 18.1, *) {
            self
                .writingToolsBehavior(.complete)
                .writingToolsAffordanceVisibility(.automatic)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
#endif
