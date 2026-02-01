# Claude.md - Beast Mode Project Documentation

This document provides context for Claude Code sessions working on the Beast Mode workout tracker app.

## Project Overview

Beast Mode is a SwiftUI/SwiftData iOS fitness tracking app focused on strength training. The app emphasizes the emotional experience of hitting personal records (PRs) with celebrations, social sharing, gamification, AI-powered analytics, and custom workout planning.

**Current Version**: 1.3.1 "Iron Clad"
**Platform**: iOS 17+, macOS 14+, watchOS 10+
**Architecture**: SwiftUI + SwiftData + MVVM

## Project Structure

```
BeastMode/
├── App/
│   ├── BeastModeApp.swift          # Main entry point, SwiftData container, deep links
│   └── ContentView.swift           # Tab navigation (5 tabs), main views
├── Core/
│   ├── Models/
│   │   ├── Analytics.swift         # Analytics models, trends, time ranges (V1.2)
│   │   ├── Exercise.swift          # Exercise definitions, categories, types
│   │   ├── PersonalRecord.swift    # PR model with PRType enum
│   │   ├── SetLog.swift            # Individual set tracking
│   │   ├── Streak.swift            # UserStreak model, Badge enum (15 badges)
│   │   ├── UserProfile.swift       # User prefs, rest timer settings
│   │   ├── Workout.swift           # Workout + WorkoutExercise models
│   │   └── WorkoutPlan.swift       # Plan, PlanDay, PlanExercise models (V1.3)
│   └── Services/
│       ├── AICoachService.swift        # Claude API integration for AI coaching (V1.2)
│       ├── AnalyticsService.swift      # Progressive overload analytics (V1.2)
│       ├── ComplicationUpdateService.swift # Watch complication updates (V1.3)
│       ├── HealthKitService.swift      # HealthKit body weight integration (V1.2)
│       ├── PlanSharingService.swift    # Plan export/import/sharing (V1.3)
│       ├── PRDetectionService.swift    # PR detection with Brzycki E1RM formula
│       ├── RestTimerService.swift      # Smart rest duration + timer manager
│       ├── StreakService.swift         # Streak tracking, badge awards
│       └── WeeklyReviewService.swift   # AI weekly review generation (V1.2)
├── Features/
│   ├── AICoach/
│   │   └── WeeklyReviewView.swift      # AI-powered weekly review UI (V1.2)
│   ├── Celebrations/
│   │   └── PRCelebrationView.swift     # Full-screen PR celebration + coordinator
│   ├── Progress/
│   │   ├── AnalyticsDashboardView.swift    # Main analytics dashboard (V1.2)
│   │   ├── BodyWeightChartView.swift       # HealthKit weight chart (V1.2)
│   │   └── ExerciseDetailAnalyticsView.swift # Exercise trends detail (V1.2)
│   ├── Settings/
│   │   └── RestTimerSettingsView.swift # Rest timer customization UI
│   ├── Sharing/
│   │   └── PRShareCardGenerator.swift  # Shareable PR image cards
│   ├── Streaks/
│   │   ├── BadgeDisplayView.swift      # Badge collection + detail views
│   │   └── StreakDisplayView.swift     # Streak flame + weekly progress
│   ├── WeeklyPlan/                     # Custom workout plans (V1.3)
│   │   ├── AddExerciseSheet.swift      # Add exercise to plan day
│   │   ├── DayEditorView.swift         # Edit individual plan day
│   │   ├── ImportPlanSheet.swift       # Import plan from file/code
│   │   ├── PlanEditorView.swift        # Create/edit workout plans
│   │   ├── PlanLibraryView.swift       # Browse and manage plans
│   │   └── SharePlanSheet.swift        # Share plan via file/link/code
│   └── Workout/
│       └── SetInputView.swift          # Set input with PR integration
└── UI/
    └── Components/                     # Reusable UI components
BeastModeWatch/                         # Apple Watch Extension (V1.3)
└── Complications/
    ├── ComplicationDataProvider.swift  # Timeline provider, data manager
    ├── StreakComplication.swift        # Streak + weekly progress widgets
    └── TodayWorkoutComplication.swift  # Today's workout widget
Tests/
└── BeastModeTests/
    ├── Core/
    │   ├── Services/                       # Service unit tests (V1.3.1)
    │   │   ├── AnalyticsServiceTests.swift      # Trend calculations, overview tests
    │   │   ├── PlanSharingServiceTests.swift    # Export, import, validation tests
    │   │   ├── PRDetectionServiceTests.swift    # E1RM, PR type detection tests
    │   │   └── StreakServiceTests.swift         # Streak, badge award tests
    │   └── Utilities/
    │       └── UtilityTests.swift               # WeekCalculator, E1RM, ProgressiveOverload
    ├── Integration/                        # Integration tests (V1.3.1)
    │   └── WorkoutFlowIntegrationTests.swift    # End-to-end workout flows
    ├── Performance/                        # Performance tests (V1.3.1)
    │   └── AnalyticsPerformanceTests.swift      # Large dataset, batch, memory tests
    ├── Snapshots/                          # Snapshot tests (V1.3.1)
    │   ├── SnapshotTestCase.swift               # Base configuration, helpers
    │   ├── Components/
    │   │   ├── PRCelebrationSnapshotTests.swift     # PR badge, celebration snapshots
    │   │   └── StreakBadgeSnapshotTests.swift       # Streak, badge, progress snapshots
    │   └── __Snapshots__/                       # Reference images
    └── Support/                            # Test infrastructure (V1.3.1)
        ├── ModelContainerFactory.swift          # In-memory SwiftData containers
        ├── Fixtures/
        │   ├── PRFixtures.swift                 # PR test data, scenarios
        │   ├── UserFixtures.swift               # User profiles, streaks
        │   └── WorkoutFixtures.swift            # Workouts, plans, sets
        └── Mocks/
            ├── MockAICoachService.swift         # Configurable AI mock
            ├── MockHealthKitService.swift       # HealthKit mock scenarios
            └── Protocols/
                └── ServiceProtocols.swift       # Protocol definitions for DI
```

