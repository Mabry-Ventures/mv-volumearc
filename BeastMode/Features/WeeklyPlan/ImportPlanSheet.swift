// ImportPlanSheet.swift
// BeastMode
// View for importing workout plans

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Sheet for importing a workout plan
struct ImportPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var importMethod: ImportMethod = .file
    @State private var shareCode = ""
    @State private var isImporting = false
    @State private var previewPlan: ShareablePlan?
    @State private var importedPlan: WorkoutPlan?
    @State private var error: Error?
    @State private var showFilePicker = false

    private var userId: UUID? {
        profiles.first?.id
    }

    enum ImportMethod: String, CaseIterable {
        case file = "File"
        case code = "Code"

        var icon: String {
            switch self {
            case .file: return "doc.fill"
            case .code: return "number"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let plan = importedPlan {
                    // Success view
                    successView(plan)
                } else if let preview = previewPlan {
                    // Preview before import
                    previewView(preview)
                } else {
                    // Import options
                    importOptionsView
                }
            }
            .padding()
            .navigationTitle(importedPlan != nil ? "Import Complete" : "Import Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.json, .beastModePlan],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
    }

    // MARK: - Import Options View

    private var importOptionsView: some View {
        VStack(spacing: 24) {
            // Method picker
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.Sharing.importFrom)
                    .font(.headline)

                HStack(spacing: 12) {
                    ForEach(ImportMethod.allCases, id: \.self) { method in
                        ImportMethodButton(
                            method: method,
                            isSelected: importMethod == method
                        ) {
                            importMethod = method
                            error = nil
                        }
                    }
                }
            }

            // Content based on method
            switch importMethod {
            case .file:
                fileImportView
            case .code:
                codeImportView
            }

            if let error {
                errorView(error)
            }

            Spacer()
        }
    }

    private var fileImportView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.arrow.up")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text(L10n.Sharing.importFile)
                .font(.headline)

            Text(L10n.Sharing.selectPlanFile)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showFilePicker = true
            } label: {
                Label("Choose File", systemImage: "folder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.blue)
                    )
                    .foregroundStyle(.white)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private var codeImportView: some View {
        VStack(spacing: 16) {
            Image(systemName: "number.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.purple)

            Text(L10n.Sharing.enterShareCode)
                .font(.headline)

            Text(L10n.Sharing.enterCodeDesc)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("XXXXXXXX", text: $shareCode)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .tracking(4)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.secondary.opacity(0.1))
                )
                .onChange(of: shareCode) { _, newValue in
                    // Limit to 8 characters and uppercase
                    shareCode = String(newValue.uppercased().prefix(8))
                }

            Button {
                importFromCode()
            } label: {
                HStack {
                    if isImporting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(L10n.Sharing.importPlan)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(shareCode.count == 8 ? .purple : .secondary)
                )
                .foregroundStyle(.white)
            }
            .disabled(shareCode.count != 8 || isImporting)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Preview View

    private func previewView(_ plan: ShareablePlan) -> some View {
        VStack(spacing: 20) {
            // Plan info
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.green)

                Text(L10n.Sharing.planFound)
                    .font(.title2.weight(.bold))
            }

            // Plan details card
            VStack(alignment: .leading, spacing: 12) {
                Text(plan.name)
                    .font(.headline)

                if let description = plan.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack(spacing: 20) {
                    VStack(alignment: .leading) {
                        Text(L10n.Plan.daysPerWeek)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(plan.daysPerWeek)")
                            .font(.headline)
                    }

                    VStack(alignment: .leading) {
                        Text(L10n.Plan.difficulty)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(plan.difficulty)
                            .font(.headline)
                    }

                    VStack(alignment: .leading) {
                        Text(L10n.Plan.goal)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(plan.goal)
                            .font(.headline)
                    }
                }

                Divider()

                // Days preview
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.Plan.weeklySchedule)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(plan.days, id: \.weekday) { day in
                        HStack {
                            Text(weekdayName(for: day.weekday))
                                .font(.subheadline)
                                .frame(width: 80, alignment: .leading)

                            Text(day.name)
                                .font(.subheadline)
                                .foregroundStyle(day.isRestDay ? .secondary : .primary)

                            Spacer()

                            if !day.isRestDay {
                                Text("\(day.exercises.count) exercises")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let author = plan.authorName {
                    Divider()

                    HStack {
                        Text(L10n.Sharing.createdBy)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(author)
                            .font(.caption.weight(.semibold))
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )

            Spacer()

            // Import button
            Button {
                confirmImport(plan)
            } label: {
                HStack {
                    if isImporting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(L10n.Sharing.importThisPlan)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: "FF6B35"))
                )
                .foregroundStyle(.white)
            }
            .disabled(isImporting)

            Button("Choose Different Plan") {
                previewPlan = nil
            }
            .font(.subheadline)
        }
    }

    // MARK: - Success View

    private func successView(_ plan: WorkoutPlan) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text(L10n.Sharing.planImported)
                .font(.title.weight(.bold))

            Text("\"\(plan.name)\" has been added to your library")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    // TODO: Navigate to plan editor
                    dismiss()
                } label: {
                    Text(L10n.Plan.viewPlan)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(hex: "FF6B35"))
                        )
                        .foregroundStyle(.white)
                }

                Button("Done") {
                    dismiss()
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: - Error View

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

    // MARK: - Actions

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            isImporting = true
            error = nil

            Task {
                do {
                    // Get security scoped access
                    guard url.startAccessingSecurityScopedResource() else {
                        throw PlanSharingError.invalidFileType
                    }
                    defer { url.stopAccessingSecurityScopedResource() }

                    let data = try Data(contentsOf: url)
                    let service = PlanSharingService(modelContext: modelContext)
                    let preview = try await service.validatePlanData(data)

                    await MainActor.run {
                        previewPlan = preview
                        isImporting = false
                    }
                } catch {
                    await MainActor.run {
                        self.error = error
                        isImporting = false
                    }
                }
            }

        case .failure(let error):
            self.error = error
        }
    }

    private func importFromCode() {
        guard let userId else { return }

        isImporting = true
        error = nil

        Task {
            do {
                let service = PlanSharingService(modelContext: modelContext)
                let plan = try await service.importPlanFromCode(shareCode, userId: userId)

                await MainActor.run {
                    importedPlan = plan
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    isImporting = false
                }
            }
        }
    }

    private func confirmImport(_ preview: ShareablePlan) {
        guard let userId else { return }

        isImporting = true

        let plan = preview.toPlan(userId: userId)
        modelContext.insert(plan)

        importedPlan = plan
        isImporting = false
    }

    private func weekdayName(for weekday: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(weekday: weekday)) ?? .now
        return formatter.string(from: date)
    }
}

