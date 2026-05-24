import CryptoKit
import Foundation

/// Structural, privacy-scoped representation of a VolumeArc prescription that
/// can be exported to Apple's WorkoutKit surface.
public struct WorkoutKitPrescription: Sendable, Equatable {
    public static let defaultSetCount = 3
    public static let defaultRestDuration: TimeInterval = 90

    /// Data exported to WorkoutKit. Keep this list intentionally structural:
    /// no coach prompt text, no readiness factors, no athlete profile fields.
    public static let dataScope: [String] = [
        "workout identifier",
        "exercise identifier",
        "exercise display name",
        "HealthKit activity category",
        "target weight",
        "target unit",
        "target rep range",
        "working set count",
        "rest interval",
    ]

    public let workoutID: String
    public let exerciseID: String
    public let exerciseName: String
    public let activityType: WorkoutActivityType
    public let target: WorkoutTarget
    public let setCount: Int
    public let restDuration: TimeInterval

    public init(
        workoutID: String,
        exerciseID: String,
        exerciseName: String,
        activityType: WorkoutActivityType,
        target: WorkoutTarget,
        setCount: Int = Self.defaultSetCount,
        restDuration: TimeInterval = Self.defaultRestDuration
    ) {
        self.workoutID = workoutID
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.activityType = activityType
        self.target = target
        self.setCount = max(1, setCount)
        self.restDuration = max(0, restDuration)
    }

    public init(
        autopilot: WorkoutAutopilotState,
        workoutID: String,
        setCount: Int = Self.defaultSetCount,
        restDuration: TimeInterval = Self.defaultRestDuration
    ) {
        let exercise = VolumeArcExerciseCatalog.exercise(withID: autopilot.nextExerciseID)
        self.init(
            workoutID: workoutID,
            exerciseID: autopilot.nextExerciseID,
            exerciseName: autopilot.nextExerciseName,
            activityType: exercise?.healthKitActivityType.workoutActivityType ?? .strengthTraining,
            target: autopilot.nextTarget,
            setCount: setCount,
            restDuration: restDuration
        )
    }

    public var planID: UUID {
        Self.stablePlanID(for: workoutID)
    }

    public var workStepDisplayName: String {
        let weight = target.weight.formatted(.number.precision(.fractionLength(0...1)))
        return "\(exerciseName) \(weight)\(target.unit) x \(target.repRange.lowerBound)-\(target.repRange.upperBound)"
    }

    public var recoveryStepDisplayName: String {
        "Rest \(Int(restDuration.rounded())) seconds"
    }

