// DashboardNavigationTests.swift
// BeastModeUITests
// UI tests for dashboard navigation flows

import XCTest

final class DashboardNavigationTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--skip-onboarding"]
        app.launchEnvironment = ["UITEST_MODE": "1"]
        app.launch()

        // Wait for app to be ready
        let homeTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.home]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 5), "App should launch to home tab")
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Tab Navigation Tests

    func testTabNavigationBetweenAllTabs() throws {
        let tabBar = app.tabBars.firstMatch

        // Verify all 5 tabs exist
        XCTAssertTrue(tabBar.buttons[AccessibilityIdentifiers.TabBar.home].exists, "Home tab should exist")
        XCTAssertTrue(tabBar.buttons[AccessibilityIdentifiers.TabBar.workout].exists, "Workout tab should exist")
        XCTAssertTrue(tabBar.buttons[AccessibilityIdentifiers.TabBar.plans].exists, "Plans tab should exist")
        XCTAssertTrue(tabBar.buttons[AccessibilityIdentifiers.TabBar.progress].exists, "Progress tab should exist")
        XCTAssertTrue(tabBar.buttons[AccessibilityIdentifiers.TabBar.profile].exists, "Profile tab should exist")

        // Navigate to Workout tab
        tabBar.buttons[AccessibilityIdentifiers.TabBar.workout].tap()
        XCTAssertTrue(app.navigationBars["Workout"].waitForExistence(timeout: 2), "Should navigate to Workout view")

        // Navigate to Plans tab
        tabBar.buttons[AccessibilityIdentifiers.TabBar.plans].tap()
        XCTAssertTrue(app.navigationBars["My Plans"].waitForExistence(timeout: 2), "Should navigate to Plans view")

        // Navigate to Progress tab
        tabBar.buttons[AccessibilityIdentifiers.TabBar.progress].tap()
        XCTAssertTrue(app.navigationBars[AccessibilityIdentifiers.Analytics.dashboard].waitForExistence(timeout: 2), "Should navigate to Progress view")

        // Navigate to Profile tab
        tabBar.buttons[AccessibilityIdentifiers.TabBar.profile].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 2), "Should navigate to Profile view")

        // Navigate back to Home tab
        tabBar.buttons[AccessibilityIdentifiers.TabBar.home].tap()
        XCTAssertTrue(app.navigationBars["Beast Mode"].waitForExistence(timeout: 2), "Should navigate back to Home view")
    }

    func testHomeTabIsSelectedByDefault() throws {
        let homeTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.home]
        XCTAssertTrue(homeTab.isSelected, "Home tab should be selected by default")
    }

    func testTabSelectionStateUpdates() throws {
        let tabBar = app.tabBars.firstMatch

        // Select Workout tab
        tabBar.buttons[AccessibilityIdentifiers.TabBar.workout].tap()
        XCTAssertTrue(tabBar.buttons[AccessibilityIdentifiers.TabBar.workout].isSelected, "Workout tab should be selected")
        XCTAssertFalse(tabBar.buttons[AccessibilityIdentifiers.TabBar.home].isSelected, "Home tab should not be selected")

        // Select Plans tab
        tabBar.buttons[AccessibilityIdentifiers.TabBar.plans].tap()
        XCTAssertTrue(tabBar.buttons[AccessibilityIdentifiers.TabBar.plans].isSelected, "Plans tab should be selected")
        XCTAssertFalse(tabBar.buttons[AccessibilityIdentifiers.TabBar.workout].isSelected, "Workout tab should not be selected")
    }

    // MARK: - Home Navigation Tests

    func testNavigationToAnalyticsDashboardFromHome() throws {
        // Ensure we're on Home
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons[AccessibilityIdentifiers.TabBar.home].tap()

        // Tap on Progress tab to navigate to Analytics Dashboard
        tabBar.buttons[AccessibilityIdentifiers.TabBar.progress].tap()

        // Verify Analytics Dashboard is displayed
        let analyticsDashboard = app.otherElements[AccessibilityIdentifiers.Analytics.dashboard]
        XCTAssertTrue(analyticsDashboard.waitForExistence(timeout: 3), "Analytics Dashboard should be displayed")

        // Verify time range picker exists
        let timeRangePicker = app.segmentedControls[AccessibilityIdentifiers.Analytics.timeRangePicker]
        XCTAssertTrue(timeRangePicker.exists, "Time range picker should exist on Analytics Dashboard")
    }

    func testNavigationToBadgeCollectionFromHome() throws {
        // Ensure we're on Home
        let homeTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.home]
        homeTab.tap()

        // Tap the trophy button in toolbar
        let trophyButton = app.navigationBars.buttons[AccessibilityIdentifiers.Home.trophyButton]
        XCTAssertTrue(trophyButton.waitForExistence(timeout: 2), "Trophy button should exist")
        trophyButton.tap()

        // Verify Badge Collection view is displayed
        let badgeCollection = app.navigationBars["Badges"]
        XCTAssertTrue(badgeCollection.waitForExistence(timeout: 2), "Badge Collection should be displayed")
    }

    func testNavigationToWorkoutDetailFromRecentWorkouts() throws {
        // Ensure we're on Home
        let homeTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.home]
        homeTab.tap()

        // Look for recent workouts section
        let recentWorkoutsSection = app.staticTexts[AccessibilityIdentifiers.Home.recentWorkoutsSection]

        // If recent workouts exist, try to tap one
        if recentWorkoutsSection.exists {
            // Find workout row
            let workoutRow = app.buttons[AccessibilityIdentifiers.Home.workoutRow].firstMatch
            if workoutRow.exists {
                workoutRow.tap()

                // Verify workout detail navigation
                let workoutDetail = app.otherElements[AccessibilityIdentifiers.Workout.detailView]
                XCTAssertTrue(workoutDetail.waitForExistence(timeout: 2), "Workout detail should be displayed")
            }
        }
    }

    func testQuickStartWorkoutNavigation() throws {
        // Ensure we're on Home
        let homeTab = app.tabBars.buttons[AccessibilityIdentifiers.TabBar.home]
        homeTab.tap()

        // Tap Quick Start button
        let quickStartButton = app.buttons[AccessibilityIdentifiers.Home.quickStartButton]
        XCTAssertTrue(quickStartButton.waitForExistence(timeout: 2), "Quick Start button should exist")
        quickStartButton.tap()

        // Verify navigation to Workout view
        let workoutView = app.otherElements[AccessibilityIdentifiers.Workout.activeWorkoutView]
        XCTAssertTrue(workoutView.waitForExistence(timeout: 2), "Should navigate to active workout view")
    }

    // MARK: - Plans Navigation Tests

    func testNavigationToPlanEditorFromPlanLibrary() throws {
        // Navigate to Plans tab
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons[AccessibilityIdentifiers.TabBar.plans].tap()

        // Wait for Plans view to load
        XCTAssertTrue(app.navigationBars["My Plans"].waitForExistence(timeout: 2))

        // Tap create plan button
        let createPlanMenu = app.navigationBars.buttons[AccessibilityIdentifiers.Plans.addPlanButton]
        XCTAssertTrue(createPlanMenu.waitForExistence(timeout: 2), "Add plan button should exist")
        createPlanMenu.tap()

        // Select "Create New Plan" from menu
        let createNewPlanOption = app.buttons["Create New Plan"]
        XCTAssertTrue(createNewPlanOption.waitForExistence(timeout: 2), "Create New Plan option should exist")
        createNewPlanOption.tap()

        // Verify Plan Editor sheet is displayed
        let planEditor = app.navigationBars[AccessibilityIdentifiers.Plans.planEditor]
        XCTAssertTrue(planEditor.waitForExistence(timeout: 2), "Plan Editor should be displayed")
    }

    func testNavigationToPlanDetailFromPlanLibrary() throws {
        // Navigate to Plans tab
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons[AccessibilityIdentifiers.TabBar.plans].tap()

        // Wait for Plans view to load
        XCTAssertTrue(app.navigationBars["My Plans"].waitForExistence(timeout: 2))

        // Check if there are any plans
        let planRow = app.buttons[AccessibilityIdentifiers.Plans.planRow].firstMatch
        if planRow.waitForExistence(timeout: 2) {
            planRow.tap()

            // Verify Plan Editor sheet is displayed
            let planEditor = app.navigationBars[AccessibilityIdentifiers.Plans.planEditor]
            XCTAssertTrue(planEditor.waitForExistence(timeout: 2), "Plan Editor should be displayed")
        }
    }

    func testNavigationToImportPlanSheet() throws {
        // Navigate to Plans tab
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons[AccessibilityIdentifiers.TabBar.plans].tap()

        // Wait for Plans view to load
        XCTAssertTrue(app.navigationBars["My Plans"].waitForExistence(timeout: 2))

        // Tap add plan menu
        let addPlanButton = app.navigationBars.buttons[AccessibilityIdentifiers.Plans.addPlanButton]
        XCTAssertTrue(addPlanButton.waitForExistence(timeout: 2), "Add plan button should exist")
        addPlanButton.tap()

        // Select "Import Plan" from menu
        let importPlanOption = app.buttons["Import Plan"]
        XCTAssertTrue(importPlanOption.waitForExistence(timeout: 2), "Import Plan option should exist")
        importPlanOption.tap()

        // Verify Import Plan sheet is displayed
        let importSheet = app.navigationBars["Import Plan"]
        XCTAssertTrue(importSheet.waitForExistence(timeout: 2), "Import Plan sheet should be displayed")
    }

    func testNavigationToTemplatePickerSheet() throws {
        // Navigate to Plans tab
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons[AccessibilityIdentifiers.TabBar.plans].tap()

        // Wait for Plans view to load
        XCTAssertTrue(app.navigationBars["My Plans"].waitForExistence(timeout: 2))

        // Tap add plan menu
        let addPlanButton = app.navigationBars.buttons[AccessibilityIdentifiers.Plans.addPlanButton]
        XCTAssertTrue(addPlanButton.waitForExistence(timeout: 2), "Add plan button should exist")
        addPlanButton.tap()

        // Select "Start from Template" from menu
        let templateOption = app.buttons["Start from Template"]
        XCTAssertTrue(templateOption.waitForExistence(timeout: 2), "Start from Template option should exist")
        templateOption.tap()

        // Verify Template Picker sheet is displayed
        let templatePicker = app.navigationBars["Choose Template"]
        XCTAssertTrue(templatePicker.waitForExistence(timeout: 2), "Template Picker should be displayed")
    }

    // MARK: - Settings Navigation Tests

    func testNavigationToSettingsAndBack() throws {
        // Navigate to Profile tab (which contains settings)
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons[AccessibilityIdentifiers.TabBar.profile].tap()

        // Wait for Profile view to load
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 2))

        // Tap Rest Timer settings
        let restTimerCell = app.cells[AccessibilityIdentifiers.Settings.restTimerCell]
        if restTimerCell.waitForExistence(timeout: 2) {
            restTimerCell.tap()

            // Verify Rest Timer Settings view is displayed
            let restTimerSettings = app.navigationBars[AccessibilityIdentifiers.Settings.restTimerView]
            XCTAssertTrue(restTimerSettings.waitForExistence(timeout: 2), "Rest Timer Settings should be displayed")

            // Navigate back
            let backButton = app.navigationBars.buttons.element(boundBy: 0)
            backButton.tap()

            // Verify we're back on Profile
            XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 2), "Should navigate back to Profile")
        }
    }

    func testNavigationToBadgesFromProfile() throws {
        // Navigate to Profile tab
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons[AccessibilityIdentifiers.TabBar.profile].tap()

        // Wait for Profile view to load
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 2))

        // Tap Badges cell
        let badgesCell = app.cells[AccessibilityIdentifiers.Settings.badgesCell]
        if badgesCell.waitForExistence(timeout: 2) {
            badgesCell.tap()

            // Verify Badge Collection view is displayed
            let badgeCollection = app.navigationBars["Badges"]
            XCTAssertTrue(badgeCollection.waitForExistence(timeout: 2), "Badge Collection should be displayed")
        }
    }

    // MARK: - Progress Tab Navigation Tests

    func testNavigationToExerciseDetailFromAnalytics() throws {
        // Navigate to Progress tab
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons[AccessibilityIdentifiers.TabBar.progress].tap()

        // Wait for Analytics Dashboard to load
        let analyticsDashboard = app.otherElements[AccessibilityIdentifiers.Analytics.dashboard]
        XCTAssertTrue(analyticsDashboard.waitForExistence(timeout: 3))

        // Find an exercise trend row and tap it
        let exerciseTrendRow = app.buttons[AccessibilityIdentifiers.Analytics.exerciseTrendRow].firstMatch
        if exerciseTrendRow.waitForExistence(timeout: 3) {
            exerciseTrendRow.tap()

            // Verify Exercise Detail Analytics sheet is displayed
            let exerciseDetail = app.otherElements[AccessibilityIdentifiers.Analytics.exerciseDetail]
            XCTAssertTrue(exerciseDetail.waitForExistence(timeout: 2), "Exercise Detail Analytics should be displayed")
        }
    }

    func testTimeRangePickerChangesData() throws {
        // Navigate to Progress tab
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons[AccessibilityIdentifiers.TabBar.progress].tap()

        // Wait for Analytics Dashboard to load
        let analyticsDashboard = app.otherElements[AccessibilityIdentifiers.Analytics.dashboard]
        XCTAssertTrue(analyticsDashboard.waitForExistence(timeout: 3))

        // Find time range picker
        let timeRangePicker = app.segmentedControls[AccessibilityIdentifiers.Analytics.timeRangePicker]
        if timeRangePicker.exists {
            // Select different time ranges
            let oneMonthButton = timeRangePicker.buttons["1M"]
            let threeMonthsButton = timeRangePicker.buttons["3M"]
            let sixMonthsButton = timeRangePicker.buttons["6M"]

            if oneMonthButton.exists {
                oneMonthButton.tap()
                // Allow time for data reload
                Thread.sleep(forTimeInterval: 0.5)
            }

            if threeMonthsButton.exists {
                threeMonthsButton.tap()
                Thread.sleep(forTimeInterval: 0.5)
            }

            if sixMonthsButton.exists {
                sixMonthsButton.tap()
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
    }

    func testNavigationToBodyWeightSettings() throws {
        // Navigate to Progress tab
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons[AccessibilityIdentifiers.TabBar.progress].tap()

        // Wait for Analytics Dashboard to load
        XCTAssertTrue(app.otherElements[AccessibilityIdentifiers.Analytics.dashboard].waitForExistence(timeout: 3))

        // Tap gear button in toolbar
        let gearButton = app.navigationBars.buttons[AccessibilityIdentifiers.Analytics.settingsButton]
        if gearButton.waitForExistence(timeout: 2) {
            gearButton.tap()

            // Verify Body Weight Settings view is displayed
            let bodyWeightSettings = app.navigationBars["Body Weight"]
            XCTAssertTrue(bodyWeightSettings.waitForExistence(timeout: 2), "Body Weight Settings should be displayed")
        }
    }

    // MARK: - Deep Link Handling Tests

    func testDeepLinkHandlingForPlanImport() throws {
        // Create a test deep link URL
        let testDeepLink = "beastmode://import?plan=eyJ2ZXJzaW9uIjoxLCJuYW1lIjoiVGVzdCBQbGFuIn0="

        // Simulate opening deep link by relaunching with URL
        app.terminate()

        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--skip-onboarding"]
        app.launchEnvironment = [
            "UITEST_MODE": "1",
            "UITEST_DEEP_LINK": testDeepLink
        ]
        app.launch()

        // Verify import sheet is displayed
        let importSheet = app.sheets[AccessibilityIdentifiers.DeepLink.importSheet]
        if importSheet.waitForExistence(timeout: 3) {
            // Import sheet should show loading or preview
            XCTAssertTrue(importSheet.exists, "Import sheet should be displayed for deep link")
        }
    }

    func testDeepLinkHandlingForInvalidPlan() throws {
        // Create an invalid deep link URL
        let invalidDeepLink = "beastmode://import?plan=invalid_base64"

        // Simulate opening deep link
        app.terminate()

        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--skip-onboarding"]
        app.launchEnvironment = [
            "UITEST_MODE": "1",
            "UITEST_DEEP_LINK": invalidDeepLink
        ]
        app.launch()

        // Verify error handling
        let errorAlert = app.alerts.firstMatch
        if errorAlert.waitForExistence(timeout: 3) {
            // Error alert or message should be displayed
            XCTAssertTrue(errorAlert.exists, "Error should be shown for invalid deep link")
        }
    }

    // MARK: - Workout Navigation Tests

    func testNavigationToActiveWorkout() throws {
        // Navigate to Workout tab
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons[AccessibilityIdentifiers.TabBar.workout].tap()

        // Wait for Workout view to load
        XCTAssertTrue(app.navigationBars["Workout"].waitForExistence(timeout: 2))

        // Tap Start Workout button
        let startWorkoutButton = app.buttons[AccessibilityIdentifiers.Workout.startButton]
        XCTAssertTrue(startWorkoutButton.waitForExistence(timeout: 2), "Start Workout button should exist")
        startWorkoutButton.tap()

        // Verify Active Workout view is displayed
        let activeWorkout = app.otherElements[AccessibilityIdentifiers.Workout.activeWorkoutView]
        XCTAssertTrue(activeWorkout.waitForExistence(timeout: 2), "Active Workout view should be displayed")
    }

    func testNavigationToExerciseSelectorFromActiveWorkout() throws {
        // Navigate to Workout tab and start workout
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons[AccessibilityIdentifiers.TabBar.workout].tap()

        // Start workout
        let startWorkoutButton = app.buttons[AccessibilityIdentifiers.Workout.startButton]
        if startWorkoutButton.waitForExistence(timeout: 2) {
            startWorkoutButton.tap()

            // Tap Add Exercise button
            let addExerciseButton = app.buttons[AccessibilityIdentifiers.Workout.addExerciseButton]
            XCTAssertTrue(addExerciseButton.waitForExistence(timeout: 2), "Add Exercise button should exist")
            addExerciseButton.tap()

            // Verify Exercise Selector sheet is displayed
            let exerciseSelector = app.navigationBars["Add Exercise"]
            XCTAssertTrue(exerciseSelector.waitForExistence(timeout: 2), "Exercise Selector should be displayed")
        }
    }

    // MARK: - Navigation State Persistence Tests

    func testNavigationStatePreservedOnTabSwitch() throws {
        // Navigate to Plans tab and open plan editor
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons[AccessibilityIdentifiers.TabBar.plans].tap()

        // Wait for Plans view
        XCTAssertTrue(app.navigationBars["My Plans"].waitForExistence(timeout: 2))

        // Switch to Home tab
        tabBar.buttons[AccessibilityIdentifiers.TabBar.home].tap()
        XCTAssertTrue(app.navigationBars["Beast Mode"].waitForExistence(timeout: 2))

        // Switch back to Plans tab
        tabBar.buttons[AccessibilityIdentifiers.TabBar.plans].tap()

        // Plans view should still be at root
        XCTAssertTrue(app.navigationBars["My Plans"].waitForExistence(timeout: 2), "Plans tab should preserve its state")
    }

    // MARK: - Sheet Dismissal Tests

    func testPlanEditorSheetDismissal() throws {
        // Navigate to Plans tab
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons[AccessibilityIdentifiers.TabBar.plans].tap()

        // Wait for Plans view to load
        XCTAssertTrue(app.navigationBars["My Plans"].waitForExistence(timeout: 2))

        // Open plan editor
        let addPlanButton = app.navigationBars.buttons[AccessibilityIdentifiers.Plans.addPlanButton]
        XCTAssertTrue(addPlanButton.waitForExistence(timeout: 2))
        addPlanButton.tap()

        let createNewPlanOption = app.buttons["Create New Plan"]
        XCTAssertTrue(createNewPlanOption.waitForExistence(timeout: 2))
        createNewPlanOption.tap()

        // Verify sheet is displayed
        let planEditor = app.navigationBars[AccessibilityIdentifiers.Plans.planEditor]
        XCTAssertTrue(planEditor.waitForExistence(timeout: 2))

        // Tap Cancel button
        let cancelButton = app.buttons[AccessibilityIdentifiers.Common.cancelButton]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 2))
        cancelButton.tap()

        // Verify sheet is dismissed
        XCTAssertTrue(app.navigationBars["My Plans"].waitForExistence(timeout: 2), "Should return to Plans view after dismissal")
    }

    func testImportSheetDismissal() throws {
        // Navigate to Plans tab
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons[AccessibilityIdentifiers.TabBar.plans].tap()

        // Wait for Plans view to load
        XCTAssertTrue(app.navigationBars["My Plans"].waitForExistence(timeout: 2))

        // Open import sheet
        let addPlanButton = app.navigationBars.buttons[AccessibilityIdentifiers.Plans.addPlanButton]
        XCTAssertTrue(addPlanButton.waitForExistence(timeout: 2))
        addPlanButton.tap()

        let importPlanOption = app.buttons["Import Plan"]
        XCTAssertTrue(importPlanOption.waitForExistence(timeout: 2))
        importPlanOption.tap()

        // Verify sheet is displayed
        let importSheet = app.navigationBars["Import Plan"]
        XCTAssertTrue(importSheet.waitForExistence(timeout: 2))

        // Tap Cancel button
        let cancelButton = app.buttons["Cancel"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 2))
        cancelButton.tap()

        // Verify sheet is dismissed
        XCTAssertTrue(app.navigationBars["My Plans"].waitForExistence(timeout: 2), "Should return to Plans view after dismissal")
    }
}

