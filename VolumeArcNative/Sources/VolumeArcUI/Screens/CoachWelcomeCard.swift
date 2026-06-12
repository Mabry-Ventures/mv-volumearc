#if canImport(SwiftUI)
import SwiftUI

/// Static welcome copy for the Coach tab's empty state. Extracted from
/// `CoachView` purely for file-length budget — content unchanged.
struct CoachWelcomeCard: View {
    var body: some View {
        VACard(style: .elevated) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                HStack(alignment: .top, spacing: VA.Space.md) {
                    Image(systemName: "waveform.and.mic")
                        .font(VA.Typography.title2)
                        .foregroundStyle(VA.Colors.primary)
                        .frame(width: 44, height: 44)
                        .background(VA.Colors.primary.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: VA.Space.xs) {
                        Text(String(localized: "Your Coach", comment: "Coach welcome card title"))
                            .font(VA.Typography.title2)
                            .foregroundStyle(VA.Colors.textPrimary)
                        Text(String(
                            localized: """
                                Ask anything about your training — load selection, form cues, \
                                recovery, or tomorrow's plan. I’ll ground the answer in your \
                                recent sessions and readiness.
                                """,
                            comment: "Coach welcome card description"
                        ))
                        .font(VA.Typography.body)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
#endif
