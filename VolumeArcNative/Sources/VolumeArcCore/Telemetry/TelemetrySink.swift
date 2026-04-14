import Foundation

public enum TelemetrySeverity: String, Sendable, Comparable {
    case info
    case warning
    case error

    public static func < (lhs: TelemetrySeverity, rhs: TelemetrySeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .info: return 0
        case .warning: return 1
        case .error: return 2
        }
    }
}

public struct TelemetryEvent: Sendable {
    public let category: String
    public let name: String
    public let severity: TelemetrySeverity
    public let message: String
    public let metadata: [String: String]

    public init(category: String, name: String, severity: TelemetrySeverity, message: String, metadata: [String: String] = [:]) {
        self.category = category
        self.name = name
        self.severity = severity
        self.message = message
        self.metadata = metadata
    }
}

public protocol TelemetrySink: Sendable {
    func record(_ event: TelemetryEvent)
}

public struct FanoutTelemetrySink: TelemetrySink {
    private let sinks: [TelemetrySink]

    public init(sinks: [TelemetrySink]) {
        self.sinks = sinks
    }

    public func record(_ event: TelemetryEvent) {
        for sink in sinks {
            sink.record(event)
        }
    }
}

public struct InMemoryTelemetrySink: TelemetrySink {
    private let events: [TelemetryEvent]

    public init(events: [TelemetryEvent] = []) {
        self.events = events
    }

    public func record(_ event: TelemetryEvent) {}
}

public struct UserDefaultsTelemetrySink: TelemetrySink {
    public init() {}
    public func record(_ event: TelemetryEvent) {}
}

#if canImport(OSLog)
import OSLog

public struct OSLogTelemetrySink: TelemetrySink {
    private let logger = Logger(subsystem: "com.mabryventures.VolumeArc", category: "telemetry")

    public init() {}

    public func record(_ event: TelemetryEvent) {
        switch event.severity {
        case .info:
            logger.info("[\(event.category)] \(event.name): \(event.message)")
        case .warning:
            logger.warning("[\(event.category)] \(event.name): \(event.message)")
        case .error:
            logger.error("[\(event.category)] \(event.name): \(event.message)")
        }
    }
}
#endif

public struct OperationalSignalSummary: Sendable {
    public let id: String
    public let title: String
    public let message: String
    public let severity: TelemetrySeverity

    public init(id: String, title: String, message: String, severity: TelemetrySeverity) {
        self.id = id
        self.title = title
        self.message = message
        self.severity = severity
    }
}
