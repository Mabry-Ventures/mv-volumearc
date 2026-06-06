#if canImport(BackgroundTasks) && !os(watchOS)
import BackgroundTasks
import Foundation
import os
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

    /// VOL-204: late-bound telemetry sink for `BGTaskScheduler.submit`
    /// failure reporting. `VolumeArcApp.init` sets this alongside
    /// `sharedModel` so the schedule paths can emit typed telemetry
    /// without depending on a fully-constructed dashboard model. Stays
    /// optional because BGTask registration runs before the App body
    /// resolves, and the schedule calls must not crash if the slot is
    /// somehow unset (defensive — every shipping configuration sets it).
    ///
    /// `@MainActor` matches `sharedModel` and satisfies Swift 6 strict-
    /// concurrency. The schedule call sites (`scheduleAll`, the two
    /// schedule funcs, and the shared `submit` seam) are also
    /// `@MainActor` below; `VolumeArcApp.init` and the
    /// `Task { @MainActor in … }` blocks inside the BGTask handlers
    /// already operate on the main actor, so no caller is forced to
    /// hop.
    @MainActor static var telemetrySink: (any TelemetrySink)?

    /// Internal `os.Logger` for BG-task scheduling. Always available
    /// even when `telemetrySink` is nil, so a scheduling failure is
    /// visible in `Console.app` regardless of whether the Sentry /
    /// telemetry sink wiring is healthy.
    private static let logger = Logger(subsystem: "com.mabryventures.VolumeArc", category: "background-tasks")

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
    /// `@MainActor` so the call chain that touches `telemetrySink`
    /// (VOL-204) stays main-actor isolated under Swift 6 strict-
    /// concurrency. Call sites (`VolumeArcApp.onAppear` + the
    /// `Task { @MainActor in … }` inside each BGTask handler) already
    /// run on the main actor; no caller is forced to hop.
    @MainActor
    static func scheduleAll() {
        scheduleAppRefresh()
        scheduleAppProcessing()
    }

    // VOL-204: `BGTaskScheduler.submit` failures used to be silently
    // swallowed via `try?`. Operators could not distinguish "user has
    // background-refresh disabled" from "request entitlements missing"
    // from "system rate-limited the submission" from "everything is
    // fine, just no wake yet." Now we wrap submits in do/catch, emit
    // typed telemetry on both success and failure (so operations can
    // see scheduling health in Sentry / UserDefaults sink), and log
    // to `os.Logger` so a deployment without a configured telemetry
    // sink still surfaces the failure in Console.app.
    @MainActor
    @discardableResult
    static func scheduleAppRefresh() -> Bool {
        let request = BGAppRefreshTaskRequest(identifier: appRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        return submit(request, identifier: appRefreshIdentifier, kind: "app_refresh")
    }

    @MainActor
    @discardableResult
    static func scheduleAppProcessing() -> Bool {
        let request = BGProcessingTaskRequest(identifier: appProcessingIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60 * 60)
        return submit(request, identifier: appProcessingIdentifier, kind: "app_processing")
    }

    /// Shared submission seam — visible to tests via a fake
    /// `BGTaskScheduler` (the test seam is the function-level
    /// indirection here, not a protocol over `BGTaskScheduler` itself
    /// which is a system singleton). Returns true on success, false on
    /// `BGTaskScheduler.submit` throw. Either way emits one telemetry
    /// event so operators can see scheduling health.
    ///
    /// `@MainActor` so it can read the `telemetrySink` static (VOL-204)
    /// under Swift 6 strict concurrency. `BGTaskScheduler.shared.submit`
    /// is documented as thread-safe, so running on main is fine.
    @MainActor
    @discardableResult
    static func submit(
        _ request: BGTaskRequest,
        identifier: String,
        kind: String
    ) -> Bool {
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("BGTaskScheduler.submit ok: \(identifier, privacy: .public)")
            telemetrySink?.record(TelemetryEvent(
                category: "background",
                name: "schedule_submitted",
                severity: .info,
                message: "BGTaskScheduler.submit accepted \(identifier).",
                metadata: ["kind": kind, "identifier": identifier]
            ))
            return true
        } catch {
            let bgError = (error as? BGTaskScheduler.Error)
            let errorCode = bgError.map { String(describing: $0.code) } ?? "unknown"
            let errorDescription = (error as NSError).localizedDescription
            // Wrapped across lines so the resulting source line fits
            // SwiftLint's 150-char rule. The `\` line-continuations
            // suppress the newlines in the rendered string at runtime,
            // so the os.Logger output is still a single line.
            logger.error(
                """
                BGTaskScheduler.submit failed for \
                \(identifier, privacy: .public): \
                \(errorCode, privacy: .public) — \
                \(errorDescription, privacy: .public)
                """
            )
            telemetrySink?.record(TelemetryEvent(
                category: "background",
                name: "schedule_failed",
                severity: .error,
                message: "BGTaskScheduler.submit failed for \(identifier): \(errorCode).",
                metadata: [
                    "kind": kind,
                    "identifier": identifier,
                    "error_code": errorCode,
                    "error_description": errorDescription
                ]
            ))
            return false
        }
    }

    // MARK: - Handlers

    private static func handleAppRefresh(_ task: BGAppRefreshTask) {
        let completion = TaskCompletion(task: task)

        task.expirationHandler = {
            completion.complete(success: false)
        }

        Task { @MainActor in
            // VOL-204: reschedule on the main actor since
            // `scheduleAppRefresh` is now `@MainActor`-isolated (it
            // touches the `telemetrySink` static). The handler closure
            // itself is dispatched on a system queue by BGTaskScheduler,
            // so the hop into main has to happen here.
            scheduleAppRefresh()
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
        let completion = TaskCompletion(task: task)

        task.expirationHandler = {
            completion.complete(success: false)
        }

        Task { @MainActor in
            // VOL-204: same main-actor hop reason as `handleAppRefresh`.
            scheduleAppProcessing()
            if let model = sharedModel {
                await model.performBackgroundProcessing()
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
