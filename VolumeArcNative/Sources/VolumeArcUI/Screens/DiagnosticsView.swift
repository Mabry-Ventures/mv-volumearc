#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// Diagnostics screen — surfaces the persistent telemetry buffer so users
/// and support can see what the app has been doing without a network call.
/// Useful for debugging degraded states and producing support requests.
public struct DiagnosticsView: View {
    @State private var events: [TelemetryEvent] = []
    @State private var filter: Filter = .all

    private let sink = UserDefaultsTelemetrySink()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            filterBar
            if !events.isEmpty {
                summaryCard
                    .padding(.horizontal, VA.Space.md)
                    .padding(.bottom, VA.Space.sm)
            }
            if filteredEvents.isEmpty {
                VAEmptyState(
                    icon: "doc.text.magnifyingglass",
                    title: String(localized: "No events yet", comment: "Diagnostics empty-state title"),
                    message: String(
                        localized: "Diagnostics events will appear here as you use the app.",
                        comment: "Diagnostics empty-state message"
                    )
                )
            } else {
                List {
                    ForEach(Array(filteredEvents.enumerated()), id: \.offset) { _, event in
                        eventRow(event)
                    }
                }
                .listStyle(.plain)
            }
        }
        // VOL-200 P4: stable identifier so `profile.diagnostics`
        // journey test can confirm the view appeared after tapping
        // the Profile row.
        .accessibilityIdentifier("diagnostics.root")
        .navigationTitle(String(localized: "Diagnostics", comment: "Diagnostics screen navigation title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(
                        String(localized: "Refresh", comment: "Diagnostics menu — refresh events"),
                        systemImage: "arrow.clockwise"
                    ) {
                        reload()
                    }
                    Button(
                        String(localized: "Clear", comment: "Diagnostics menu — clear stored events"),
                        systemImage: "trash",
                        role: .destructive
                    ) {
                        sink.clear()
                        reload()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { reload() }
    }

    // MARK: - Filter

    private enum Filter: String, CaseIterable {
        case all
        case warning
        case error

        var title: String {
            switch self {
            case .all:
                return String(localized: "All", comment: "Diagnostics filter — show all events")
            case .warning:
                return String(localized: "Warnings", comment: "Diagnostics filter — show only warnings")
            case .error:
                return String(localized: "Errors", comment: "Diagnostics filter — show only errors")
            }
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: VA.Space.sm) {
            HStack(spacing: VA.Space.sm) {
                ForEach(Filter.allCases, id: \.self) { filterCase in
                    Button {
                        filter = filterCase
                        VAHaptics.selection()
                    } label: {
                        Text(filterCase.title)
                            .font(VA.Typography.footnote)
                            .foregroundStyle(filter == filterCase ? VA.Colors.textOnPrimary : VA.Colors.textPrimary)
                            .padding(.horizontal, VA.Space.md)
                            .padding(.vertical, VA.Space.sm)
                            .background(filter == filterCase ? VA.Colors.primary : Color.clear)
                            .clipShape(Capsule())
                            .overlay {
                                Capsule().stroke(VA.Colors.primary.opacity(0.4), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: VA.Space.sm) {
                Text(String(
                    localized: "^[\(filteredEvents.count) event](inflect: true) of ^[\(events.count) event](inflect: true)",
                    comment: "Diagnostics counter — filtered events out of total"
                ))
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textSecondary)
                Spacer(minLength: VA.Space.sm)
                ShareLink(
                    item: diagnosticsExportText,
                    subject: Text(String(localized: "VolumeArc diagnostics", comment: "Diagnostics export share subject")),
                    message: Text(String(
                        localized: "Diagnostics export from VolumeArc.",
                        comment: "Diagnostics export share message"
                    ))
                ) {
                    Label(
                        String(localized: "Export", comment: "Diagnostics export button"),
                        systemImage: "square.and.arrow.up"
                    )
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.primary)
                    .accessibilityIdentifier("diagnostics.export")
                }
                .accessibilityIdentifier("diagnostics.export")
            }
        }
        .padding(VA.Space.md)
    }

    private var summaryCard: some View {
        VACard(style: .flat) {
            VStack(alignment: .leading, spacing: VA.Space.sm) {
                HStack(alignment: .center, spacing: VA.Space.sm) {
                    Image(systemName: summaryIcon)
                        .font(VA.Typography.headline)
                        .foregroundStyle(summaryColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summaryTitle)
                            .font(VA.Typography.headline)
                            .foregroundStyle(VA.Colors.textPrimary)
                        Text(summaryDetail)
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.textSecondary)
                    }
                }
                Text(String(
                    localized: """
                    Warnings are support signals, not always launch blockers. Export diagnostics \
                    when reporting an issue so the team can see the exact event history.
                    """,
                    comment: "Diagnostics warning explanation"
                ))
                .font(VA.Typography.captionLarge)
                .foregroundStyle(VA.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diagnostics.summary")
    }

    // MARK: - Rows

    private func eventRow(_ event: TelemetryEvent) -> some View {
        HStack(alignment: .top, spacing: VA.Space.sm) {
            Image(systemName: iconForSeverity(event.severity))
                .font(VA.Typography.caption)
                .foregroundStyle(colorForSeverity(event.severity))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(event.name)
                        .font(VA.Typography.headline)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Spacer()
                    Text(event.timestamp.formatted(.dateTime.hour().minute().second()))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .monospacedDigit()
                }
                Text("[\(event.category)] \(event.message)")
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textSecondary)
                if !event.metadata.isEmpty {
                    Text(event.metadata.map { "\($0.key)=\($0.value)" }.joined(separator: " · "))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textTertiary)
                }
            }
        }
        .padding(.vertical, VA.Space.xs)
    }

    // MARK: - Helpers

    private var filteredEvents: [TelemetryEvent] {
        switch filter {
        case .all: return events.reversed()
        case .warning: return events.filter { $0.severity == .warning }.reversed()
        case .error: return events.filter { $0.severity == .error }.reversed()
        }
    }

    private func reload() {
        events = sink.loadEvents()
    }

    private var warningCount: Int {
        events.filter { $0.severity == .warning }.count
    }

    private var errorCount: Int {
        events.filter { $0.severity == .error }.count
    }

    private var summaryTitle: String {
        if errorCount > 0 {
            return String(
                localized: "^[\(errorCount) error](inflect: true) recorded",
                comment: "Diagnostics summary title for error count"
            )
        }
        if warningCount > 0 {
            return String(
                localized: "^[\(warningCount) warning](inflect: true) recorded",
                comment: "Diagnostics summary title for warning count"
            )
        }
        return String(localized: "No warnings recorded", comment: "Diagnostics summary title healthy state")
    }

    private var summaryDetail: String {
        if errorCount > 0 {
            return String(
                localized: "Use Export before clearing events.",
                comment: "Diagnostics summary detail for error state"
            )
        }
        if warningCount > 0 {
            return String(
                localized: "Review the warning list or include the export in feedback.",
                comment: "Diagnostics summary detail for warning state"
            )
        }
        return String(
            localized: "Recent app events are informational.",
            comment: "Diagnostics summary detail for healthy state"
        )
    }

    private var summaryIcon: String {
        if errorCount > 0 { return "xmark.octagon.fill" }
        if warningCount > 0 { return "exclamationmark.triangle.fill" }
        return "checkmark.seal.fill"
    }

    private var summaryColor: Color {
        if errorCount > 0 { return VA.Colors.error }
        if warningCount > 0 { return VA.Colors.warning }
        return VA.Colors.success
    }

    private var diagnosticsExportText: String {
        let formatter = ISO8601DateFormatter()
        let rows = events.reversed().map { event in
            let metadata = event.metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            return [
                formatter.string(from: event.timestamp),
                event.severity.rawValue.uppercased(),
                "[\(event.category)] \(event.name)",
                event.message,
                metadata.isEmpty ? nil : "metadata: \(metadata)",
            ]
            .compactMap { $0 }
            .joined(separator: " | ")
        }
        let visibleRows = rows.isEmpty
            ? [String(localized: "No diagnostics events recorded.", comment: "Diagnostics empty export row")]
            : rows

        return ([
            String(localized: "VolumeArc diagnostics", comment: "Diagnostics export title"),
            String(localized: "Events: \(events.count)", comment: "Diagnostics export total events row"),
            String(localized: "Warnings: \(warningCount)", comment: "Diagnostics export warnings row"),
            String(localized: "Errors: \(errorCount)", comment: "Diagnostics export errors row"),
            "",
        ] + visibleRows).joined(separator: "\n")
    }

    private func iconForSeverity(_ severity: TelemetrySeverity) -> String {
        switch severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func colorForSeverity(_ severity: TelemetrySeverity) -> Color {
        switch severity {
        case .info: return VA.Colors.info
        case .warning: return VA.Colors.warning
        case .error: return VA.Colors.error
        }
    }
}
#endif
