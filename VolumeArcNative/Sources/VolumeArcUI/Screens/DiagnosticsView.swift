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
            Spacer()
            Text(String(
                localized: "\(filteredEvents.count) of \(events.count)",
                comment: "Diagnostics counter — filtered events out of total"
            ))
            .font(VA.Typography.caption)
            .foregroundStyle(VA.Colors.textSecondary)
        }
        .padding(VA.Space.md)
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
