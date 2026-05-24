#if canImport(SwiftUI) && canImport(AVFoundation) && canImport(Vision) && os(iOS)
import AVFoundation
import ImageIO
import SwiftUI
import Vision
import VolumeArcCore

public struct FormCheckCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller: FormCheckCameraController
    private let exerciseName: String
    private let onComplete: (FormCheckAnalysis) -> Void

    public init(
        exercise: FormCheckExercise,
        exerciseName: String,
        onComplete: @escaping (FormCheckAnalysis) -> Void
    ) {
        _controller = StateObject(wrappedValue: FormCheckCameraController(exercise: exercise))
        self.exerciseName = exerciseName
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            cameraSurface
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: VA.Space.xl)
                bottomPanel
            }
            .padding(VA.Space.lg)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .onAppear {
            controller.prepare()
        }
        .onDisappear {
            controller.stopSession()
        }
        .accessibilityIdentifier("formCheck.root")
    }

    @ViewBuilder
    private var cameraSurface: some View {
        switch controller.authorization {
        case .authorized:
            ZStack {
                CameraPreview(session: controller.session)
                    .ignoresSafeArea()
                FormCheckSkeletonOverlay(frame: controller.latestFrame)
                    .ignoresSafeArea()
            }
        case .denied:
            FormCheckUnavailableView(
                title: String(localized: "Camera blocked", comment: "Form check camera denied title"),
                message: String(
                    localized: "Enable Camera access in Settings to capture a form check.",
                    comment: "Form check camera denied message"
                )
            )
        case .unavailable:
            FormCheckUnavailableView(
                title: String(localized: "Camera unavailable", comment: "Form check no camera title"),
                message: String(
                    localized: "This device cannot start a rear-camera form check.",
                    comment: "Form check no camera message"
                )
            )
        case .notDetermined:
            FormCheckUnavailableView(
                title: String(localized: "Camera access", comment: "Form check camera permission title"),
                message: String(
                    localized: "VolumeArc uses the rear camera for on-device pose analysis only.",
                    comment: "Form check camera permission message"
                )
            )
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                controller.stopCapture()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.42), in: Circle())
            }
            .accessibilityLabel(String(localized: "Close", comment: "Close form check capture"))
            .accessibilityIdentifier("formCheck.close")

            Spacer()

            Text(exerciseName)
                .font(VA.Typography.headline)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, VA.Space.md)
                .frame(height: 38)
                .background(.black.opacity(0.42), in: Capsule())
        }
        .padding(.top, VA.Space.xl)
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: VA.Space.md) {
            HStack(spacing: VA.Space.sm) {
                Image(systemName: controller.isRecording ? "record.circle.fill" : "figure.strengthtraining.traditional")
                    .foregroundStyle(controller.isRecording ? VA.Colors.error : VA.Colors.primary)
                    .font(VA.Typography.headline)
                VStack(alignment: .leading, spacing: VA.Space.xxs) {
                    Text(statusTitle)
                        .font(VA.Typography.headline)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text(statusSubtitle)
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            if let analysis = controller.analysis {
                FormCheckResultSummary(analysis: analysis)
            } else if controller.isRecording {
                recordingMetrics
            } else {
                privacyNote
            }

            controls
        }
        .padding(VA.Space.lg)
        .background(VA.Colors.surfacePrimary.opacity(0.94), in: RoundedRectangle(cornerRadius: VA.Radius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: VA.Radius.lg)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
        }
        .accessibilityIdentifier("formCheck.panel")
    }

    private var recordingMetrics: some View {
        HStack(spacing: VA.Space.md) {
            metric(label: String(localized: "Frames", comment: "Form check captured frames"), value: "\(controller.poseFrameCount)")
            metric(label: String(localized: "Time", comment: "Form check elapsed time"), value: "\(Int(controller.elapsedSeconds))s")
            if controller.isBatteryLow {
                metric(label: String(localized: "Battery", comment: "Form check low battery metric"), value: "<30%")
            }
        }
    }

    private var privacyNote: some View {
        Text(String(
            localized: "Video frames are processed on this device only. No camera frames upload to VolumeArc, Cloudflare, Gemini, Sentry, or iCloud.",
            comment: "Form check capture privacy note"
        ))
        .font(VA.Typography.footnote)
        .foregroundStyle(VA.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var controls: some View {
        HStack(spacing: VA.Space.md) {
            if let analysis = controller.analysis {
                VAButton(
                    String(localized: "Use result", comment: "Accept form check result"),
                    icon: "checkmark",
                    style: .primary,
                    accessibilityIdentifier: "formCheck.useResult"
                ) {
                    VAHaptics.setLogged()
                    onComplete(analysis)
                    dismiss()
                }
                VAButton(
                    String(localized: "Retake", comment: "Retake form check capture"),
                    icon: "arrow.clockwise",
                    style: .secondary,
                    accessibilityIdentifier: "formCheck.retake"
                ) {
                    VAHaptics.tap()
                    controller.resetAnalysis()
                }
            } else if controller.isRecording {
                VAButton(
                    String(localized: "Stop & analyze", comment: "Stop form check capture"),
                    icon: "stop.fill",
                    style: .primary,
                    accessibilityIdentifier: "formCheck.stop"
                ) {
                    VAHaptics.tap()
                    controller.stopCapture()
                }
            } else {
                VAButton(
                    String(localized: "Start capture", comment: "Start form check capture"),
                    icon: "camera.fill",
                    style: .primary,
                    accessibilityIdentifier: "formCheck.start"
                ) {
                    VAHaptics.sessionStart()
                    controller.startCapture()
                }
                .disabled(controller.authorization != .authorized || !controller.isSessionRunning)
            }
        }
    }

    private var statusTitle: String {
        if let analysis = controller.analysis {
            return analysis.verdict.displayName
        }
        if controller.isRecording {
            return String(localized: "Capturing form", comment: "Form check recording status")
        }
        return String(localized: "Form check ready", comment: "Form check ready status")
    }

    private var statusSubtitle: String {
        if let analysis = controller.analysis {
            return analysis.cueText
        }
        if controller.isRecording {
            return String(
                localized: "Keep your full body and bar path in frame.",
                comment: "Form check recording subtitle"
            )
        }
        if controller.isBatteryLow {
            return String(
                localized: "Battery is below 30%; keep the capture short.",
                comment: "Form check low battery warning"
            )
        }
        return String(
            localized: "Set your phone side-on, then capture one set.",
            comment: "Form check ready subtitle"
        )
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: VA.Space.xxs) {
            Text(label)
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textSecondary)
            Text(value)
                .font(VA.Typography.headline)
                .foregroundStyle(VA.Colors.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public enum FormCheckCameraAuthorization: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

public final class FormCheckCameraController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    public let session = AVCaptureSession()
    @Published public private(set) var authorization: FormCheckCameraAuthorization = .notDetermined
    @Published public private(set) var isSessionRunning = false
    @Published public private(set) var isRecording = false
    @Published public private(set) var latestFrame: FormCheckFrame?
    @Published public private(set) var analysis: FormCheckAnalysis?
    @Published public private(set) var poseFrameCount = 0
    @Published public private(set) var elapsedSeconds: TimeInterval = 0
    @Published public private(set) var isBatteryLow = false

    private let exercise: FormCheckExercise
    private let analyzer: FormCheckAnalyzer
    private let sessionQueue = DispatchQueue(label: "com.mabryventures.volumearc.formcheck.session")
    private var configured = false
    private var recordingActive = false
    private var captureStartedAt: Date?
    private var capturedFrames: [FormCheckFrame] = []
    private var autoStopToken = UUID()

    public init(exercise: FormCheckExercise) {
        self.exercise = exercise
        self.analyzer = FormCheckAnalyzer(exercise: exercise)
        super.init()
    }

    public func prepare() {
        refreshBatteryState(enableMonitoring: true)

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorization = .authorized
            configureAndStart()
        case .notDetermined:
            authorization = .notDetermined
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.authorization = granted ? .authorized : .denied
                }
                if granted {
                    self?.configureAndStart()
                }
            }
        case .denied, .restricted:
            authorization = .denied
        @unknown default:
            authorization = .unavailable
        }
    }

    public func startCapture() {
        sessionQueue.async { [weak self] in
            guard let self, configured else { return }
            capturedFrames = []
            captureStartedAt = Date()
            recordingActive = true
            let token = UUID()
            autoStopToken = token
            DispatchQueue.main.async {
                self.analysis = nil
                self.poseFrameCount = 0
                self.elapsedSeconds = 0
                self.isRecording = true
                self.refreshBatteryState()
            }
            sessionQueue.asyncAfter(deadline: .now() + 90) { [weak self] in
                guard let self, self.autoStopToken == token, self.recordingActive else { return }
                self.finishCapture()
            }
        }
    }

    public func stopCapture() {
        sessionQueue.async { [weak self] in
            self?.finishCapture()
        }
    }

    public func resetAnalysis() {
        analysis = nil
        latestFrame = nil
        poseFrameCount = 0
        elapsedSeconds = 0
    }

    public func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            recordingActive = false
            if session.isRunning {
                session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isRecording = false
                self.isSessionRunning = false
            }
        }
    }

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard recordingActive else { return }
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(
            cmSampleBuffer: sampleBuffer,
            orientation: .right,
            options: [:]
        )
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              let frame = VisionPoseFrameAdapter.frame(
                from: observation,
                timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
              ) else {
            return
        }
        capturedFrames.append(frame)
        let elapsed = captureStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        let frameCount = capturedFrames.count
        DispatchQueue.main.async {
            self.latestFrame = frame
            self.poseFrameCount = frameCount
            self.elapsedSeconds = elapsed
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !configured {
                guard configureSession() else {
                    DispatchQueue.main.async {
                        self.authorization = .unavailable
                    }
                    return
                }
                configured = true
            }
            if !session.isRunning {
                session.startRunning()
            }
            let running = session.isRunning
            DispatchQueue.main.async {
                self.isSessionRunning = running
            }
        }
    }

    private func finishCapture() {
        guard recordingActive else { return }
        recordingActive = false
        autoStopToken = UUID()
        let frames = capturedFrames
        let capturedAt = captureStartedAt ?? Date()
        let result = analyzer.analyze(frames: frames, capturedAt: capturedAt)
        DispatchQueue.main.async {
            self.analysis = result
            self.isRecording = false
            self.elapsedSeconds = result.duration
            switch result.verdict {
            case .solid:
                VAHaptics.setLogged()
            case .review:
                VAHaptics.warning()
            case .inconclusive:
                VAHaptics.error()
            }
        }
    }

    private func configureSession() -> Bool {
        session.beginConfiguration()
        session.sessionPreset = .high
        defer {
            session.commitConfiguration()
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return false
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        guard session.canAddOutput(output) else {
            return false
        }
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        session.addOutput(output)
        output.connection(with: .video)?.videoOrientation = .portrait
        return true
    }

    private func refreshBatteryState(enableMonitoring: Bool = false) {
        Task { @MainActor [weak self] in
            if enableMonitoring {
                UIDevice.current.isBatteryMonitoringEnabled = true
            }
            let level = UIDevice.current.batteryLevel
            self?.isBatteryLow = level >= 0 && level < 0.30
        }
    }
}

