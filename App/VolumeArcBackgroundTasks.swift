#if canImport(BackgroundTasks) && !os(watchOS)
import BackgroundTasks
import Foundation
import VolumeArcCore

/// Schedules and handles background tasks for VolumeArc:
/// - `app-refresh`: sync data, refresh widget snapshots, update readiness
/// - `app-processing`: heavier work like coach memory consolidation
///
/// Both tasks run opportunistically and are coalesced by the system —
/// requesting them frequently doesn't increase how often they actually run.
enum VolumeArcBackgroundTasks {
    static let appRefreshIdentifier = "com.mabryventures.VolumeArc.appRefresh"
    static let appProcessingIdentifier = "com.mabryventures.VolumeArc.appProcessing"

    /// Late-bound holder for the dashboard model. The SwiftUI App init()
    /// must register BG task handlers before the model is constructed,
    /// so the handlers capture this holder and dereference it at task time.
    @MainActor static var sharedModel: WorkoutDashboardModel?

    /// Register handlers for both task identifiers. Must be called before
    /// `UIApplication` finishes launching (from `VolumeArcApp.init`).
    static func registerHandlers() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: appRefreshIdentifier,
            using: nil
        ) { task in
            // BGTask is not Sendable; run handler synchronously on the system
            // queue and dispatch the actual work to MainActor.
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Self.handleAppRefresh(refreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: appProcessingIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Self.handleAppProcessing(processingTask)
        }
    }

    /// Schedule both tasks to run when the system decides it's appropriate.
    static func scheduleAll() {
        scheduleAppRefresh()
        scheduleAppProcessing()
    }

    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: appRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func scheduleAppProcessing() {
        let request = BGProcessingTaskRequest(identifier: appProcessingIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Handlers

    private static func handleAppRefresh(_ task: BGAppRefreshTask) {
        scheduleAppRefresh()
        let completion = TaskCompletion(task: task)

        task.expirationHandler = {
            completion.complete(success: false)
        }

        Task { @MainActor in
            if let model = sharedModel {
                // VOL-110: route through `performBackgroundRefresh` rather
                // than `refresh` directly so the BGTask handler emits
                // bracketing telemetry events
                // (`background.refresh_started` / `_completed`) that
                // operations can use to observe BGTask wake events. The
                // method is also the test seam for VOL-110's unit test.
                let success = await model.performBackgroundRefresh()
                completion.complete(success: success)
            } else {
                completion.complete(success: false)
            }
        }
    }

    private static func handleAppProcessing(_ task: BGProcessingTask) {
        scheduleAppProcessing()
        let completion = TaskCompletion(task: task)

        task.expirationHandler = {
            completion.complete(success: false)
        }

        Task { @MainActor in
            if let model = sharedModel {
                await model.syncNow()
                completion.complete(success: true)
            } else {
                completion.complete(success: false)
            }
        }
    }
}

/// Sendable wrapper around BGTask so the completion call can cross
/// concurrency boundaries safely. BGTask.setTaskCompleted is thread-safe.
private final class TaskCompletion: @unchecked Sendable {
    private let task: BGTask
    private let lock = NSLock()
    private var completed = false

    init(task: BGTask) {
        self.task = task
    }

    func complete(success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return }
        completed = true
        task.setTaskCompleted(success: success)
    }
}
#endif
