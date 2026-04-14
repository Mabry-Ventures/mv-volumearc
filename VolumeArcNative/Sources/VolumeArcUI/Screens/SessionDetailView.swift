#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// Detail view for a historical session row. Pushed from Today's
/// recent sessions list with a `.navigationTransition(.zoom(...))` so
/// the card hero-animates into the detail.
public struct SessionDetailView: View {
    let session: RecentSession

    public init(session: RecentSession) {
        self.session = session
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VA.Space.lg) {
                header
                metricGrid
                exerciseList
                Spacer(minLength: VA.Space.xxl)
            }
            .padding(VA.Space.lg)
        }
        .background(VA.Colors.surfaceSecondary)
        .navigationTitle(
            session.date.formatted(.dateTime.weekday(.wide).month().day())
        )
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: VA.Space.xs) {
            Text(String(localized: "SESSION", comment: "Session detail header label"))
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textSecondary)
                .tracking(0.5)
            Text(session.date.formatted(.dateTime.hour().minute()))
                .font(VA.Typography.title)
                .foregroundStyle(VA.Colors.textPrimary)
        }
    }

    private var metricGrid: some View {
        HStack(spacing: VA.Space.md) {
            VACard(style: .glass) {
                VStack(alignment: .leading, spacing: VA.Space.xs) {
                    Text(String(localized: "SETS", comment: "Session detail set count label"))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .tracking(0.5)
                    Text("\(session.completedSetCount)")
                        .font(VA.Typography.display)
                        .foregroundStyle(VA.Colors.textPrimary)
                }
            }
            VACard(style: .glass) {
                VStack(alignment: .leading, spacing: VA.Space.xs) {
                    Text(String(localized: "VOLUME", comment: "Session detail volume label"))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .tracking(0.5)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(Int(session.totalVolumeLoad))")
                            .font(VA.Typography.display)
                            .foregroundStyle(VA.Colors.textPrimary)
                        Text("lb")
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.textSecondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var exerciseList: some View {
        if !session.exerciseIDs.isEmpty {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                VASectionHeader(String(localized: "Exercises", comment: "Session detail exercises section header"))
                ForEach(session.exerciseIDs, id: \.self) { exerciseID in
                    VACard(style: .flat) {
                        HStack {
                            Text(exerciseDisplayName(exerciseID))
                                .font(VA.Typography.headline)
                                .foregroundStyle(VA.Colors.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(VA.Colors.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private func exerciseDisplayName(_ id: String) -> String {
        VolumeArcExerciseCatalog.exercise(withID: id)?.name ?? id.replacingOccurrences(of: "-", with: " ").capitalized
    }
}
#endif
