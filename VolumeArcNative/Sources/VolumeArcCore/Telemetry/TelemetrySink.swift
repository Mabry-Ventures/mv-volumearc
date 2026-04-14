import Foundation

public enum TelemetrySeverity: String, Sendable, Comparable, Codable {
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

public struct TelemetryEvent: Sendable, Codable {
    public let category: String
    public let name: String
    public let severity: TelemetrySeverity
    public let message: String
    public let metadata: [String: String]
    public let timestamp: Date

    public init(
        category: String,
        name: String,
        severity: TelemetrySeverity,
        message: String,
        metadata: [String: String] = [:],
        timestamp: Date = .now
    ) {
        self.category = category
        self.name = name
        self.severity = severity
        self.message = message
        self.metadata = metadata
        self.timestamp = timestamp
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

/// In-memory telemetry sink that keeps the last N events in a bounded buffer.
/// Thread-safe via an internal lock.
public final class InMemoryTelemetrySink: TelemetrySink, @unchecked Sendable {
    private let lock = NSLock()
    private let maxEvents: Int
    private var events: [TelemetryEvent]

    public init(events: [TelemetryEvent] = [], maxEvents: Int = 200) {
        self.events = events
        self.maxEvents = maxEvents
    }

    public func record(_ event: TelemetryEvent) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }

    /// Snapshot of currently buffered events.
    public var currentEvents: [TelemetryEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

/// Persistent telemetry sink backed by UserDefaults (rolling buffer of the last N events).
/// Used for diagnostics the user or support can inspect without a network call.
///
/// UserDefaults itself is thread-safe but not declared `Sendable`, so we wrap it
/// in an `@unchecked Sendable` struct with internal locking.
public struct UserDefaultsTelemetrySink: TelemetrySink, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let maxEvents: Int
    private let lock = NSLock()

    public init(
        defaults: UserDefaults = .standard,
        key: String = "com.mabryventures.VolumeArc.telemetry.events",
        maxEvents: Int = 100
    ) {
        self.defaults = defaults
        self.key = key
        self.maxEvents = maxEvents
    }

    public func record(_ event: TelemetryEvent) {
        lock.lock()
        defer { lock.unlock() }
        var events = unsafeLoadEvents()
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        if let data = try? JSONEncoder().encode(events) {
            defaults.set(data, forKey: key)
        }
    }

    private func unsafeLoadEvents() -> [TelemetryEvent] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([TelemetryEvent].self, from: data)
        else {
            return []
        }
        return decoded
    }

    /// Load all persisted events.
    public func loadEvents() -> [TelemetryEvent] {
        lock.lock()
        defer { lock.unlock() }
        return unsafeLoadEvents()
    }

    /// Clear all persisted events.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: key)
    }
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
