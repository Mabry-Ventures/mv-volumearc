import Foundation

public enum WatchFacePreset: String, CaseIterable, Identifiable, Sendable {
    case modular
    case infograph
    case photo

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .modular: return "VolumeArc Modular"
        case .infograph: return "VolumeArc Infograph"
        case .photo: return "VolumeArc Photo"
        }
    }

    public var subtitle: String {
        switch self {
        case .modular:
            return "Daily training decisions at a glance"
        case .infograph:
            return "Dense readiness, workout, and streak context"
        case .photo:
            return "Personal photo face with VolumeArc anchors"
        }
    }

    public var family: String {
        switch self {
        case .modular: return "Modular Duo"
        case .infograph: return "Infograph"
        case .photo: return "Photos"
        }
    }

    public var resourceName: String {
        switch self {
        case .modular: return "VolumeArc-Modular"
        case .infograph: return "VolumeArc-Infograph"
        case .photo: return "VolumeArc-Photo"
        }
    }

    public var telemetryName: String {
        switch self {
        case .modular: return "modular"
        case .infograph: return "infograph"
        case .photo: return "photo"
        }
    }

    public var accentHex: String {
        switch self {
        case .modular: return "#FFB37A"
        case .infograph: return "#F26A33"
        case .photo: return "#5C99E6"
        }
    }

    public var complicationSlots: [WatchFaceComplicationSlot] {
        switch self {
        case .modular:
            return [
                WatchFaceComplicationSlot(slot: "Top", label: "Readiness", value: "82", detail: "Graphic rectangular"),
                WatchFaceComplicationSlot(slot: "Middle", label: "Next Workout", value: "Push A", detail: "Bench 190 x 5"),
                WatchFaceComplicationSlot(slot: "Bottom left", label: "Last Session", value: "12.4k", detail: "lb volume"),
                WatchFaceComplicationSlot(slot: "Bottom right", label: "Streak", value: "16 wk", detail: "Open gauge"),
            ]
        case .infograph:
            return [
                WatchFaceComplicationSlot(slot: "Bezel", label: "Readiness", value: "82", detail: "0-100 arc"),
                WatchFaceComplicationSlot(slot: "Top right", label: "Next", value: "Push A", detail: "Bench 190 x 5"),
                WatchFaceComplicationSlot(slot: "Bottom left", label: "Last", value: "12.4k", detail: "lb volume"),
                WatchFaceComplicationSlot(slot: "Bottom right", label: "Streak", value: "16 wk", detail: "Weekly streak"),
            ]
        case .photo:
            return [
                WatchFaceComplicationSlot(slot: "Top left", label: "Readiness", value: "82", detail: "Single value"),
                WatchFaceComplicationSlot(slot: "Top right", label: "Streak", value: "16 wk", detail: "Single value"),
            ]
        }
    }
}

public struct WatchFaceComplicationSlot: Identifiable, Equatable, Sendable {
    public var id: String { slot }
    public let slot: String
    public let label: String
    public let value: String
    public let detail: String

    public init(slot: String, label: String, value: String, detail: String) {
        self.slot = slot
        self.label = label
        self.value = value
        self.detail = detail
    }
}

public enum WatchFacePack {
    public static let bundleSubdirectory = "WatchFaces"

    public static func bundledPresets(in bundle: Bundle = .main) -> [WatchFacePreset] {
        WatchFacePreset.allCases.filter { bundledFileURL(for: $0, in: bundle) != nil }
    }

    public static func bundledFileURL(
        for preset: WatchFacePreset,
        in bundle: Bundle = .main
    ) -> URL? {
        bundle.url(
            forResource: preset.resourceName,
            withExtension: "watchface",
            subdirectory: bundleSubdirectory
        ) ?? bundle.url(forResource: preset.resourceName, withExtension: "watchface")
    }
}

public extension WorkoutDashboardModel {
    func recordWatchFacePackInstalled(_ preset: WatchFacePreset) {
        telemetrySink.record(TelemetryEvent(
            category: "watch.face_pack",
            name: "installed",
            severity: .info,
            message: "Watch face preset installed",
            metadata: [
                "preset": preset.telemetryName,
                "family": preset.family,
            ]
        ))
    }

    func recordWatchFacePackInstallFailed(_ preset: WatchFacePreset, reason: String) {
        telemetrySink.record(TelemetryEvent(
            category: "watch.face_pack",
            name: "install_failed",
            severity: .warning,
            message: "Watch face preset install failed",
            metadata: [
                "preset": preset.telemetryName,
                "reason": reason,
            ]
        ))
    }
}
