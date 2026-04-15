import Foundation

/// Computes a 0-100 readiness score from recent training load, rest, and recovery signals.
///
/// The model uses a weighted composite of five factors, each contributing
/// a signed impact to the baseline score of 85:
/// - Training frequency (sessions in last 7 days)
/// - Rest days since last session
/// - Volume load trend (increasing vs decreasing)
/// - Average RPE trend (grinding sessions indicate accumulated fatigue)
/// - Session duration (long sessions accumulate more fatigue)
public struct ReadinessModel: Sendable {
    public init() {}

    public func evaluate(sessions: [RecentSession], athlete: AthleteProfile) -> ReadinessAssessment {
        let now = Date.now
        let oneWeekAgo = now.addingTimeInterval(-7 * 86_400)
        let recent = sessions.filter { $0.date > oneWeekAgo }

        var factors: [ReadinessAssessment.Factor] = []
        var score = 85  // baseline

        // Factor 1: Training frequency
        let sessionsThisWeek = recent.count
        let idealFrequency = athlete.weeklyTrainingDays
        let frequencyImpact = frequencyScoreImpact(
            sessionsThisWeek: sessionsThisWeek,
            ideal: idealFrequency
        )
        factors.append(.init(
            name: "Training frequency",
            impact: frequencyImpact,
            detail: "\(sessionsThisWeek)/\(idealFrequency) sessions this week"
        ))
        score += frequencyImpact

        // Factor 2: Rest since last session
        let lastSession = sessions.sorted { $0.date > $1.date }.first
        let restImpact = restScoreImpact(lastSession: lastSession, now: now)
        let restDetail: String
        if let lastSession {
            let hours = max(0, Int(now.timeIntervalSince(lastSession.date) / 3600))
            restDetail = hours < 24 ? "\(hours)h since last session" : "\(hours / 24)d since last session"
        } else {
            restDetail = "No recent training"
        }
        factors.append(.init(name: "Recovery", impact: restImpact, detail: restDetail))
        score += restImpact

        // Factor 3: Volume load trend
        let volumeImpact = volumeTrendImpact(sessions: sessions)
        factors.append(.init(
            name: "Volume load",
            impact: volumeImpact,
            detail: volumeImpact < 0 ? "Trending up — fatigue accumulating" : "Managed load"
        ))
        score += volumeImpact

        // Factor 4: Average RPE trend
        let rpeImpact = rpeTrendImpact(sessions: recent)
        factors.append(.init(
            name: "Session intensity",
            impact: rpeImpact,
            detail: averageRPEDetail(sessions: recent)
        ))
        score += rpeImpact

        // Factor 5: Session duration stress
        let durationImpact = durationImpact(sessions: recent)
        factors.append(.init(
            name: "Session duration",
            impact: durationImpact,
            detail: averageDurationDetail(sessions: recent)
        ))
        score += durationImpact

        // Clamp to 0-100
        let clampedScore = max(0, min(100, score))

        return ReadinessAssessment(
            score: clampedScore,
            brief: brief(for: clampedScore),
            factors: factors
        )
    }

    // MARK: - Factor calculations

    private func frequencyScoreImpact(sessionsThisWeek: Int, ideal: Int) -> Int {
        let ratio = Double(sessionsThisWeek) / Double(max(1, ideal))
        switch ratio {
        case ..<0.5: return -8       // Under-trained, slightly lower readiness
        case 0.5..<1.0: return 0     // On track
        case 1.0..<1.25: return -2   // At target
        case 1.25..<1.5: return -6   // Over target
        default: return -12          // Significantly over-trained
        }
    }

    private func restScoreImpact(lastSession: RecentSession?, now: Date) -> Int {
        guard let lastSession else { return 5 } // Fully rested
        let hoursSince = now.timeIntervalSince(lastSession.date) / 3600
        switch hoursSince {
        case ..<12: return -15       // Same-day or overnight
        case 12..<24: return -8      // Yesterday
        case 24..<48: return 3       // Good recovery window
        case 48..<96: return 5       // Well-rested
        case 96..<168: return 0      // Getting detrained
        default: return -5           // Too much rest
        }
    }

    private func volumeTrendImpact(sessions: [RecentSession]) -> Int {
        let sorted = sessions.sorted { $0.date > $1.date }
        guard sorted.count >= 3 else { return 0 }
        let recent = sorted.prefix(3).map(\.totalVolumeLoad)
        let older = sorted.dropFirst(3).prefix(3).map(\.totalVolumeLoad)
        guard !older.isEmpty else { return 0 }

        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let olderAvg = older.reduce(0, +) / Double(older.count)
        guard olderAvg > 0 else { return 0 }

        let change = (recentAvg - olderAvg) / olderAvg
        switch change {
        case ..<(-0.15): return 4    // Deloading, recovering
        case (-0.15)..<0.05: return 0 // Stable
        case 0.05..<0.15: return -3  // Progressive overload
        case 0.15..<0.30: return -6  // Pushing hard
        default: return -10          // Significant overload
        }
    }

    private func rpeTrendImpact(sessions: [RecentSession]) -> Int {
        guard !sessions.isEmpty else { return 0 }
        let avgRPE = sessions.map(\.averageRPE).reduce(0, +) / Double(sessions.count)
        switch avgRPE {
        case ..<6.5: return 4        // Easy sessions
        case 6.5..<7.5: return 0     // Moderate
        case 7.5..<8.5: return -4    // Hard
        case 8.5..<9.5: return -8    // Grinding
        default: return -12          // Maximal effort sessions
        }
    }

    private func durationImpact(sessions: [RecentSession]) -> Int {
        guard !sessions.isEmpty else { return 0 }
        let avgMinutes = Double(sessions.map(\.durationMinutes).reduce(0, +)) / Double(sessions.count)
        switch avgMinutes {
        case ..<45: return 2          // Efficient sessions
        case 45..<75: return 0        // Standard
        case 75..<105: return -3      // Long
        default: return -6            // Marathon sessions
        }
    }

    // MARK: - Text generation

    private func brief(for score: Int) -> String {
        switch score {
        case 90...100: return "Peak readiness. Green light — push if the bar moves well."
        case 75..<90: return "Well recovered. Hit your targets with confidence."
        case 60..<75: return "Moderate fatigue. Stick to the plan, don't chase PRs."
        case 45..<60: return "Accumulating fatigue. Consider an easier day or volume cut."
        case 30..<45: return "Underrecovered. Strong case for a deload session."
        default: return "Recovery-focused day. Skip intensity — move well and rest."
        }
    }

    private func averageRPEDetail(sessions: [RecentSession]) -> String {
        guard !sessions.isEmpty else { return "No recent data" }
        let avg = sessions.map(\.averageRPE).reduce(0, +) / Double(sessions.count)
        return String(format: "Avg RPE %.1f across recent sessions", avg)
    }

    private func averageDurationDetail(sessions: [RecentSession]) -> String {
        guard !sessions.isEmpty else { return "No recent data" }
        let avg = sessions.map(\.durationMinutes).reduce(0, +) / max(1, sessions.count)
        return "\(avg)min average"
    }
}
