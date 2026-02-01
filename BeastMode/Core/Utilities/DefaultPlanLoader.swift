import Foundation
import SwiftData

/// Utility for loading default workout plans
enum DefaultPlanLoader {
    /// Load the default Beast Mode workout plan into the model context
    @MainActor
    static func loadDefaultPlan(into context: ModelContext) {
        guard let url = Bundle.main.url(forResource: "DefaultWorkoutPlans", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            print("Failed to load default workout plan JSON")
            loadHardcodedPlan(into: context)
            return
        }

        do {
            let planData = try JSONDecoder().decode(WorkoutPlanData.self, from: data)
            createPlan(from: planData, in: context)
        } catch {
            print("Failed to decode workout plan: \(error)")
            loadHardcodedPlan(into: context)
        }
    }

    /// Create a WorkoutPlan from decoded data
    @MainActor
    private static func createPlan(from data: WorkoutPlanData, in context: ModelContext) {
        let plan = WorkoutPlan(name: data.name, isActive: true)
        context.insert(plan)

        for (index, dayData) in data.days.enumerated() {
            guard let weekday = Weekday(rawValue: dayData.weekday) else { continue }

            let day = PlannedDay(
                weekday: weekday,
                focusArea: dayData.focusArea,
                sortOrder: index
            )
            day.plan = plan

            for (exerciseIndex, exerciseData) in dayData.exercises.enumerated() {
                let exerciseType = ExerciseType(rawValue: exerciseData.type) ?? .strength

                let exercise = PlannedExercise(
                    name: exerciseData.name,
                    targetSets: exerciseData.sets,
                    targetRepsMin: exerciseData.repsMin,
                    targetRepsMax: exerciseData.repsMax,
                    exerciseType: exerciseType,
                    notes: exerciseData.notes,
                    sortOrder: exerciseIndex
                )
                exercise.day = day
                day.exercises.append(exercise)
            }

            plan.days.append(day)
        }

        try? context.save()
    }

    /// Fallback hardcoded plan if JSON loading fails
    @MainActor
    private static func loadHardcodedPlan(into context: ModelContext) {
        let plan = WorkoutPlan(name: "Beast Mode Split", isActive: true)
        context.insert(plan)

        let daysData: [(Weekday, String, [(String, Int, Int, Int, ExerciseType)])] = [
            (.sunday, "Rest", []),
            (.monday, "Push", [
                ("Barbell Bench Press", 4, 6, 8, .strength),
                ("Incline Dumbbell Press", 3, 8, 12, .strength),
                ("Overhead Press", 3, 8, 10, .strength),
                ("Lateral Raises", 3, 12, 15, .strength),
                ("Tricep Pushdowns", 3, 10, 12, .strength),
                ("Overhead Tricep Extension", 3, 10, 12, .strength)
            ]),
            (.tuesday, "Pull", [
                ("Deadlift", 4, 5, 6, .strength),
                ("Pull-ups", 4, 6, 10, .strength),
                ("Barbell Rows", 3, 8, 10, .strength),
                ("Face Pulls", 3, 15, 20, .strength),
                ("Barbell Curls", 3, 10, 12, .strength),
                ("Hammer Curls", 3, 10, 12, .strength)
            ]),
            (.wednesday, "Legs", [
                ("Barbell Squats", 4, 6, 8, .strength),
                ("Romanian Deadlift", 3, 8, 10, .strength),
                ("Leg Press", 3, 10, 12, .strength),
                ("Leg Curls", 3, 10, 12, .strength),
                ("Calf Raises", 4, 12, 15, .strength),
                ("Plank", 3, 60, 60, .timed)
            ]),
            (.thursday, "Push", [
                ("Dumbbell Bench Press", 4, 8, 10, .strength),
                ("Cable Flyes", 3, 12, 15, .strength),
                ("Arnold Press", 3, 8, 10, .strength),
                ("Front Raises", 3, 12, 15, .strength),
                ("Skull Crushers", 3, 10, 12, .strength),
                ("Diamond Push-ups", 3, 12, 15, .strength)
            ]),
            (.friday, "Pull", [
                ("Barbell Rows", 4, 6, 8, .strength),
                ("Lat Pulldown", 3, 10, 12, .strength),
                ("Seated Cable Row", 3, 10, 12, .strength),
                ("Reverse Flyes", 3, 15, 20, .strength),
                ("Preacher Curls", 3, 10, 12, .strength),
                ("Incline Curls", 3, 10, 12, .strength)
            ]),
            (.saturday, "Legs + Core", [
                ("Front Squats", 4, 6, 8, .strength),
                ("Walking Lunges", 3, 12, 12, .strength),
                ("Leg Extensions", 3, 12, 15, .strength),
                ("Glute Bridges", 3, 12, 15, .strength),
                ("Hanging Leg Raises", 3, 10, 15, .core),
                ("Cable Crunches", 3, 15, 20, .core)
            ])
        ]

        for (index, (weekday, focusArea, exercises)) in daysData.enumerated() {
            let day = PlannedDay(
                weekday: weekday,
                focusArea: focusArea,
                sortOrder: index
            )
            day.plan = plan

            for (exerciseIndex, (name, sets, repsMin, repsMax, type)) in exercises.enumerated() {
                let exercise = PlannedExercise(
                    name: name,
                    targetSets: sets,
                    targetRepsMin: repsMin,
                    targetRepsMax: repsMax,
                    exerciseType: type,
                    sortOrder: exerciseIndex
                )
                exercise.day = day
                day.exercises.append(exercise)
            }

            plan.days.append(day)
        }

        try? context.save()
    }
}

// MARK: - JSON Data Structures

struct WorkoutPlanData: Codable {
    let name: String
    let days: [DayData]

    struct DayData: Codable {
        let weekday: Int
        let focusArea: String
        let exercises: [ExerciseData]
    }

    struct ExerciseData: Codable {
        let name: String
        let sets: Int
        let repsMin: Int
        let repsMax: Int
        let type: String
        let notes: String?
    }
}
