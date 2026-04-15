#if canImport(Network)
import Foundation
import Network

public final class NetworkReachabilityMonitor: Sendable {
    private let monitor: NWPathMonitor
    private let queue: DispatchQueue

    public init(queue: DispatchQueue = DispatchQueue(label: "com.mabryventures.VolumeArc.reachability")) {
        self.monitor = NWPathMonitor()
        self.queue = queue
    }

    /// Current reachability status (snapshot — does not start monitoring).
    public var isReachable: Bool {
        monitor.currentPath.status == .satisfied
    }

    /// Whether the current path uses a cellular interface.
    public var isCellular: Bool {
        monitor.currentPath.usesInterfaceType(.cellular)
    }

    /// Whether the current path is constrained (e.g., Low Data Mode).
    public var isConstrained: Bool {
        monitor.currentPath.isConstrained
    }

    /// Start monitoring and call the handler on every path change.
    public func start(onChange: @escaping @Sendable (NWPath) -> Void) {
        monitor.pathUpdateHandler = onChange
        monitor.start(queue: queue)
    }

    /// Stop monitoring.
    public func stop() {
        monitor.cancel()
    }
}
#endif
