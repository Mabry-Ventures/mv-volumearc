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

extension Notification.Name {
    /// VOL-149: posted after `InMemoryTelemetrySink` records an event
    /// when the sink was constructed with `postsNotificationOnRecord:
    /// true`. The deterministic-mode app shell observes this to refresh
    /// the test-only `debug.telemetry.events` accessibility overlay so
    /// XCUITests can poll the accessibility tree and assert that a
    /// specific (category, name) event fired during a journey.
    ///
    /// `userInfo` carries the `TelemetryEvent` under the key
    /// `TelemetryNotificationKey.event` so observers don't need a
    /// sink reference to inspect what just happened.
    ///
    /// Production-mode sinks never post this — the notification only
    /// fires when the test harness explicitly opts in via the factory.
    public static let volumeArcTelemetryDidRecord = Notification.Name(
        "VolumeArc.TelemetryDidRecord"
    )
}

public enum TelemetryNotificationKey {
    public static let event = "event"
}

/// In-memory telemetry sink that keeps the last N events in a bounded buffer.
/// Thread-safe via an internal lock.
public final class InMemoryTelemetrySink: TelemetrySink, @unchecked Sendable {
    private let lock = NSLock()
    private let maxEvents: Int
    private var events: [TelemetryEvent]
    private let postsNotificationOnRecord: Bool

    public init(
        events: [TelemetryEvent] = [],
        maxEvents: Int = 200,
        postsNotificationOnRecord: Bool = false
    ) {
        self.events = events
        self.maxEvents = maxEvents
        self.postsNotificationOnRecord = postsNotificationOnRecord
    }

    public func record(_ event: TelemetryEvent) {
        lock.lock()
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        lock.unlock()

        // VOL-149: notify after releasing the lock so observers can
        // safely call back into the sink without deadlocking. Only
        // fires when the factory opted in (deterministic / UITest mode).
        // userInfo carries the event so observers don't need a sink
        // reference to inspect what just happened.
        if postsNotificationOnRecord {
            NotificationCenter.default.post(
                name: .volumeArcTelemetryDidRecord,
                object: nil,
                userInfo: [TelemetryNotificationKey.event: event]
            )
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
        defaults.synchronize()
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
