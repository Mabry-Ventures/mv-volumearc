#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

#if canImport(ClockKit)
import ClockKit
#endif

public struct WatchFacePackView: View {
    @ObservedObject private var model: WorkoutDashboardModel
    @State private var alert: InstallAlert?
    @State private var installingPreset: WatchFacePreset?

    public init(model: WorkoutDashboardModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: VA.Space.xl) {
                header
                ForEach(WatchFacePreset.allCases) { preset in
                    presetCard(preset)
                }
            }
            .padding(VA.Space.lg)
            .padding(.bottom, VA.Space.xxl)
        }
        .background(VA.Colors.surfaceGrouped)
        .navigationTitle(String(localized: "Watch Faces", comment: "Watch face pack navigation title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("watchFaces.root")
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text(String(localized: "OK", comment: "Default alert dismissal")))
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: VA.Space.sm) {
            Text(String(localized: "VolumeArc Watch Face Pack", comment: "Watch face pack title"))
                .font(VA.Typography.title)
                .foregroundStyle(VA.Colors.textPrimary)
            Text(String(
                localized: "Three designed presets for keeping readiness, the next lift, and streak context on your wrist.",
                comment: "Watch face pack subtitle"
            ))
            .font(VA.Typography.body)
            .foregroundStyle(VA.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, VA.Space.sm)
    }

    private func presetCard(_ preset: WatchFacePreset) -> some View {
        let fileAvailable = WatchFacePack.bundledFileURL(for: preset) != nil
        return VACard(style: .glass) {
            VStack(alignment: .leading, spacing: VA.Space.lg) {
                HStack(alignment: .center, spacing: VA.Space.lg) {
                    WatchFacePreview(preset: preset)
                        .frame(width: 112, height: 132)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: VA.Space.xs) {
                        Text(preset.displayName)
                            .font(VA.Typography.headline)
                            .foregroundStyle(VA.Colors.textPrimary)
                        Text(preset.subtitle)
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(preset.family)
                            .font(VA.Typography.caption)
                            .foregroundStyle(VA.Colors.primary)
                    }
                    Spacer(minLength: VA.Space.sm)
                }

                VStack(spacing: VA.Space.sm) {
                    ForEach(preset.complicationSlots) { slot in
                        HStack(spacing: VA.Space.md) {
                            Text(slot.slot)
                                .font(VA.Typography.caption)
                                .foregroundStyle(VA.Colors.textSecondary)
                                .frame(width: 84, alignment: .leading)
                            VStack(alignment: .leading, spacing: VA.Space.xxs) {
                                Text(slot.label)
                                    .font(VA.Typography.footnote)
                                    .foregroundStyle(VA.Colors.textPrimary)
                                Text(slot.detail)
                                    .font(VA.Typography.caption)
                                    .foregroundStyle(VA.Colors.textSecondary)
                            }
                            Spacer()
                            Text(slot.value)
                                .font(VA.Typography.footnote)
                                .foregroundStyle(VA.Colors.textPrimary)
                        }
                    }
                }

                Button {
                    Task { await install(preset) }
                } label: {
                    HStack {
                        if installingPreset == preset {
                            ProgressView()
                        } else {
                            Image(systemName: fileAvailable ? "applewatch.and.arrow.forward" : "square.and.arrow.down")
                        }
                        Text(fileAvailable
                            ? String(localized: "Install", comment: "Install watch face action")
                            : String(localized: "Export needed", comment: "Missing watch face file action")
                        )
                    }
                    .font(VA.Typography.button)
                    .foregroundStyle(VA.Colors.textOnPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(fileAvailable ? VA.Colors.primary : VA.Colors.textTertiary, in: RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!fileAvailable || installingPreset != nil)
                .accessibilityIdentifier("watchFaces.install.\(preset.telemetryName)")
                .accessibilityHint(fileAvailable
                    ? Text(String(localized: "Opens Apple's Add Watch Face flow", comment: "Watch face install hint"))
                    : Text(String(localized: "The exported watch face file is not bundled yet", comment: "Watch face missing file hint"))
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    @MainActor
    private func install(_ preset: WatchFacePreset) async {
        guard let fileURL = WatchFacePack.bundledFileURL(for: preset) else {
            model.recordWatchFacePackInstallFailed(preset, reason: "file_missing")
            alert = InstallAlert(
                title: String(localized: "Export required", comment: "Watch face missing file alert title"),
                message: String(
                    localized: "The .watchface export for this preset is not bundled yet.",
                    comment: "Watch face missing file alert message"
                )
            )
            return
        }

        installingPreset = preset
        defer { installingPreset = nil }

        #if canImport(ClockKit)
        do {
            try await addWatchFace(at: fileURL)
            model.recordWatchFacePackInstalled(preset)
            alert = InstallAlert(
                title: String(localized: "Ready on Apple Watch", comment: "Watch face success alert title"),
                message: String(
                    localized: "Apple's Watch app will finish adding the face.",
                    comment: "Watch face success alert message"
                )
            )
        } catch {
            model.recordWatchFacePackInstallFailed(preset, reason: String(describing: error))
            alert = InstallAlert(
                title: String(localized: "Could not install", comment: "Watch face install failure alert title"),
                message: error.localizedDescription
            )
        }
        #else
        model.recordWatchFacePackInstallFailed(preset, reason: "clockkit_unavailable")
        alert = InstallAlert(
            title: String(localized: "Apple Watch unavailable", comment: "Watch face ClockKit unavailable title"),
            message: String(
                localized: "This device cannot add Apple Watch faces.",
                comment: "Watch face ClockKit unavailable message"
            )
        )
        #endif
    }

    #if canImport(ClockKit)
    private func addWatchFace(at fileURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            CLKWatchFaceLibrary().addWatchFace(at: fileURL) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    #endif
}

private struct InstallAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct WatchFacePreview: View {
    let preset: WatchFacePreset

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.22, green: 0.22, blue: 0.24), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .overlay(alignment: .trailing) {
                    Capsule()
                        .fill(Color.gray.opacity(0.6))
                        .frame(width: 4, height: 24)
                        .offset(x: 4, y: -18)
                }

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(previewBackground)
                .padding(6)

            previewContent
                .padding(14)
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch preset {
        case .modular:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("9:41")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Spacer()
                    Text("MON")
                        .font(.system(size: 6, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                readinessBlock
                compactRow("Push A", detail: "Bench")
                HStack(spacing: 6) {
                    compactTile("12.4k", label: "Last")
                    compactTile("16", label: "Streak")
                }
            }
        case .infograph:
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 1)
                Circle()
                    .trim(from: 0.55, to: 0.92)
                    .stroke(VA.Colors.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(180))
                Text("9:41")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                corner("82", alignment: .topLeading)
                corner("Push", alignment: .topTrailing)
                corner("12k", alignment: .bottomLeading)
                corner("16", alignment: .bottomTrailing)
            }
        case .photo:
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.12, blue: 0.18),
                        Color(red: 0.08, green: 0.05, blue: 0.04),
                    ],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
                VStack {
                    HStack {
                        cornerLabel("82", label: "Ready")
                        Spacer()
                        cornerLabel("16", label: "Streak")
                    }
                    Spacer()
                    Text("9:41")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                }
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var previewBackground: some ShapeStyle {
        switch preset {
        case .infograph:
            return AnyShapeStyle(Color(red: 0.02, green: 0.02, blue: 0.025))
        case .photo:
            return AnyShapeStyle(Color.black)
        case .modular:
            return AnyShapeStyle(Color.black)
        }
    }

    private var readinessBlock: some View {
        HStack(spacing: 6) {
            Circle()
                .trim(from: 0, to: 0.82)
                .stroke(VA.Colors.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 24, height: 24)
                .rotationEffect(.degrees(-90))
            VStack(alignment: .leading, spacing: 0) {
                Text("82")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("Readiness")
                    .font(.system(size: 6, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
            }
        }
        .padding(7)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func compactRow(_ value: String, detail: String) -> some View {
        HStack {
            Text(value)
                .font(.system(size: 9, weight: .semibold))
            Spacer()
            Text(detail)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
        }
        .padding(6)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func compactTile(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 5, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func corner(_ value: String, alignment: Alignment) -> some View {
        Text(value)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .padding(6)
    }

    private func cornerLabel(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 5, weight: .bold))
                .foregroundStyle(VA.Colors.primary)
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .rounded))
        }
    }
}

#endif
