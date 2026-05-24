import Foundation

extension WorkoutAutopilotState {
    func liveActivitySetProgressSummary(
        loggedSetCount: Int,
        totalSets: Int = WorkoutKitPrescription.defaultSetCount
    ) -> String {
        let boundedTotalSets = max(totalSets, 1)
        let currentSet = min(max(loggedSetCount + 1, 1), boundedTotalSets)
        let weight = nextTarget.weight.formatted(.number.precision(.fractionLength(0...1)))
        return String(
            localized: "Set \(currentSet)/\(boundedTotalSets) · \(weight) \(nextTarget.unit)",
            comment: "Live Activity set-progress line; placeholders are current set, total sets, target weight, and unit."
        )
    }
}
