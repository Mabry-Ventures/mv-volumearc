#if canImport(Combine)

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

    public func recordSubscriptionManageOpened(source: String) {
        telemetrySink.record(TelemetryEvent(
            category: "subscription",
            name: "manage_opened",
            severity: .info,
            message: "Subscription management opened.",
            metadata: [
                "source": source,
            ]
        ))
    }

    public func recordHealthKitUnavailableShown(source: String) {
        telemetrySink.record(TelemetryEvent(
            category: "healthkit",
            name: "unavailable",
            severity: .info,
            message: "Apple Health is not connected on this surface.",
            metadata: [
                "source": source,
            ]
        ))
    }
}

#endif
