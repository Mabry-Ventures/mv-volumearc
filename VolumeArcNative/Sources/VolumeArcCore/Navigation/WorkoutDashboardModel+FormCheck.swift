#if canImport(SwiftUI)
import Foundation

extension WorkoutDashboardModel {
    public func recordFormCheckAnalysis(_ analysis: FormCheckAnalysis) {
        latestFormCheckAnalysis = analysis
        telemetrySink.record(TelemetryEvent(
            category: "form_check",
            name: "completed",
            severity: .info,
            message: analysis.summaryLine,
            metadata: [
                "exercise": analysis.exercise.rawValue,
                "verdict": analysis.verdict.rawValue,
                "reps": "\(analysis.repCount)",
                "haptic": analysis.hapticCode.rawValue,
            ]
        ))
    }
}
#endif
