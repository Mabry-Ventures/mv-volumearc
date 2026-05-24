import Foundation

public enum FormCheckExercise: String, Codable, Sendable, CaseIterable, Identifiable {
    case squat
    case benchPress = "bench_press"
    case deadlift

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .squat:
            return String(localized: "Squat", comment: "Form check exercise name — squat")
        case .benchPress:
            return String(localized: "Bench press", comment: "Form check exercise name — bench press")
        case .deadlift:
            return String(localized: "Deadlift", comment: "Form check exercise name — deadlift")
        }
    }

    public static func infer(exerciseID: String, name: String) -> FormCheckExercise? {
        let haystack = "\(exerciseID) \(name)".lowercased()
        if haystack.contains("deadlift") {
            return .deadlift
        }
        if haystack.contains("bench") {
            return .benchPress
        }
        if haystack.contains("squat") {
            return .squat
        }
        return nil
    }

    var movementMode: FormCheckMovementMode {
        switch self {
        case .deadlift:
            return .upThenDown
        case .benchPress, .squat:
            return .downThenUp
        }
    }

    var trackingJoints: [FormCheckJointName] {
        switch self {
        case .squat:
            return [.root, .leftHip, .rightHip]
        case .benchPress, .deadlift:
            return [.leftWrist, .rightWrist]
        }
    }
}

enum FormCheckMovementMode: Sendable {
    case downThenUp
    case upThenDown
}

public enum FormCheckJointName: String, Codable, Sendable, CaseIterable {
    case nose
    case neck
    case root
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftHip
    case rightHip
    case leftKnee
    case rightKnee
    case leftAnkle
    case rightAnkle
}