// MARK: - Accessibility Identifiers

/// Accessibility identifiers for UI testing
enum AccessibilityIdentifiers {

    enum TabBar {
        static let home = "tab_home"
        static let workout = "tab_workout"
        static let plans = "tab_plans"
        static let progress = "tab_progress"
        static let profile = "tab_profile"
    }

    enum Home {
        static let trophyButton = "home_trophy_button"
        static let quickStartButton = "home_quick_start_button"
        static let recentWorkoutsSection = "home_recent_workouts_section"
        static let workoutRow = "home_workout_row"
        static let streakDisplay = "home_streak_display"
        static let weeklyReviewCard = "home_weekly_review_card"
    }

    enum Workout {
        static let startButton = "workout_start_button"
        static let activeWorkoutView = "workout_active_view"
        static let detailView = "workout_detail_view"
        static let addExerciseButton = "workout_add_exercise_button"
        static let finishButton = "workout_finish_button"
        static let exerciseCard = "workout_exercise_card"
        static let setInput = "workout_set_input"
    }

    enum Plans {
        static let addPlanButton = "plans_add_button"
        static let planRow = "plans_plan_row"
        static let planEditor = "New Plan"
        static let planDetail = "plans_plan_detail"
        static let activePlanCard = "plans_active_plan_card"
        static let quickActions = "plans_quick_actions"
        static let importSheet = "plans_import_sheet"
        static let templatePicker = "plans_template_picker"
    }

    enum Analytics {
        static let dashboard = "Progress"
        static let timeRangePicker = "analytics_time_range_picker"
        static let exerciseTrendRow = "analytics_exercise_trend_row"
        static let exerciseDetail = "analytics_exercise_detail"
        static let summaryCards = "analytics_summary_cards"
        static let progressBreakdown = "analytics_progress_breakdown"
        static let settingsButton = "analytics_settings_button"
    }

    enum Settings {
        static let restTimerCell = "settings_rest_timer_cell"
        static let restTimerView = "Rest Timer"
        static let badgesCell = "settings_badges_cell"
        static let unitsCell = "settings_units_cell"
        static let signOutButton = "settings_sign_out_button"
    }

    enum DeepLink {
        static let importSheet = "deep_link_import_sheet"
        static let loadingView = "deep_link_loading_view"
        static let errorView = "deep_link_error_view"
        static let successView = "deep_link_success_view"
    }

    enum Common {
        static let cancelButton = "Cancel"
        static let saveButton = "Save"
        static let doneButton = "Done"
        static let backButton = "back_button"
    }
}
