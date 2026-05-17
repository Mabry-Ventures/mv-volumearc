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
    /// Produce the current recovery snapshot. Implementations are
    /// expected to absorb their own errors (HK availability, auth
    /// failures, sample-fetch failures) and return `RecoveryContext()`
    /// or a partial context — never throw. The dashboard treats an
    /// empty context as "no recovery section" rather than surfacing
    /// a UI failure. Dropping `throws` from the protocol surface
    /// matches the practical behavior implementations already follow
    /// and lets the Swift compiler reason about call-site
    /// existentials without typed-throws inference quirks.
    func currentRecovery(now: Date) async -> RecoveryContext
}

/// Default no-op reader. Returns an empty `RecoveryContext`, which
/// makes `RecoveryContext.hasAnyData == false` and causes
/// `CoachContext.asPromptBlock` to omit the recovery section entirely.
/// Used on non-iOS targets and as the test default.
public struct UnavailableRecoveryReader: RecoveryReader {
    public init() {}

    public func currentRecovery(now: Date = .now) async -> RecoveryContext {
        RecoveryContext()
    }
}
