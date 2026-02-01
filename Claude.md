# Claude.md - Beast Mode Project Documentation

This document provides context for Claude Code sessions working on the Beast Mode workout tracker app.

## Project Overview

Beast Mode is a SwiftUI/SwiftData iOS fitness tracking app focused on strength training. The app emphasizes the emotional experience of hitting personal records (PRs) with celebrations, social sharing, and gamification.

**Current Version**: 1.1 "Victory Lap"
**Platform**: iOS 17+, macOS 14+
**Architecture**: SwiftUI + SwiftData + MVVM

## Project Structure

```
BeastMode/
├── App/
│   ├── BeastModeApp.swift      # Main entry point, SwiftData container setup
│   └── ContentView.swift       # Tab navigation, main views
├── Core/
│   ├── Models/
│   │   ├── Exercise.swift      # Exercise definitions, categories, types
│   │   ├── PersonalRecord.swift # PR model with PRType enum
│   │   ├── SetLog.swift        # Individual set tracking
│   │   ├── Streak.swift        # UserStreak model, Badge enum (15 badges)
│   │   ├── UserProfile.swift   # User prefs, rest timer settings
│   │   └── Workout.swift       # Workout + WorkoutExercise models
│   └── Services/
│       ├── PRDetectionService.swift   # PR detection with Brzycki E1RM formula
│       ├── RestTimerService.swift     # Smart rest duration + timer manager
│       └── StreakService.swift        # Streak tracking, badge awards
├── Features/
│   ├── Celebrations/
│   │   └── PRCelebrationView.swift    # Full-screen PR celebration + coordinator
│   ├── Settings/
│   │   └── RestTimerSettingsView.swift # Rest timer customization UI
│   ├── Sharing/
│   │   └── PRShareCardGenerator.swift  # Shareable PR image cards
│   ├── Streaks/
│   │   ├── BadgeDisplayView.swift      # Badge collection + detail views
│   │   └── StreakDisplayView.swift     # Streak flame + weekly progress
│   └── Workout/
│       └── SetInputView.swift          # Set input with PR integration
└── UI/
    └── Components/                      # Reusable UI components
Tests/
└── BeastModeTests/
    ├── PRDetectionTests.swift          # E1RM formula, PR detection edge cases
    ├── RestTimerTests.swift            # Timer service, formatting tests
    └── StreakTests.swift               # Streak calculation, badge award tests
```

## Key Architectural Decisions

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

## Dependencies

```swift
// Package.swift
.package(url: "https://github.com/simibac/ConfettiSwiftUI.git", from: "1.1.0")
```

## Common Patterns

### Environment Objects
- `CelebrationCoordinator` - Injected at app root for global celebration access
- `RestTimerManager` - Created per `SetInputView` instance

### View Modifiers
- `.celebrationOverlay(coordinator:)` - Adds celebration presentation capability

### Color Extension
- `Color(hex:)` initializer for hex color strings (supports RGB, ARGB)

## Testing

Unit tests cover:
- E1RM calculation accuracy
- PR detection for all 4 types + edge cases (zero weight/reps)
- Streak calculation (consecutive days, gaps, same-day)
- Badge award logic (no duplicates, threshold checks)
- Rest timer service (compound vs isolation detection)

## Future Development (Not Yet Implemented)

From V1.1 spec, these areas may need attention:
- Snapshot tests for share cards
- UI tests for celebration flow
- Push notifications for streak reminders
- iCloud sync for cross-device data
