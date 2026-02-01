# Claude.md - Beast Mode Project Documentation

This document provides context for Claude Code sessions working on the Beast Mode workout tracker app.

## Project Overview

Beast Mode is a SwiftUI/SwiftData iOS fitness tracking app focused on strength training. The app emphasizes the emotional experience of hitting personal records (PRs) with celebrations, social sharing, gamification, AI-powered analytics, and custom workout planning.

**Current Version**: 1.3 "Your Split"
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
    ├── AnalyticsTests.swift            # Trend calculations, analytics tests (V1.2)
    ├── PRDetectionTests.swift          # E1RM formula, PR detection edge cases
    ├── RestTimerTests.swift            # Timer service, formatting tests
    ├── StreakTests.swift               # Streak calculation, badge award tests
    └── WorkoutPlanTests.swift          # Plan creation, sharing, import tests (V1.3)
```

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

Unit tests cover:
- E1RM calculation accuracy
- PR detection for all 4 types + edge cases (zero weight/reps)
- Streak calculation (consecutive days, gaps, same-day)
- Badge award logic (no duplicates, threshold checks)
- Rest timer service (compound vs isolation detection)
- Progress trend calculations (V1.2)
- Volume trend calculations (V1.2)
- Weight suggestion JSON decoding (V1.2)
- Analytics overview categorization (V1.2)
- WorkoutPlan creation and properties (V1.3)
- PlanDay weekday names and sorting (V1.3)
- PlanExercise prescription text formatting (V1.3)
- ShareablePlan encoding/decoding (V1.3)
- Plan import/export via PlanSharingService (V1.3)
- Deep link URL generation and parsing (V1.3)
- ComplicationData encoding/decoding (V1.3)

## Future Development

From V1.3 spec, these areas may need attention:
- Integration tests for HealthKit
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
