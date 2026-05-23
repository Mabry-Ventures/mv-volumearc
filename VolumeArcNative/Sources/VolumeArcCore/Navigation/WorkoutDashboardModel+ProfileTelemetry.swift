#if canImport(SwiftUI)

extension WorkoutDashboardModel {
    func recordProfilePreferenceTelemetry(
        previousCoachingStyle: CoachingStyle,
        previousPrivacyMode: PrivacyMode,
        defaults: UserProfileDefaults
    ) {
        if previousCoachingStyle != defaults.coachingStyle {
            telemetrySink.record(TelemetryEvent(
                category: "profile",
                name: "coaching_style.changed",
                severity: .info,
                message: "Coaching style changed",
                metadata: [
                    "from": previousCoachingStyle.rawValue,
                    "to": defaults.coachingStyle.rawValue,
                ]
            ))
        }

        if previousPrivacyMode != defaults.privacyMode {
            telemetrySink.record(TelemetryEvent(
                category: "profile",
                name: "privacy_mode.changed",
                severity: .info,
                message: "Privacy mode changed",
                metadata: [
                    "from": previousPrivacyMode.rawValue,
                    "to": defaults.privacyMode.rawValue,
                ]
            ))
        }
    }
}

#endif
