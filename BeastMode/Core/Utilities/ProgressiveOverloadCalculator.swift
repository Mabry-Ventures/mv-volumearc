import Foundation

/// Calculator for progressive overload recommendations
struct ProgressiveOverloadCalculator {
    /// Standard weight increment for upper body exercises (lbs)
    static let upperBodyIncrement: Double = 5.0

    /// Standard weight increment for lower body exercises (lbs)
    static let lowerBodyIncrement: Double = 10.0

    /// Minimum weight increment (lbs)
    static let minimumIncrement: Double = 2.5

    /// Calculate suggested weight progression
    static func suggestNextWeight(
        currentWeight: Double,
        completedReps: Int,
        targetRepsMin: Int,
        targetRepsMax: Int,
        exerciseType: ExerciseCategory = .upper
    ) -> WeightSuggestion {
        let increment = exerciseType == .lower ? lowerBodyIncrement : upperBodyIncrement

        // If completed reps exceed target max, increase weight
        if completedReps >= targetRepsMax {
            let newWeight = currentWeight + increment
            return WeightSuggestion(
                currentWeight: currentWeight,
                suggestedWeight: newWeight,
                targetReps: targetRepsMin,
                reasoning: "Great work! You hit \(completedReps) reps. Time to go heavier.",
                progressionType: .increase
            )
        }

        // If completed reps are below target min, consider deload or maintain
        if completedReps < targetRepsMin {
            // If significantly below, suggest deload
            if completedReps < targetRepsMin - 2 {
                let deloadWeight = max(minimumIncrement, currentWeight * 0.9)
                return WeightSuggestion(
                    currentWeight: currentWeight,
                    suggestedWeight: deloadWeight,
                    targetReps: targetRepsMax,
                    reasoning: "Consider a slight deload to build back up with better form.",
                    progressionType: .deload
                )
            }

            // Otherwise maintain and focus on getting more reps
            return WeightSuggestion(
                currentWeight: currentWeight,
                suggestedWeight: currentWeight,
                targetReps: targetRepsMin,
                reasoning: "Keep at this weight and aim for \(targetRepsMin) reps next time.",
                progressionType: .maintain
            )
        }

        // Within target range - maintain and push for more reps
        return WeightSuggestion(
            currentWeight: currentWeight,
            suggestedWeight: currentWeight,
            targetReps: min(completedReps + 1, targetRepsMax),
            reasoning: "Good work! Try to get \(min(completedReps + 1, targetRepsMax)) reps next session.",
            progressionType: .maintain
        )
    }

    /// Analyze a series of sets and provide recommendations
    static func analyzePerformance(
        recentSets: [(weight: Double, reps: Int, date: Date)],
        targetRepsMin: Int,
        targetRepsMax: Int,
        exerciseCategory: ExerciseCategory = .upper
    ) -> PerformanceAnalysis {
        guard !recentSets.isEmpty else {
            return PerformanceAnalysis(
                trend: .insufficient,
                suggestion: "Log some sets to get personalized recommendations.",
                confidenceLevel: .low
            )
        }

        // Sort by date, most recent first
        let sortedSets = recentSets.sorted { $0.date > $1.date }

        // Calculate average performance
        let avgWeight = sortedSets.map(\.weight).reduce(0, +) / Double(sortedSets.count)
        let avgReps = Double(sortedSets.map(\.reps).reduce(0, +)) / Double(sortedSets.count)

        // Analyze trend (comparing recent vs older)
        let trend: PerformanceTrend
        if sortedSets.count >= 4 {
            let recentAvg = sortedSets.prefix(2).map { $0.weight * Double($0.reps) }.reduce(0, +) / 2
            let olderAvg = sortedSets.dropFirst(2).prefix(2).map { $0.weight * Double($0.reps) }.reduce(0, +) / 2

            if recentAvg > olderAvg * 1.05 {
                trend = .improving
            } else if recentAvg < olderAvg * 0.95 {
                trend = .declining
            } else {
                trend = .maintaining
            }
        } else {
            trend = .insufficient
        }

        // Generate suggestion based on analysis
        let suggestion: String
        let confidenceLevel: ConfidenceLevel

        switch trend {
        case .improving:
            let nextWeight = suggestNextWeight(
                currentWeight: avgWeight,
                completedReps: Int(avgReps),
                targetRepsMin: targetRepsMin,
                targetRepsMax: targetRepsMax,
                exerciseType: exerciseCategory
            )
            suggestion = "Strong progress! \(nextWeight.reasoning)"
            confidenceLevel = .high

        case .declining:
            suggestion = "Consider a deload week or check recovery factors (sleep, nutrition, stress)."
            confidenceLevel = .medium

        case .maintaining:
            if avgReps >= Double(targetRepsMax) {
                suggestion = "Consistent performance at top of rep range. Ready to increase weight!"
            } else {
                suggestion = "Solid consistency. Focus on adding one rep per session."
            }
            confidenceLevel = .high

        case .insufficient:
            suggestion = "Keep logging workouts to get better recommendations."
            confidenceLevel = .low
        }

        return PerformanceAnalysis(
            trend: trend,
            suggestion: suggestion,
            confidenceLevel: confidenceLevel,
            averageWeight: avgWeight,
            averageReps: avgReps
        )
    }

    /// Calculate estimated one rep max
    static func estimateOneRepMax(weight: Double, reps: Int) -> Double {
        if reps == 1 { return weight }
        // Epley formula
        return weight * (1 + Double(reps) / 30)
    }

    /// Calculate weight for a target rep count based on 1RM
    static func weightForReps(oneRepMax: Double, targetReps: Int) -> Double {
        if targetReps == 1 { return oneRepMax }
        // Inverse of Epley formula
        return oneRepMax / (1 + Double(targetReps) / 30)
    }
}

// MARK: - Supporting Types

enum ExerciseCategory {
    case upper
    case lower
    case core
}

enum ProgressionType {
    case increase
    case maintain
    case deload
}

struct WeightSuggestion {
    let currentWeight: Double
    let suggestedWeight: Double
    let targetReps: Int
    let reasoning: String
    let progressionType: ProgressionType

    var changeAmount: Double {
        suggestedWeight - currentWeight
    }

    var changePercentage: Double {
        guard currentWeight > 0 else { return 0 }
        return (changeAmount / currentWeight) * 100
    }
}

enum PerformanceTrend {
    case improving
    case maintaining
    case declining
    case insufficient

    var displayName: String {
        switch self {
        case .improving: return "Improving"
        case .maintaining: return "Maintaining"
        case .declining: return "Declining"
        case .insufficient: return "More Data Needed"
        }
    }

    var icon: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .maintaining: return "arrow.right"
        case .declining: return "arrow.down.right"
        case .insufficient: return "questionmark"
        }
    }
}

enum ConfidenceLevel {
    case high
    case medium
    case low

    var displayName: String {
        switch self {
        case .high: return "High Confidence"
        case .medium: return "Medium Confidence"
        case .low: return "Low Confidence"
        }
    }
}

struct PerformanceAnalysis {
    let trend: PerformanceTrend
    let suggestion: String
    let confidenceLevel: ConfidenceLevel
    var averageWeight: Double?
    var averageReps: Double?
}
