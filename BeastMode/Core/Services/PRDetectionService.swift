// PRDetectionService.swift
// BeastMode
// Service for detecting personal records

import Foundation
import SwiftData

/// Service for detecting and recording personal records
actor PRDetectionService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Checks if a completed set represents a new PR
    /// Returns the PR type if detected, nil otherwise
    func checkForPR(
        exerciseName: String,
        weight: Double,
        reps: Int,
        userId: UUID
    ) async -> PRType? {
        // Validate inputs
        guard weight > 0, reps > 0 else { return nil }

        // Fetch existing PRs for this exercise and user
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate<PersonalRecord> { pr in
                pr.exerciseName == exerciseName && pr.userId == userId
            },
            sortBy: [SortDescriptor(\.estimatedOneRepMax, order: .reverse)]
        )

        let existingPRs = try? modelContext.fetch(descriptor)
        let currentE1RM = calculateE1RM(weight: weight, reps: reps)

        guard let bestPR = existingPRs?.first else {
            // First ever logged set for this exercise = automatic PR
            return .firstTime
        }

        // Check for estimated max PR (most important)
        if currentE1RM > bestPR.estimatedOneRepMax {
            let improvement = currentE1RM - bestPR.estimatedOneRepMax
            return .estimatedMax(improvement: improvement)
        }

        // Check for heaviest weight ever
        let maxWeight = existingPRs?.map(\.weight).max() ?? 0
        if weight > maxWeight {
            return .heaviestWeight(weight: weight)
        }

        // Check for rep PR at same weight (within 0.5 lbs tolerance)
        let sameWeightPRs = existingPRs?.filter { abs($0.weight - weight) < 0.5 }
        if let maxRepsAtWeight = sameWeightPRs?.map(\.reps).max(),
           reps > maxRepsAtWeight {
            return .repRecord(atWeight: weight, reps: reps)
        }

        return nil
    }

    /// Saves a PR to the database
    func savePR(
        exerciseName: String,
        weight: Double,
        reps: Int,
        prType: PRType,
        sourceSetId: UUID,
        userId: UUID
    ) async throws {
        let e1rm = calculateE1RM(weight: weight, reps: reps)

        let pr = PersonalRecord(
            exerciseName: exerciseName,
            weight: weight,
            reps: reps,
            estimatedOneRepMax: e1rm,
            date: .now,
            sourceSetId: sourceSetId,
            prType: prType,
            userId: userId
        )

        modelContext.insert(pr)
        try modelContext.save()
    }

    /// Calculates estimated one-rep max using Brzycki formula
    /// - Parameters:
    ///   - weight: Weight lifted
    ///   - reps: Number of reps performed
    /// - Returns: Estimated 1RM
    func calculateE1RM(weight: Double, reps: Int) -> Double {
        // Brzycki formula: weight × (36 / (37 - reps))
        // Most accurate for reps <= 12
        guard reps > 0 else { return weight }

        if reps == 1 {
            return weight
        }

        // For high reps, cap at 12 for formula accuracy
        let effectiveReps = min(reps, 12)
        return weight * (36.0 / (37.0 - Double(effectiveReps)))
    }

    /// Get all PRs for a user
    func getAllPRs(for userId: UUID) async throws -> [PersonalRecord] {
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate<PersonalRecord> { $0.userId == userId },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Get PRs for a specific exercise
    func getPRs(for exerciseName: String, userId: UUID) async throws -> [PersonalRecord] {
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate<PersonalRecord> { pr in
                pr.exerciseName == exerciseName && pr.userId == userId
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Get the best E1RM for an exercise
    func getBestE1RM(for exerciseName: String, userId: UUID) async throws -> Double? {
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate<PersonalRecord> { pr in
                pr.exerciseName == exerciseName && pr.userId == userId
            },
            sortBy: [SortDescriptor(\.estimatedOneRepMax, order: .reverse)]
        )

        let results = try modelContext.fetch(descriptor)
        return results.first?.estimatedOneRepMax
    }

    /// Get count of all PRs for a user
    func getPRCount(for userId: UUID) async throws -> Int {
        let descriptor = FetchDescriptor<PersonalRecord>(
            predicate: #Predicate<PersonalRecord> { $0.userId == userId }
        )
        return try modelContext.fetchCount(descriptor)
    }
}