## Version 1.3.1 Features (Iron Clad)

### Testing Infrastructure

**Swift Testing Framework**
- All tests use modern Swift Testing with `@Suite` and `@Test` macros
- Parameterized tests via `arguments:` parameter for comprehensive coverage
- Uses `#expect` macro for assertions instead of XCTAssert
- `@MainActor` annotation for SwiftData tests

**Test Infrastructure**
- `ModelContainerFactory` creates isolated in-memory SwiftData containers
- Factory methods: `makeContainer()`, `makePopulatedContainer()`, `makeAnalyticsContainer()`, `makeStreakContainer()`
- All tests run with fresh database state for isolation

**Test Fixtures**
- `UserFixtures`: `standardUser`, `metricUser`, `newUser`, `customTimerUser`
- `WorkoutFixtures`: `pplSplit()`, `makeWorkout()`, `benchWorkout()`, `generateWeekOfWorkouts()`
- `PRFixtures`: `benchPressPRHistory()`, `squatPRHistory()`, `e1rmImprovementScenarios`
- `StreakFixtures`: `newStreak()`, `activeStreak()`, `milestoneStreak()`

**Mock Services**
- `MockAICoachService`: Configurable responses, call tracking, error injection, delay simulation
- `MockHealthKitService`: Weight trend scenarios (gaining, losing, maintaining, denied)
- Protocol-based mocking via `ServiceProtocols.swift`

**Test Suites**
- `PRDetectionServiceTests`: First-time, E1RM, heaviest weight, rep records, edge cases
- `StreakServiceTests`: Streak calculation, badge awards, weekly progress
- `AnalyticsServiceTests`: Progress trends, volume trends, overview generation
- `PlanSharingServiceTests`: Export, import, share codes, validation
- `UtilityTests`: WeekCalculator, E1RMCalculator, ProgressiveOverloadCalculator

### Integration Tests
- `WorkoutFlowIntegrationTests`: Complete workout flow from plan to log to PR
- Multi-week analytics building verification
- PR detection across workout sessions
- Streak continuation across days
- Plan sharing export/import flow

### Performance Tests
- Analytics overview with 1000+ workouts (<2s threshold)
- PR detection with extensive history (<500ms threshold)
- Streak calculation with year of data (<500ms threshold)
- Batch workout insertion performance
- Exercise search with large library
- Memory stability during large data processing
- Concurrent analytics requests

### Snapshot Tests
- `SnapshotConfiguration` with device, color scheme, dynamic type variants
- `SnapshotWrapper` for consistent test rendering
- `PRCelebrationSnapshotTests`: PR badges, celebration modals
- `StreakBadgeSnapshotTests`: Streak display, achievement badges, weekly progress
- `SnapshotTestData` provides consistent test data

### CI/CD Configuration

**Xcode Test Plans**
- `BeastMode.xctestplan`: Development testing with coverage
- `BeastMode-CI.xctestplan`: CI testing (skips performance/snapshot tests)
- `BeastMode-Nightly.xctestplan`: Full suite with sanitizers

**GitHub Actions**
- `.github/workflows/test.yml`: Automated testing on push/PR
- Parallel build and test jobs
- Code coverage reporting with 80% threshold
- Nightly builds with full sanitizer suite
- SwiftLint code quality checks

**Coverage Script**
- `scripts/check_coverage.py`: Parse Xcode coverage JSON
- Reports overall, target, and file-level coverage
- Highlights low-coverage files (<70%)
- Tracks core service coverage separately

## Version 1.3 Features (Your Split)