public struct FormCheckPoint: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let confidence: Double

    public init(x: Double, y: Double, confidence: Double) {
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

public struct FormCheckFrame: Codable, Sendable, Equatable {
    public let timestamp: TimeInterval
    public let joints: [FormCheckJointName: FormCheckPoint]

    public init(timestamp: TimeInterval, joints: [FormCheckJointName: FormCheckPoint]) {
        self.timestamp = timestamp
        self.joints = joints
    }

    public var averageConfidence: Double {
        guard !joints.isEmpty else { return 0 }
        let total = joints.values.reduce(0) { $0 + $1.confidence }
        return total / Double(joints.count)
    }

    public func point(for joint: FormCheckJointName) -> FormCheckPoint? {
        joints[joint]
    }

    func averagedPoint(for candidates: [FormCheckJointName]) -> FormCheckPoint? {
        let points = candidates.compactMap { joints[$0] }
        guard !points.isEmpty else { return nil }
        let confidenceTotal = points.reduce(0) { $0 + max($1.confidence, 0.01) }
        let weightedX = points.reduce(0) { $0 + ($1.x * max($1.confidence, 0.01)) } / confidenceTotal
        let weightedY = points.reduce(0) { $0 + ($1.y * max($1.confidence, 0.01)) } / confidenceTotal
        let confidence = points.reduce(0) { $0 + $1.confidence } / Double(points.count)
        return FormCheckPoint(x: weightedX, y: weightedY, confidence: confidence)
    }
}

public enum FormCheckVerdict: String, Codable, Sendable, CaseIterable {
    case solid
    case review
    case inconclusive

    public var displayName: String {
        switch self {
        case .solid:
            return String(localized: "Solid", comment: "Form check verdict — solid")
        case .review:
            return String(localized: "Review", comment: "Form check verdict — review")
        case .inconclusive:
            return String(localized: "Try again", comment: "Form check verdict — inconclusive")
        }
    }
}

public enum FormCheckHapticCode: String, Codable, Sendable, CaseIterable {
    case solid = "three_taps"
    case review = "five_taps"
    case inconclusive = "single_tap"
}

public enum FormCheckFlag: String, Codable, Sendable, CaseIterable, Comparable {
    case lowConfidence = "low_confidence"
    case insufficientMovement = "insufficient_movement"
    case noRepDetected = "no_rep_detected"
    case shallowDepth = "shallow_depth"
    case unstableBarPath = "unstable_bar_path"
    case rushedTempo = "rushed_tempo"
    case inconsistentDepth = "inconsistent_depth"

    public static func < (lhs: FormCheckFlag, rhs: FormCheckFlag) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var promptLabel: String {
        switch self {
        case .lowConfidence:
            return "pose confidence was low"
        case .insufficientMovement:
            return "movement range was too small to classify"
        case .noRepDetected:
            return "no full rep was detected"
        case .shallowDepth:
            return "range of motion looked shallow"
        case .unstableBarPath:
            return "bar path drifted laterally"
        case .rushedTempo:
            return "tempo was rushed"
        case .inconsistentDepth:
            return "rep depth varied"
        }
    }
}

public struct FormCheckRep: Codable, Sendable, Equatable, Identifiable {
    public var id: Int { index }
    public let index: Int
    public let startedAt: TimeInterval
    public let transitionAt: TimeInterval
    public let endedAt: TimeInterval
    public let eccentricDuration: TimeInterval
    public let concentricDuration: TimeInterval
    public let depth: Double
    public let lateralDrift: Double

    public init(
        index: Int,
        startedAt: TimeInterval,
        transitionAt: TimeInterval,
        endedAt: TimeInterval,
        eccentricDuration: TimeInterval,
        concentricDuration: TimeInterval,
        depth: Double,
        lateralDrift: Double
    ) {
        self.index = index
        self.startedAt = startedAt
        self.transitionAt = transitionAt
        self.endedAt = endedAt
        self.eccentricDuration = eccentricDuration
        self.concentricDuration = concentricDuration
        self.depth = depth
        self.lateralDrift = lateralDrift
    }

    public var totalDuration: TimeInterval {
        endedAt - startedAt
    }
}

public struct FormCheckAnalysis: Codable, Sendable, Equatable {
    public let exercise: FormCheckExercise
    public let capturedAt: Date
    public let duration: TimeInterval
    public let frameCount: Int
    public let poseFrameCount: Int
    public let averageConfidence: Double
    public let reps: [FormCheckRep]
    public let maxLateralDrift: Double
    public let flags: [FormCheckFlag]
    public let verdict: FormCheckVerdict
    public let hapticCode: FormCheckHapticCode
    public let cueText: String

    public init(
        exercise: FormCheckExercise,
        capturedAt: Date,
        duration: TimeInterval,
        frameCount: Int,
        poseFrameCount: Int,
        averageConfidence: Double,
        reps: [FormCheckRep],
        maxLateralDrift: Double,
        flags: [FormCheckFlag],
        verdict: FormCheckVerdict,
        hapticCode: FormCheckHapticCode,
        cueText: String
    ) {
        self.exercise = exercise
        self.capturedAt = capturedAt
        self.duration = duration
        self.frameCount = frameCount
        self.poseFrameCount = poseFrameCount
        self.averageConfidence = averageConfidence
        self.reps = reps
        self.maxLateralDrift = maxLateralDrift
        self.flags = flags.sorted()
        self.verdict = verdict
        self.hapticCode = hapticCode
        self.cueText = cueText
    }

    public var repCount: Int {
        reps.count
    }

    public var averageRepDuration: TimeInterval? {
        guard !reps.isEmpty else { return nil }
        return reps.reduce(0) { $0 + $1.totalDuration } / Double(reps.count)
    }

    public var promptFragment: String {
        var lines = [
            "## Latest form check",
            "- Exercise: \(exercise.displayName)",
            "- Verdict: \(verdict.displayName)",
            "- Reps detected: \(repCount)",
            "- Pose confidence: \(Self.percent(averageConfidence))",
            "- Max lateral drift: \(Self.percent(maxLateralDrift)) of frame width",
        ]
        if let averageRepDuration {
            lines.append("- Average rep tempo: \(String(format: "%.1f", averageRepDuration))s")
        }
        if !flags.isEmpty {
            let flagText = flags.map(\.promptLabel).joined(separator: "; ")
            lines.append("- Flags: \(flagText)")
        }
        lines.append("- Cue: \(cueText)")
        lines.append("- Privacy: video frames were processed on-device; only these derived metrics are in context.")
        return lines.joined(separator: "\n")
    }

    public var summaryLine: String {
        let tempo = averageRepDuration.map { "\(String(format: "%.1f", $0))s avg" } ?? "tempo n/a"
        return "\(exercise.displayName): \(repCount) reps, \(tempo), drift \(Self.percent(maxLateralDrift))"
    }

    private static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

public struct FormCheckAnalyzer: Sendable {
    public let exercise: FormCheckExercise
    public let minimumConfidence: Double
    public let minimumMovementRange: Double
    public let unstableDriftThreshold: Double
    public let minimumPhaseDuration: TimeInterval

    public init(
        exercise: FormCheckExercise,
        minimumConfidence: Double = 0.45,
        minimumMovementRange: Double = 0.10,
        unstableDriftThreshold: Double = 0.16,
        minimumPhaseDuration: TimeInterval = 0.25
    ) {
        self.exercise = exercise
        self.minimumConfidence = minimumConfidence
        self.minimumMovementRange = minimumMovementRange
        self.unstableDriftThreshold = unstableDriftThreshold
        self.minimumPhaseDuration = minimumPhaseDuration
    }

    public func analyze(
        frames rawFrames: [FormCheckFrame],
        capturedAt: Date = Date()
    ) -> FormCheckAnalysis {
        let samples = rawFrames
            .compactMap(makeSample)
            .sorted { $0.timestamp < $1.timestamp }
        let duration = duration(of: rawFrames)
        guard samples.count >= 8 else {
            return buildAnalysis(
                capture: CaptureStats(capturedAt: capturedAt, duration: duration, frameCount: rawFrames.count),
                samples: samples,
                reps: [],
                flags: [.lowConfidence, .noRepDetected],
                maxDrift: 0
            )
        }

        let yValues = samples.map(\.y)
        let movementRange = (yValues.max() ?? 0) - (yValues.min() ?? 0)
        let highThreshold = (yValues.min() ?? 0) + movementRange * 0.72
        let lowThreshold = (yValues.min() ?? 0) + movementRange * 0.28
        let reps = detectReps(
            samples: samples,
            lowThreshold: lowThreshold,
            highThreshold: highThreshold
        )
        let maxDrift = max(reps.map(\.lateralDrift).max() ?? lateralDrift(in: samples), 0)
        let flags = flagsFor(samples: samples, reps: reps, movementRange: movementRange, maxDrift: maxDrift)

        return buildAnalysis(
            capture: CaptureStats(capturedAt: capturedAt, duration: duration, frameCount: rawFrames.count),
            samples: samples,
            reps: reps,
            flags: flags,
            maxDrift: maxDrift
        )
    }

    private func makeSample(from frame: FormCheckFrame) -> TrackedSample? {
        guard let point = frame.averagedPoint(for: exercise.trackingJoints),
              point.confidence >= minimumConfidence else {
            return nil
        }
        return TrackedSample(
            timestamp: frame.timestamp,
            x: point.x,
            y: point.y,
            confidence: point.confidence
        )
    }

    private func detectReps(
        samples: [TrackedSample],
        lowThreshold: Double,
        highThreshold: Double
    ) -> [FormCheckRep] {
        switch exercise.movementMode {
        case .downThenUp:
            return detectDownThenUp(samples: samples, lowThreshold: lowThreshold, highThreshold: highThreshold)
        case .upThenDown:
            return detectUpThenDown(samples: samples, lowThreshold: lowThreshold, highThreshold: highThreshold)
        }
    }

    private func detectDownThenUp(
        samples: [TrackedSample],
        lowThreshold: Double,
        highThreshold: Double
    ) -> [FormCheckRep] {
        var reps: [FormCheckRep] = []
        var readyAtTop = false
        var start: TrackedSample?
        var bottom: TrackedSample?

        for sample in samples {
            if sample.y >= highThreshold {
                readyAtTop = true
            }
            if readyAtTop, start == nil, sample.y < highThreshold {
                start = sample
            }
            if let currentStart = start, bottom == nil, sample.y <= lowThreshold {
                bottom = sample
                start = currentStart
            }
            if let currentStart = start,
               let currentBottom = bottom,
               sample.y >= highThreshold {
                let repSamples = samples.between(currentStart.timestamp, sample.timestamp)
                reps.append(makeRep(
                    index: reps.count + 1,
                    start: currentStart,
                    transition: currentBottom,
                    end: sample,
                    samples: repSamples
                ))
                start = nil
                bottom = nil
                readyAtTop = true
            }
        }
        return reps
    }

    private func detectUpThenDown(
        samples: [TrackedSample],
        lowThreshold: Double,
        highThreshold: Double
    ) -> [FormCheckRep] {
        var reps: [FormCheckRep] = []
        var readyAtBottom = false
        var start: TrackedSample?
        var top: TrackedSample?

        for sample in samples {
            if sample.y <= lowThreshold {
                readyAtBottom = true
            }
            if readyAtBottom, start == nil, sample.y > lowThreshold {
                start = sample
            }
            if let currentStart = start, top == nil, sample.y >= highThreshold {
                top = sample
                start = currentStart
            }
            if let currentStart = start,
               let currentTop = top,
               sample.y <= lowThreshold {
                let repSamples = samples.between(currentStart.timestamp, sample.timestamp)
                reps.append(makeRep(
                    index: reps.count + 1,
                    start: currentStart,
                    transition: currentTop,
                    end: sample,
                    samples: repSamples
                ))
                start = nil
                top = nil
                readyAtBottom = true
            }
        }
        return reps
    }

    private func makeRep(
        index: Int,
        start: TrackedSample,
        transition: TrackedSample,
        end: TrackedSample,
        samples: [TrackedSample]
    ) -> FormCheckRep {
        let firstPhase = transition.timestamp - start.timestamp
        let secondPhase = end.timestamp - transition.timestamp
        let eccentricDuration: TimeInterval
        let concentricDuration: TimeInterval
        switch exercise.movementMode {
        case .downThenUp:
            eccentricDuration = firstPhase
            concentricDuration = secondPhase
        case .upThenDown:
            concentricDuration = firstPhase
            eccentricDuration = secondPhase
        }
        return FormCheckRep(
            index: index,
            startedAt: start.timestamp,
            transitionAt: transition.timestamp,
            endedAt: end.timestamp,
            eccentricDuration: max(0, eccentricDuration),
            concentricDuration: max(0, concentricDuration),
            depth: abs(transition.y - start.y),
            lateralDrift: lateralDrift(in: samples)
        )
    }

    private func flagsFor(
        samples: [TrackedSample],
        reps: [FormCheckRep],
        movementRange: Double,
        maxDrift: Double
    ) -> [FormCheckFlag] {
        var flags = Set<FormCheckFlag>()
        let averageConfidence = samples.reduce(0) { $0 + $1.confidence } / Double(samples.count)
        if averageConfidence < 0.62 {
            flags.insert(.lowConfidence)
        }
        if movementRange < minimumMovementRange {
            flags.insert(.insufficientMovement)
        }
        if reps.isEmpty {
            flags.insert(.noRepDetected)
        }
        if movementRange < 0.16 {
            flags.insert(.shallowDepth)
        }
        if maxDrift > unstableDriftThreshold {
            flags.insert(.unstableBarPath)
        }
        if reps.contains(where: { $0.eccentricDuration < minimumPhaseDuration || $0.concentricDuration < minimumPhaseDuration }) {
            flags.insert(.rushedTempo)
        }
        if reps.count >= 2 {
            let depths = reps.map(\.depth)
            if let minDepth = depths.min(), let maxDepth = depths.max(), maxDepth - minDepth > 0.10 {
                flags.insert(.inconsistentDepth)
            }
        }
        return flags.sorted()
    }

    private func buildAnalysis(
        capture: CaptureStats,
        samples: [TrackedSample],
        reps: [FormCheckRep],
        flags: [FormCheckFlag],
        maxDrift: Double
    ) -> FormCheckAnalysis {
        let averageConfidence = samples.isEmpty
            ? 0
            : samples.reduce(0) { $0 + $1.confidence } / Double(samples.count)
        let verdict = verdict(for: flags, reps: reps)
        return FormCheckAnalysis(
            exercise: exercise,
            capturedAt: capture.capturedAt,
            duration: capture.duration,
            frameCount: capture.frameCount,
            poseFrameCount: samples.count,
            averageConfidence: averageConfidence,
            reps: reps,
            maxLateralDrift: maxDrift,
            flags: flags,
            verdict: verdict,
            hapticCode: hapticCode(for: verdict),
            cueText: cueText(for: verdict, flags: flags, reps: reps)
        )
    }

    private func verdict(for flags: [FormCheckFlag], reps: [FormCheckRep]) -> FormCheckVerdict {
        if reps.isEmpty || flags.contains(.insufficientMovement) || flags.contains(.noRepDetected) {
            return .inconclusive
        }
        let reviewFlags: Set<FormCheckFlag> = [.unstableBarPath, .rushedTempo, .inconsistentDepth, .shallowDepth]
        if flags.contains(where: { reviewFlags.contains($0) }) {
            return .review
        }
        return .solid
    }

    private func hapticCode(for verdict: FormCheckVerdict) -> FormCheckHapticCode {
        switch verdict {
        case .solid:
            return .solid
        case .review:
            return .review
        case .inconclusive:
            return .inconclusive
        }
    }

    private func cueText(
        for verdict: FormCheckVerdict,
        flags: [FormCheckFlag],
        reps: [FormCheckRep]
    ) -> String {
        if flags.contains(.noRepDetected) || reps.isEmpty {
            return "Capture another set from a side angle."
        }
        if flags.contains(.unstableBarPath) {
            return "Keep the bar path stacked and stop the side drift."
        }
        if flags.contains(.rushedTempo) {
            return "Slow the rep and own both phases."
        }
        if flags.contains(.inconsistentDepth) {
            return "Match your depth from rep to rep."
        }
        if flags.contains(.shallowDepth) {
            return "Use a fuller range before adding load."
        }
        switch verdict {
        case .solid:
            return "Form looked steady across the captured reps."
        case .review:
            return "Review the captured set before progressing."
        case .inconclusive:
            return "Capture another set with your full body in frame."
        }
    }

    private func lateralDrift(in samples: [TrackedSample]) -> Double {
        guard let minX = samples.map(\.x).min(), let maxX = samples.map(\.x).max() else {
            return 0
        }
        return maxX - minX
    }

    private func duration(of frames: [FormCheckFrame]) -> TimeInterval {
        let sorted = frames.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first, let last = sorted.last else { return 0 }
        return max(0, last.timestamp - first.timestamp)
    }
}

private struct TrackedSample: Sendable {
    let timestamp: TimeInterval
    let x: Double
    let y: Double
    let confidence: Double
}

private struct CaptureStats: Sendable {
    let capturedAt: Date
    let duration: TimeInterval
    let frameCount: Int
}

private extension Array where Element == TrackedSample {
    func between(_ start: TimeInterval, _ end: TimeInterval) -> [TrackedSample] {
        filter { $0.timestamp >= start && $0.timestamp <= end }
    }
}
