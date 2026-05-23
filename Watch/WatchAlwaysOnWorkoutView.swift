import SwiftUI
import VolumeArcCore

struct WatchAlwaysOnWorkoutSnapshot: Codable, Equatable {
    let setLine: String
    let restTimerText: String
    let restAccessibilityLabel: String
    let restAccessibilityValue: String
    let heartRateText: String?
    let interactiveControlsVisible: Bool
    let animationPolicy: String
    let palette: [String]

    static func make(
        autopilot: WorkoutAutopilotState,
        restEndsAt: Date,
        now: Date,
        heartRateBPM: Int?
    ) -> WatchAlwaysOnWorkoutSnapshot {
        let target = autopilot.nextTarget
        let remaining = max(Int(restEndsAt.timeIntervalSince(now)), 0)
        let weight = Int(target.weight)
        let lowerBound = target.repRange.lowerBound
        let upperBound = target.repRange.upperBound

        return WatchAlwaysOnWorkoutSnapshot(
            setLine: String(
                localized: "\(autopilot.nextExerciseName) - \(weight)\(target.unit) x \(lowerBound)-\(upperBound)",
                comment: """
                    Watch AOD current set line; placeholders are exercise \
                    name, weight, unit, lower rep count, upper rep count
                    """
            ),
            restTimerText: remaining == 0
                ? String(localized: "GO", comment: "Watch AOD rest complete short label")
                : String(localized: "\(remaining)s", comment: "Watch AOD rest countdown value"),
            restAccessibilityLabel: remaining == 0
                ? String(localized: "Rest complete", comment: "Watch AOD rest complete accessibility label")
                : String(localized: "Rest timer", comment: "Watch AOD rest timer accessibility label"),
            restAccessibilityValue: Self.restAccessibilityValue(for: remaining),
            heartRateText: heartRateBPM.map { bpm in
                String(
                    localized: "HR \(bpm) bpm",
                    comment: "Watch AOD heart rate label; placeholder is beats per minute"
                )
            },
            interactiveControlsVisible: false,
            animationPolicy: "disabled",
            palette: ["black", "white", "gray", "brandPrimary@0.22"]
        )
    }

    private static func restAccessibilityValue(for remaining: Int) -> String {
        // watchOS 26.5 produced "42 second remaining" from inline inflection here.
        if remaining == 0 {
            return String(localized: "Ready for the next set", comment: "Watch AOD rest complete accessibility value")
        }
        if remaining == 1 {
            return String(localized: "1 second remaining", comment: "Watch AOD singular rest timer accessibility value")
        }
        return String(
            localized: "\(remaining) seconds remaining",
            comment: "Watch AOD plural rest timer accessibility value; placeholder is seconds remaining"
        )
    }
}

struct WatchAlwaysOnWorkoutView: View {
    let autopilot: WorkoutAutopilotState
    let restEndsAt: Date
    let heartRateBPM: Int?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let snapshot = WatchAlwaysOnWorkoutSnapshot.make(
                autopilot: autopilot,
                restEndsAt: restEndsAt,
                now: context.date,
                heartRateBPM: heartRateBPM
            )

            VStack(alignment: .leading, spacing: VA.Space.md) {
                Text(String(localized: "Active set", comment: "Watch AOD current set label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.aodTextSecondary)

                HStack(spacing: VA.Space.sm) {
                    RoundedRectangle(cornerRadius: VA.Radius.sm)
                        .fill(VA.Colors.aodAccent)
                        .frame(width: VA.Space.xxs)
                    Text(snapshot.setLine)
                        .font(VA.Typography.footnote)
                        .lineLimit(1)
                        .minimumScaleFactor(VA.Scale.aodSetLineMinimum)
                        .foregroundStyle(VA.Colors.aodTextPrimary)
                }

                Spacer(minLength: VA.Space.xs)

                Text(snapshot.restTimerText)
                    .font(VA.Typography.aodTimerDisplay)
                    .lineLimit(1)
                    .minimumScaleFactor(VA.Scale.aodTimerMinimum)
                    .foregroundStyle(VA.Colors.aodTextPrimary)
                    .accessibilityLabel(snapshot.restAccessibilityLabel)
                    .accessibilityValue(snapshot.restAccessibilityValue)

                if let heartRateText = snapshot.heartRateText {
                    Text(heartRateText)
                        .font(VA.Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(VA.Colors.aodTextTertiary)
                }
            }
            .padding(VA.Space.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(VA.Colors.aodBackground.ignoresSafeArea())
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}