### Custom Workout Plans
- `WorkoutPlan` model with days, exercises, and sharing properties
- `PlanDay` for individual days (weekday, name, isRestDay, exercises)
- `PlanExercise` for exercise templates (sets, rep range, RPE, rest)
- `PlanLibraryView` for browsing, creating, and managing plans
- `PlanEditorView` for creating/editing plans with day configuration
- `DayEditorView` for editing exercises within a day
- `AddExerciseSheet` for adding exercises with quick presets
- Template system: PPL, Upper/Lower, Full Body, Bro Split, Powerbuilding

### Plan Sharing
- `PlanSharingService` handles export/import operations
- Export as `.beastplan` file (JSON format)
- Share via deep link: `beastmode://import?plan=<base64>`
- Generate shareable 8-character codes
- `SharePlanSheet` with file, link, and code options
- `ImportPlanSheet` for importing from file or code
- `DeepLinkHandler` for handling incoming import URLs
- `ShareablePlan` DTO for serialization

### Apple Watch Complications
- `TodayWorkoutComplication` shows today's planned workout
- `StreakComplication` displays current streak with weekly progress ring
- `WeeklyProgressWidget` shows workout count toward weekly goal
- Supports: accessoryCircular, accessoryRectangular, accessoryInline, accessoryCorner
- `ComplicationDataManager` shares data via App Groups
- `ComplicationUpdateService` syncs data from iPhone

### Plan Types
```swift
enum PlanDifficulty: String, Codable {
    case beginner, intermediate, advanced
}

enum PlanGoal: String, Codable {
    case strength, hypertrophy, endurance, powerlifting, general
}

enum PlanTemplate: String, CaseIterable {
    case ppl, upperLower, fullBody, bro, powerbuilding
}
```

## Version 1.2 Features (Crystal Ball)

### HealthKit Integration
- `HealthKitService` reads body weight from Apple Health
- Supports historical data fetch and real-time observation
- `BodyWeightChartView` displays trends with interactive charts
- Trend analysis: gaining, losing, or stable

### Progressive Overload Analytics
- `AnalyticsService` computes trends across all exercises
- `ProgressTrend` enum: increasing (>2.5%), plateau, decreasing, insufficient
- `VolumeTrend` tracks week-over-week volume changes
- `ExerciseAnalytics` aggregates E1RM, volume, frequency per exercise
- `AnalyticsDashboardView` shows summary cards and progress breakdown

### AI Weekly Review
- `AICoachService` integrates with Claude API
- `Prompts.weeklyReview()` generates context-aware prompts
- `WeeklyReviewService` aggregates workout data for analysis
- `WeeklyReviewView` displays AI-generated insights
- Mock responses available when API key not configured

### Weight Progression Suggestions
- AI suggests next session's weight/reps based on trends
- `WeightSuggestion` model with confidence levels (high/medium/low)
- `WeightSuggestionCard` displays recommendations in exercise detail view

## Version 1.1 Features (Victory Lap)

### PR Detection System
- Uses **Brzycki formula** for E1RM: `weight × (36 / (37 - reps))`
- Caps effective reps at 12 for formula accuracy
- Detects 4 PR types: `firstTime`, `estimatedMax`, `heaviestWeight`, `repRecord`
- PRDetectionService is an `actor` for thread safety

### Celebration Flow
1. User completes set in `SetInputView`
2. `PRDetectionService.checkForPR()` evaluates against historical PRs
3. If PR detected, saves to database and calls `CelebrationCoordinator.celebrate()`
4. `PRCelebrationView` presents with confetti (ConfettiSwiftUI dependency)
5. User can dismiss or share → `PRShareSheet` generates image card

### Badge System
- 15 badges across 5 categories: Streak, PR, Time, Consistency, Volume
- `StreakService` automatically awards badges when thresholds met
- Badges stored as string IDs in `UserStreak.earnedBadges` (JSON encoded)
- Badge earned dates tracked separately for display

### Rest Timer Logic
- Three default durations: compound (180s), isolation (90s), default (120s)
- `RestTimerService` auto-detects exercise type via keyword matching
- Per-exercise overrides stored in `UserProfile.exerciseRestTimers`
- `RestTimerManager` is `@MainActor` for UI updates

## SwiftData Models

All models use `@Model` macro with `@Attribute(.unique)` for IDs:
- `UserProfile` - Single user, stores preferences
- `UserStreak` - Single per user, tracks all streak/badge data
- `Exercise` - Exercise library (seeded with 40+ defaults)
- `Workout` - Workout sessions with `@Relationship` to exercises
- `WorkoutExercise` - Exercise within workout, has `[SetLog]`
- `SetLog` - Individual set with weight/reps/duration
- `PersonalRecord` - Historical PR records
- `WorkoutPlan` - Custom workout plans (V1.3)
- `PlanDay` - Individual days within a plan (V1.3)
- `PlanExercise` - Exercise templates within a day (V1.3)

