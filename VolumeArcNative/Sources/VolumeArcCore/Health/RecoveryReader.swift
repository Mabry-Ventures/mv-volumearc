import Foundation

/// VOL-181 Phase 1B: platform-agnostic seam for producing a
/// `RecoveryContext` from a recovery data source (typically HealthKit
/// at the App layer, but a fake/empty implementation here in Core so
/// non-iOS targets and unit tests compile without HK imports).
///
/// The default `UnavailableRecoveryReader` returns an empty
/// `RecoveryContext()`. `WorkoutDashboardModel` injects this seam so
/// the coach prompt's recovery section gracefully degrades when HK is
/// unavailable (macOS test host, unauthorized device, watchOS-only
/// build) without any caller-side branching.
public protocol RecoveryReader: Sendable {
    /// Produce the current recovery snapshot. Implementations must be
    /// non-throwing-on-no-data — return `RecoveryContext()` (or a
    /// partial context with only some fields populated) when HK has
    /// no samples in the relevant window. The only throw should be
    /// HK availability/authorization errors.
    func currentRecovery(now: Date) async throws -> RecoveryContext
}

/// Default no-op reader. Returns an empty `RecoveryContext`, which
/// makes `RecoveryContext.hasAnyData == false` and causes
/// `CoachContext.asPromptBlock` to omit the recovery section entirely.
/// Used on non-iOS targets and as the test default.
public struct UnavailableRecoveryReader: RecoveryReader {
    public init() {}

    public func currentRecovery(now: Date = .now) async throws -> RecoveryContext {
        RecoveryContext()
    }
}