// MARK: - Import Method Button

struct ImportMethodButton: View {
    let method: ImportPlanSheet.ImportMethod
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

// MARK: - Deep Link Import View

struct DeepLinkImportView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var previewPlan: ShareablePlan?
    @State private var importedPlan: WorkoutPlan?
    @State private var isLoading = true
    @State private var error: Error?

    private var userId: UUID? {
        profiles.first?.id
    }

    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView("Loading plan...")
                } else if let error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)

                        Text(L10n.Sharing.couldntLoadPlan)
                            .font(.headline)

                        Text(error.localizedDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Try Again") {
                            loadPlan()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                } else if let plan = importedPlan {
                    VStack(spacing: 24) {
                        Spacer()

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(.green)

                        Text(L10n.Sharing.planImported)
                            .font(.title.weight(.bold))

                        Text("\"\(plan.name)\" is ready to use")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Done") {
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Import Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                loadPlan()
            }
        }
    }

    private func loadPlan() {
        guard let userId else {
            error = PlanSharingError.invalidURL
            isLoading = false
            return
        }

        isLoading = true
        error = nil

        Task {
            do {
                let service = PlanSharingService(modelContext: modelContext)
                let plan = try await service.importPlanFromURL(url, userId: userId)

                await MainActor.run {
                    importedPlan = plan
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ImportPlanSheet()
}