## Key Analytics Types (V1.2)

### ProgressTrend
```swift
enum ProgressTrend {
    case increasing(percentage: Double)  // >2.5% improvement
    case plateau(weeks: Int)             // Within ±2.5%
    case decreasing(percentage: Double)  // >2.5% decline
    case insufficient                    // <4 data points
}
```

### ChartTimeRange
```swift
enum ChartTimeRange {
    case oneMonth, threeMonths, sixMonths, oneYear, allTime
}
```

### WeightSuggestion
```swift
struct WeightSuggestion {
    let suggestedWeight: Double
    let suggestedReps: Int
    let confidence: Confidence  // high, medium, low
    let reasoning: String
    let alternativeApproach: String?
}
```

## Dependencies

```swift
// Package.swift
.package(url: "https://github.com/simibac/ConfettiSwiftUI.git", from: "1.1.0")
// Test dependencies
.package(url: "https://github.com/pointfreeco/swift-snapshot-testing.git", from: "1.15.0")
```

## URL Scheme

- `beastmode://import?plan=<base64>` - Import workout plan from deep link
- File extension: `.beastplan` (JSON format)
- UTType: `com.beastmode.plan` (conforms to .json)

## App Groups

- `group.com.beastmode.app` - Used for Watch complication data sharing

## Environment Variables

- `ANTHROPIC_API_KEY` - Optional, enables Claude API for AI coaching features

## Common Patterns

### Environment Objects
- `CelebrationCoordinator` - Injected at app root for global celebration access
- `RestTimerManager` - Created per `SetInputView` instance

### View Modifiers
- `.celebrationOverlay(coordinator:)` - Adds celebration presentation capability

### Color Extension
- `Color(hex:)` initializer for hex color strings (supports RGB, ARGB)

### Actor Pattern
- Services use `actor` for thread-safe data access: `PRDetectionService`, `StreakService`, `AnalyticsService`, `WeeklyReviewService`

## Testing

### Test Framework (V1.3.1)
Uses Swift Testing framework with `@Suite` and `@Test` macros:

```swift
@Suite("PR Detection Service")
struct PRDetectionServiceTests {
    @Test("Detects first-time PR for new exercise")
    @MainActor
    func detectsFirstTimePR() async throws {
        let container = try ModelContainerFactory.makeContainer()
        // ... test code
        #expect(pr == .firstTime)
    }

    @Test("E1RM variations", arguments: [(225.0, 5, true), (200.0, 6, false)])
    @MainActor
    func e1rmVariations(weight: Double, reps: Int, shouldBePR: Bool) async throws {
        // Parameterized test
    }
}
```

### Test Coverage Areas

**Unit Tests** cover:
- E1RM calculation accuracy (Brzycki formula)
- PR detection for all 4 types + edge cases
- Streak calculation (consecutive days, gaps, same-day)
- Badge award logic (no duplicates, threshold checks)
- Rest timer service (compound vs isolation detection)
- Progress/Volume trend calculations
- WorkoutPlan creation and sharing
- ShareablePlan encoding/decoding
- Deep link URL generation and parsing

**Integration Tests** cover:
- Complete workout flow from plan to log to PR
- Multi-week analytics building
- PR detection across workout sessions
- Streak continuation across days
- Plan sharing export/import flow

**Performance Tests** verify:
- Large dataset processing (<2s for 1000 workouts)
- PR history queries (<500ms)
- Batch operations efficiency
- Memory stability

**Snapshot Tests** capture:
- PR celebration badges and modals
- Streak display and badge UI
- Weekly progress indicators

### Running Tests

```bash
# Run all tests
xcodebuild test -scheme BeastMode -destination 'platform=iOS Simulator,name=iPhone 15 Pro'

# Run with CI test plan
xcodebuild test -scheme BeastMode -testPlan BeastMode-CI

# Run nightly (with sanitizers)
xcodebuild test -scheme BeastMode -testPlan BeastMode-Nightly

# Check coverage
python3 scripts/check_coverage.py coverage.json 80.0
```

## Future Development

**Completed in V1.3.1:**
- ✅ Comprehensive test infrastructure with Swift Testing
- ✅ Mock services for isolated testing
- ✅ Snapshot test infrastructure
- ✅ Performance test suite
- ✅ CI/CD with GitHub Actions
- ✅ Xcode test plans

**Still needs attention:**
- Integration tests for HealthKit (requires device/simulator)
- Claude API response parsing edge cases
- Snapshot tests for analytics charts
- UI tests for dashboard navigation
- Push notifications for weekly review availability
- iCloud sync for cross-device data
- Backend support for share codes (requires server)
- Plan versioning and migration
- Watch app independent workout logging
- Widget configurability
- Plan templates marketplace/community sharing