extension FormCheckCameraController: @unchecked Sendable {}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

private final class PreviewView: UIView {
    override static var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // swiftlint:disable:next force_cast
        layer as! AVCaptureVideoPreviewLayer
    }
}

private struct FormCheckSkeletonOverlay: View {
    let frame: FormCheckFrame?

    var body: some View {
        Canvas { context, size in
            guard let frame else { return }
            for connection in Self.connections {
                guard let start = frame.point(for: connection.0),
                      let end = frame.point(for: connection.1) else {
                    continue
                }
                var path = Path()
                path.move(to: Self.point(start, in: size))
                path.addLine(to: Self.point(end, in: size))
                context.stroke(path, with: .color(.white.opacity(0.72)), lineWidth: 3)
            }
            for point in frame.joints.values where point.confidence >= 0.35 {
                let center = Self.point(point, in: size)
                let rect = CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: rect), with: .color(.white))
            }
        }
        .allowsHitTesting(false)
    }

    private static let connections: [(FormCheckJointName, FormCheckJointName)] = [
        (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    private static func point(_ point: FormCheckPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: (1 - point.y) * size.height)
    }
}

private struct FormCheckResultSummary: View {
    let analysis: FormCheckAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: VA.Space.sm) {
            Text(analysis.summaryLine)
                .font(VA.Typography.body)
                .foregroundStyle(VA.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !analysis.flags.isEmpty {
                Text(analysis.flags.map(\.rawValue).joined(separator: " / "))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("formCheck.result")
    }
}

private struct FormCheckUnavailableView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: VA.Space.md) {
            Image(systemName: "camera.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.84))
            Text(title)
                .font(VA.Typography.title2)
                .foregroundStyle(Color.white)
            Text(message)
                .font(VA.Typography.body)
                .foregroundStyle(Color.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .padding(.horizontal, VA.Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
#endif
