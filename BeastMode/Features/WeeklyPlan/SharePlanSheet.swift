// SharePlanSheet.swift
// BeastMode
// View for sharing a workout plan

import SwiftUI
import SwiftData

/// Sheet for sharing a workout plan
struct SharePlanSheet: View {
    let plan: WorkoutPlan

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var shareMethod: ShareMethod = .file
    @State private var isGenerating = false
    @State private var shareURL: URL?
    @State private var shareLink: URL?
    @State private var error: Error?
    @State private var showShareSheet = false
    @State private var showCopiedToast = false

    enum ShareMethod: String, CaseIterable {
        case file = "File"
        case link = "Link"
        case code = "Code"

        var icon: String {
            switch self {
            case .file: return "doc.fill"
            case .link: return "link"
            case .code: return "number"
            }
        }

        var description: String {
            switch self {
            case .file: return "Export as .beastplan file"
            case .link: return "Generate shareable link"
            case .code: return "Create share code"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Plan preview
                planPreviewCard

                // Share method picker
                shareMethodPicker

                // Share content based on method
                shareContentView

                Spacer()
            }
            .padding()
            .navigationTitle("Share Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }
            .overlay {
                if showCopiedToast {
                    copiedToast
                }
            }
        }
    }

    // MARK: - Subviews

    private var planPreviewCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: plan.difficulty.color).opacity(0.2))
                    .frame(width: 50, height: 50)

                Image(systemName: plan.targetGoal.icon)
                    .font(.title3)
                    .foregroundStyle(Color(hex: plan.difficulty.color))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(plan.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    Text("\(plan.daysPerWeek) days/week")
                    Text("•")
                    Text("\(plan.totalExercises) exercises")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private var shareMethodPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Share Method")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(ShareMethod.allCases, id: \.self) { method in
                    ShareMethodButton(
                        method: method,
                        isSelected: shareMethod == method
                    ) {
                        shareMethod = method
                        // Reset state when changing methods
                        shareURL = nil
                        shareLink = nil
                        error = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var shareContentView: some View {
        VStack(spacing: 16) {
            switch shareMethod {
            case .file:
                fileShareView
            case .link:
                linkShareView
            case .code:
                codeShareView
            }

            if let error {
                errorView(error)
            }
        }
    }

    private var fileShareView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.arrow.up.fill")
                .font(.system(size: 50))
                .foregroundStyle(.blue)

            Text("Export your plan as a file that can be shared via AirDrop, Messages, or any file sharing app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                exportAsFile()
            } label: {
                HStack {
                    if isGenerating {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text("Export File")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.blue)
                )
            }
            .disabled(isGenerating)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private var linkShareView: some View {
        VStack(spacing: 16) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.green)

            Text("Generate a link that opens directly in Beast Mode when tapped.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let link = shareLink {
                // Link generated
                VStack(spacing: 12) {
                    Text(link.absoluteString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.secondary.opacity(0.1))
                        )

                    HStack(spacing: 12) {
                        Button {
                            copyToClipboard(link.absoluteString)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            shareURL = shareLink
                            showShareSheet = true
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Button {
                    generateLink()
                } label: {
                    HStack {
                        if isGenerating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "link.badge.plus")
                        }
                        Text("Generate Link")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.green)
                    )
                }
                .disabled(isGenerating)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private var codeShareView: some View {
        VStack(spacing: 16) {
            Image(systemName: "number.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.purple)

            Text("Share a simple code that others can enter to import your plan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let code = plan.shareCode {
                // Code exists
                VStack(spacing: 12) {
                    Text(code)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .tracking(4)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.purple.opacity(0.1))
                        )

                    Button {
                        copyToClipboard(code)
                    } label: {
                        Label("Copy Code", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
            } else {
                Button {
                    generateCode()
                } label: {
                    HStack {
                        if isGenerating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "number.square")
                        }
                        Text("Generate Code")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.purple)
                    )
                }
                .disabled(isGenerating)
            }

            Text("Note: Share codes require internet access to import")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private func errorView(_ error: Error) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.orange.opacity(0.1))
        )
    }

    private var copiedToast: some View {
        VStack {
            Spacer()

            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Copied to clipboard")
                    .font(.subheadline)
            }
            .padding()
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            .padding(.bottom, 40)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Actions

    private func exportAsFile() {
        isGenerating = true
        error = nil

        Task {
            do {
                let service = PlanSharingService(modelContext: modelContext)
                let url = try await service.exportPlanToFile(plan)
                await MainActor.run {
                    shareURL = url
                    showShareSheet = true
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    isGenerating = false
                }
            }
        }
    }

    private func generateLink() {
        isGenerating = true
        error = nil

        Task {
            do {
                let service = PlanSharingService(modelContext: modelContext)
                let url = try await service.generateShareLink(plan)
                await MainActor.run {
                    shareLink = url
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    isGenerating = false
                }
            }
        }
    }

    private func generateCode() {
        isGenerating = true
        error = nil

        Task {
            do {
                let service = PlanSharingService(modelContext: modelContext)
                _ = try await service.generateShareCode(for: plan)
                await MainActor.run {
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    isGenerating = false
                }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text

        withAnimation {
            showCopiedToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedToast = false
            }
        }
    }
}

// MARK: - Share Method Button

struct ShareMethodButton: View {
    let method: SharePlanSheet.ShareMethod
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: method.icon)
                    .font(.title2)

                Text(method.rawValue)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color(hex: "FF6B35").opacity(0.2) : .secondary.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color(hex: "FF6B35") : .clear, lineWidth: 2)
            )
            .foregroundStyle(isSelected ? Color(hex: "FF6B35") : .secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    let plan = WorkoutPlan(
        userId: UUID(),
        name: "Push/Pull/Legs",
        description: "Classic 6-day split",
        daysPerWeek: 6
    )

    return SharePlanSheet(plan: plan)
}
