#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// Detail view for a historical session row. Pushed from Today's
/// recent sessions list with a `.navigationTransition(.zoom(...))` so
/// the card hero-animates into the detail.
public struct SessionDetailView: View {
    let session: RecentSession
    let onOpen: () -> Void

    public init(session: RecentSession, onOpen: @escaping () -> Void = {}) {
        self.session = session
        self.onOpen = onOpen
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
        .background(VA.Colors.surfaceGrouped)
        // VOL-200 P3: stable identifier so the `today.recent-session-tap`
        // journey test can assert this view appeared after tapping a
        // row.
        .accessibilityIdentifier("session.detail.root")
        .navigationTitle(
            navigationTitle
        )
        .navigationBarTitleDisplayMode(.large)
        .task {
            onOpen()
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: VA.Space.xs) {
            Text(headerLabel)
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textSecondary)
                .tracking(0.5)
            Text(headerTitle)
                .font(VA.Typography.title)
                .foregroundStyle(VA.Colors.textPrimary)
        }
    }

    private var metricGrid: some View {
        // Two adjacent glass-backed metric cards. Wrap in `GlassEffectContainer`
        // on iOS 26 so the system's coordinated glass renderer composes the
        // two surfaces as a single material treatment instead of two separate
        // glass passes that would visibly seam at the spacing gap.
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: VA.Space.md) {
                    metricGridContent
                }
            } else {
                metricGridContent
            }
        }
    }

    private var metricGridContent: some View {
        HStack(spacing: VA.Space.md) {
            VACard(style: .glass) {
                VStack(alignment: .leading, spacing: VA.Space.xs) {
                    Text(primaryMetricLabel)
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .tracking(0.5)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(primaryMetricValue)
                            .font(VA.Typography.display)
                            .foregroundStyle(VA.Colors.textPrimary)
                        if let unit = primaryMetricUnit {
                            Text(unit)
                                .font(VA.Typography.footnote)
                                .foregroundStyle(VA.Colors.textSecondary)
                        }
                    }
                }
            }
            VACard(style: .glass) {
                VStack(alignment: .leading, spacing: VA.Space.xs) {
                    Text(secondaryMetricLabel)
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .tracking(0.5)
                    if session.isExternalHealthSession {
                        Text(session.sourceName ?? String(localized: "Health", comment: "Short HealthKit source fallback"))
                            .font(VA.Typography.display)
                            .foregroundStyle(VA.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(Int(session.totalVolumeLoad))")
                                .font(VA.Typography.display)
                                .foregroundStyle(VA.Colors.textPrimary)
                            Text(String(localized: "lb", comment: "Weight unit abbreviation — pounds"))
                                .font(VA.Typography.footnote)
                                .foregroundStyle(VA.Colors.textSecondary)
                        }
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
        if id.hasPrefix("healthkit-") {
            return session.title ?? String(localized: "Apple Health workout", comment: "Fallback HealthKit workout title")
        }
        return VolumeArcExerciseCatalog.exercise(withID: id)?.name
            ?? id.replacingOccurrences(of: "-", with: " ").capitalized
    }

    private var navigationTitle: String {
        if session.isExternalHealthSession, let title = session.title, !title.isEmpty {
            return title
        }
        return session.date.formatted(.dateTime.weekday(.wide).month().day())
    }

    private var headerLabel: String {
        session.isExternalHealthSession
            ? String(localized: "APPLE HEALTH", comment: "Session detail header label for HealthKit imports")
            : String(localized: "SESSION", comment: "Session detail header label")
    }

    private var headerTitle: String {
        session.isExternalHealthSession
            ? session.date.formatted(.dateTime.weekday(.wide).month().day().hour().minute())
            : session.date.formatted(.dateTime.hour().minute())
    }

    private var primaryMetricLabel: String {
        session.isExternalHealthSession
            ? String(localized: "DURATION", comment: "Session detail duration label")
            : String(localized: "SETS", comment: "Session detail set count label")
    }

    private var primaryMetricValue: String {
        session.isExternalHealthSession ? "\(session.durationMinutes)" : "\(session.completedSetCount)"
    }

    private var primaryMetricUnit: String? {
        session.isExternalHealthSession ? String(localized: "min", comment: "Minute unit abbreviation") : nil
    }

    private var secondaryMetricLabel: String {
        session.isExternalHealthSession
            ? String(localized: "SOURCE", comment: "Session detail source label")
            : String(localized: "VOLUME", comment: "Session detail volume label")
    }
}
#endif
