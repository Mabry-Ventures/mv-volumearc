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
    static func registerHandlers(model: @escaping @MainActor () -> WorkoutDashboardModel?) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: appRefreshIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleAppRefresh(refreshTask, model: model)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: appProcessingIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handleAppProcessing(processingTask, model: model)
        }
    }

    /// Schedule both tasks to run when the system decides it's appropriate.
    static func scheduleAll() {
        scheduleAppRefresh()
        scheduleAppProcessing()
    }

    static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: appRefreshIdentifier)
        // Earliest begin: 30 minutes from now.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func scheduleAppProcessing() {
        let request = BGProcessingTaskRequest(identifier: appProcessingIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        // Earliest begin: 2 hours from now.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Handlers

    private static func handleAppRefresh(
        _ task: BGAppRefreshTask,
        model: @escaping @MainActor () -> WorkoutDashboardModel?
    ) {
        // Reschedule the next refresh immediately so the chain continues.
        scheduleAppRefresh()

        let work = Task {
            await MainActor.run {
                if let model = model() {
                    Task {
                        await model.refresh()
                        task.setTaskCompleted(success: true)
                    }
                } else {
                    task.setTaskCompleted(success: false)
                }
            }
        }

        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    private static func handleAppProcessing(
        _ task: BGProcessingTask,
        model: @escaping @MainActor () -> WorkoutDashboardModel?
    ) {
        // Reschedule the next processing task.
        scheduleAppProcessing()

        let work = Task {
            await MainActor.run {
                if let model = model() {
                    Task {
                        await model.syncNow()
                        task.setTaskCompleted(success: true)
                    }
                } else {
                    task.setTaskCompleted(success: false)
                }
            }
        }

        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
#endif
