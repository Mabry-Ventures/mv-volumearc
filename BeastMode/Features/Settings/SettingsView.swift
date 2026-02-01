import SwiftUI
import SwiftData

/// Settings view for app configuration
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    @State private var showingHealthPermissions = false
    @State private var showingAbout = false

    var body: some View {
        NavigationStack {
            List {
                // Profile Section
                Section("Profile") {
                    NavigationLink {
                        ProfileEditor()
                    } label: {
                        Label("Edit Profile", systemImage: "person.circle")
                    }
                }

                // Preferences Section
                Section("Preferences") {
                    Picker("Weight Unit", selection: $appState.preferredUnits) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.displayName).tag(unit.rawValue)
                        }
                    }

                    HStack {
                        Text("Default Rest Timer")
                        Spacer()
                        Picker("", selection: $appState.defaultRestTimer) {
                            Text("60s").tag(TimeInterval(60))
                            Text("90s").tag(TimeInterval(90))
                            Text("120s").tag(TimeInterval(120))
                            Text("180s").tag(TimeInterval(180))
                        }
                        .pickerStyle(.menu)
                    }
                }

                // Integrations Section
                Section("Integrations") {
                    Button {
                        showingHealthPermissions = true
                    } label: {
                        Label("Health Permissions", systemImage: "heart.fill")
                    }

                    NavigationLink {
                        WatchSettingsView()
                    } label: {
                        Label("Apple Watch", systemImage: "applewatch")
                    }
                }

                // Data Section
                Section("Data") {
                    NavigationLink {
                        DataManagementView()
                    } label: {
                        Label("Manage Data", systemImage: "externaldrive")
                    }

                    Button {
                        Task {
                            await CloudSyncService.shared.requestSync()
                        }
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                // About Section
                Section("About") {
                    Button {
                        showingAbout = true
                    } label: {
                        Label("About Beast Mode", systemImage: "info.circle")
                    }

                    Link(destination: URL(string: "https://beastmode.app/support")!) {
                        Label("Support", systemImage: "questionmark.circle")
                    }

                    Link(destination: URL(string: "https://beastmode.app/privacy")!) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                }

                // Version
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingHealthPermissions) {
                HealthPermissionsView()
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
        }
    }
}

// MARK: - Profile Editor

struct ProfileEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = "Athlete"
    @State private var preferredUnits = WeightUnit.pounds
    @State private var weekStartsOn = Weekday.monday

    var body: some View {
        Form {
            Section("Display Name") {
                TextField("Name", text: $displayName)
            }

            Section("Preferences") {
                Picker("Weight Unit", selection: $preferredUnits) {
                    ForEach(WeightUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit)
                    }
                }

                Picker("Week Starts On", selection: $weekStartsOn) {
                    ForEach(Weekday.allCases) { day in
                        Text(day.fullName).tag(day)
                    }
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveProfile()
                    dismiss()
                }
            }
        }
        .onAppear {
            loadProfile()
        }
    }

    private func loadProfile() {
        if let profile = try? DataService.shared.getCurrentProfile() {
            displayName = profile.displayName
            preferredUnits = profile.preferredUnits
            weekStartsOn = profile.weekStartsOn
        }
    }

    private func saveProfile() {
        if let profile = try? DataService.shared.getCurrentProfile() {
            profile.displayName = displayName
            profile.preferredUnits = preferredUnits
            profile.weekStartsOn = weekStartsOn
            try? DataService.shared.updateProfile(profile)
        }
    }
}

// MARK: - Health Permissions View

struct HealthPermissionsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isAuthorized = false
    @State private var isRequesting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.pink)

                Text("Health Integration")
                    .font(.beastTitle)

                Text("Beast Mode can save your workouts to Apple Health and read your body weight for tracking.")
                    .font(.beastBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    permissionRow(icon: "figure.strengthtraining.traditional", title: "Save Workouts")
                    permissionRow(icon: "scalemass", title: "Read Body Weight")
                    permissionRow(icon: "heart", title: "Read Heart Rate")
                    permissionRow(icon: "flame", title: "Read Active Calories")
                }
                .padding()
                .glassBackground(cornerRadius: 16)

                if isAuthorized {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    TintedGlassButton("Connect to Health", icon: "heart.fill", tint: .pink) {
                        requestAuthorization()
                    }
                    .disabled(isRequesting)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Health")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func permissionRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.pink)
                .frame(width: 24)
            Text(title)
                .font(.beastBody)
        }
    }

    private func requestAuthorization() {
        isRequesting = true
        Task {
            do {
                try await HealthKitService.shared.requestAuthorization()
                await MainActor.run {
                    isAuthorized = true
                    isRequesting = false
                }
            } catch {
                await MainActor.run {
                    isRequesting = false
                }
            }
        }
    }
}

// MARK: - Watch Settings View

struct WatchSettingsView: View {
    @ObservedObject private var connectivity = WatchConnectivityService.shared

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Watch App Installed")
                    Spacer()
                    if connectivity.isWatchAppInstalled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Not Installed")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("Connection Status")
                    Spacer()
                    if connectivity.isReachable {
                        Text("Connected")
                            .foregroundStyle(.green)
                    } else {
                        Text("Not Reachable")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Sync") {
                Button("Sync Workout Plan") {
                    // Sync action
                }
                .disabled(!connectivity.isReachable)

                Button("Sync Preferences") {
                    // Sync preferences
                }
                .disabled(!connectivity.isReachable)
            }
        }
        .navigationTitle("Apple Watch")
    }
}

// MARK: - Data Management View

struct DataManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingExportSheet = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        List {
            Section("Export") {
                Button("Export All Data") {
                    showingExportSheet = true
                }
            }

            Section("Danger Zone") {
                Button("Delete All Workout Logs", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .navigationTitle("Manage Data")
        .confirmationDialog(
            "Delete All Data?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                // Delete action
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. All your workout logs and PRs will be permanently deleted.")
        }
    }
}

// MARK: - About View

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                BeastModeLogo(size: 120)

                Text("Beast Mode")
                    .font(.beastTitle)

                Text("AI-Powered Progressive Overload Tracker")
                    .font(.beastBody)
                    .foregroundStyle(.secondary)

                Text("Built with SwiftUI for iOS 26")
                    .font(.beastCaption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Text("Made with 💪 by the Beast Mode Team")
                    .font(.beastCaption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