    public static func stablePlanID(for workoutID: String) -> UUID {
        let digest = SHA256.hash(data: Data(workoutID.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

public extension HKActivityTypeMapping {
    var workoutActivityType: WorkoutActivityType {
        switch self {
        case .traditional: return .strengthTraining
        case .functional: return .functionalStrengthTraining
        case .core: return .coreTraining
        }
    }
}

public enum WorkoutKitScheduleAuthorization: String, Sendable, Equatable {
    case notDetermined
    case restricted
    case denied
    case authorized
    case unavailable
}

public enum WorkoutKitSchedulingError: Error, LocalizedError, Sendable, Equatable {
    case unsupported
    case authorizationDenied(WorkoutKitScheduleAuthorization)

    public var errorDescription: String? {
        switch self {
        case .unsupported:
            return "WorkoutKit scheduling is unavailable on this device."
        case let .authorizationDenied(state):
            return "WorkoutKit scheduling authorization is \(state.rawValue)."
        }
    }
}

public protocol WorkoutKitScheduling: Sendable {
    func authorizationState() async -> WorkoutKitScheduleAuthorization
    func requestAuthorization() async -> WorkoutKitScheduleAuthorization
    func schedule(_ prescription: WorkoutKitPrescription, at date: DateComponents) async throws
    func openInWorkoutApp(_ prescription: WorkoutKitPrescription) async throws
}

public extension WorkoutKitScheduling {
    func openInWorkoutApp(_ prescription: WorkoutKitPrescription) async throws {
        _ = prescription
        throw WorkoutKitSchedulingError.unsupported
    }
}

public struct UnavailableWorkoutKitScheduler: WorkoutKitScheduling {
    public init() {}

    public func authorizationState() async -> WorkoutKitScheduleAuthorization {
        .unavailable
    }

    public func requestAuthorization() async -> WorkoutKitScheduleAuthorization {
        .unavailable
    }

    public func schedule(_ prescription: WorkoutKitPrescription, at date: DateComponents) async throws {
        _ = prescription
        _ = date
        throw WorkoutKitSchedulingError.unsupported
    }
}

#if canImport(HealthKit) && canImport(WorkoutKit)
import HealthKit
@preconcurrency import WorkoutKit

@available(iOS 17.0, watchOS 10.0, *)
public enum VolumeArcWorkoutKitPlanFactory {
    public static func customWorkout(for prescription: WorkoutKitPrescription) -> CustomWorkout {
        CustomWorkout(
            activity: prescription.activityType.healthKitActivityType,
            location: .indoor,
            displayName: "VolumeArc \(prescription.exerciseName)",
            blocks: [
                IntervalBlock(
                    steps: [
                        IntervalStep(
                            .work,
                            step: WorkoutStep(
                                goal: .open,
                                displayName: prescription.workStepDisplayName
                            )
                        ),
                        IntervalStep(
                            .recovery,
                            step: WorkoutStep(
                                goal: .time(prescription.restDuration, .seconds),
                                displayName: prescription.recoveryStepDisplayName
                            )
                        ),
                    ],
                    iterations: prescription.setCount
                ),
            ]
        )
    }

    public static func workoutPlan(for prescription: WorkoutKitPrescription) -> WorkoutPlan {
        WorkoutPlan(.custom(customWorkout(for: prescription)), id: prescription.planID)
    }
}

public extension WorkoutActivityType {
    var healthKitActivityType: HKWorkoutActivityType {
        switch self {
        case .strengthTraining: return .traditionalStrengthTraining
        case .functionalStrengthTraining: return .functionalStrengthTraining
        case .coreTraining: return .coreTraining
        case .mixedCardio: return .mixedCardio
        }
    }
}

@available(iOS 17.0, watchOS 10.0, *)
public actor SystemWorkoutKitScheduler: WorkoutKitScheduling {
    public init() {}

    public func authorizationState() async -> WorkoutKitScheduleAuthorization {
        guard WorkoutScheduler.isSupported else { return .unavailable }
        return await WorkoutScheduler.shared.authorizationState.volumeArcState
    }

    public func requestAuthorization() async -> WorkoutKitScheduleAuthorization {
        guard WorkoutScheduler.isSupported else { return .unavailable }
        return await WorkoutScheduler.shared.requestAuthorization().volumeArcState
    }

    public func schedule(_ prescription: WorkoutKitPrescription, at date: DateComponents) async throws {
        guard WorkoutScheduler.isSupported else { throw WorkoutKitSchedulingError.unsupported }
        let state = await authorizationState()
        let finalState = state == .notDetermined ? await requestAuthorization() : state
        guard finalState == .authorized else {
            throw WorkoutKitSchedulingError.authorizationDenied(finalState)
        }
        await WorkoutScheduler.shared.schedule(
            VolumeArcWorkoutKitPlanFactory.workoutPlan(for: prescription),
            at: date
        )
    }

    public func openInWorkoutApp(_ prescription: WorkoutKitPrescription) async throws {
        #if os(watchOS)
        try await VolumeArcWorkoutKitPlanFactory.workoutPlan(for: prescription).openInWorkoutApp()
        #else
        _ = prescription
        throw WorkoutKitSchedulingError.unsupported
        #endif
    }
}

@available(iOS 17.0, watchOS 10.0, *)
private extension WorkoutScheduler.AuthorizationState {
    var volumeArcState: WorkoutKitScheduleAuthorization {
        switch self {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        @unknown default: return .unavailable
        }
    }
}
#endif
