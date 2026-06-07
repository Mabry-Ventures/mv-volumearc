#if canImport(SwiftUI)
import Foundation
import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif
import VolumeArcCore

/// Editable profile form. Presented as a sheet from ProfileView.
/// Writes changes via the provided save handler.
public struct EditProfileView: View {
    @Binding var isPresented: Bool
    let initialAthlete: AthleteProfile
    let initialCoachingStyle: CoachingStyle
    let onSave: (UserProfileDefaults) -> Void

    @State private var name: String
    @State private var advancementLevel: AdvancementLevel
    @State private var weeklyDays: Int
    @State private var sessionMinutes: Int
    @State private var coachingStyle: CoachingStyle
    @State private var privacyMode: PrivacyMode
    @State private var selectedEquipment: Set<Equipment>
    @AppStorage(ProfileAvatarStorage.storageKey)
    private var persistedAvatarImageData: Data?
    @State private var avatarImageData: Data?
    #if canImport(PhotosUI)
    @State private var selectedAvatarItem: PhotosPickerItem?
    @State private var avatarLoadTask: Task<Void, Never>?
    #endif

    public init(
        isPresented: Binding<Bool>,
        athlete: AthleteProfile,
        coachingStyle: CoachingStyle = .motivational,
        privacyMode: PrivacyMode = .standard,
        sessionMinutes: Int = 60,
        onSave: @escaping (UserProfileDefaults) -> Void
    ) {
        self._isPresented = isPresented
        self.initialAthlete = athlete
        self.initialCoachingStyle = coachingStyle
        self.onSave = onSave
        _name = State(initialValue: athlete.name)
        _advancementLevel = State(initialValue: athlete.advancementLevel)
        _weeklyDays = State(initialValue: athlete.weeklyTrainingDays)
        _sessionMinutes = State(initialValue: sessionMinutes)
        _coachingStyle = State(initialValue: coachingStyle)
        _privacyMode = State(initialValue: privacyMode)
        _selectedEquipment = State(initialValue: athlete.availableEquipment)
    }

    public var body: some View {
        NavigationStack {
            // VOL-200 P4: stable identifier so `profile.edit-profile`
            // journey test can confirm the edit sheet appeared after
            // tapping a row in `ProfileView`.
            Form {
                profilePhotoSection

                Section(String(localized: "About You", comment: "Edit profile section header — personal info")) {
                    TextField(
                        String(localized: "Name", comment: "Edit profile name field placeholder"),
                        text: $name
                    )
                    .accessibilityIdentifier("editProfile.name")
                    Picker(
                        String(localized: "Experience", comment: "Edit profile experience level picker"),
                        selection: $advancementLevel
                    ) {
                        ForEach(AdvancementLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                }

                Section(String(localized: "Training Schedule", comment: "Edit profile section header — schedule")) {
                    Stepper(
                        String(
                            localized: "Days per week: ^[\(weeklyDays) day](inflect: true)",
                            comment: "Edit profile days-per-week stepper label"
                        ),
                        value: $weeklyDays,
                        in: 1...7
                    )
                    Picker(
                        String(localized: "Session length", comment: "Edit profile session length picker"),
                        selection: $sessionMinutes
                    ) {
                        Text(String(localized: "30 min", comment: "Session length option")).tag(30)
                        Text(String(localized: "45 min", comment: "Session length option")).tag(45)
                        Text(String(localized: "60 min", comment: "Session length option")).tag(60)
                        Text(String(localized: "75 min", comment: "Session length option")).tag(75)
                        Text(String(localized: "90 min", comment: "Session length option")).tag(90)
                    }
                    .pickerStyle(.segmented)
                }

                Section(String(localized: "Equipment", comment: "Edit profile section header — available equipment")) {
                    ForEach(Equipment.allCases, id: \.self) { equipment in
                        Toggle(equipment.displayName, isOn: Binding(
                            get: { selectedEquipment.contains(equipment) },
                            set: { isOn in
                                if isOn {
                                    selectedEquipment.insert(equipment)
                                } else {
                                    selectedEquipment.remove(equipment)
                                }
                                VAHaptics.selection()
                            }
                        ))
                    }
                }

                Section(String(localized: "Coach", comment: "Edit profile section header — coaching preferences")) {
                    Picker(
                        String(localized: "Coaching style", comment: "Edit profile coaching style picker"),
                        selection: $coachingStyle
                    ) {
                        ForEach(CoachingStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                }

                Section {
                    Picker(
                        String(localized: "Privacy mode", comment: "Edit profile privacy mode picker"),
                        selection: $privacyMode
                    ) {
                        ForEach(PrivacyMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                } header: {
                    Text(String(localized: "Privacy", comment: "Edit profile section header — privacy"))
                } footer: {
                    Text(privacyMode.footerDescription)
                        .font(.caption)
                }
            }
            .accessibilityIdentifier("editProfile.root")
            .navigationTitle(String(localized: "Edit Profile", comment: "Edit profile screen navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel", comment: "Edit profile cancel button")) {
                        VAHaptics.tap()
                        #if canImport(PhotosUI)
                        avatarLoadTask?.cancel()
                        #endif
                        avatarImageData = persistedAvatarImageData
                        isPresented = false
                    }
                    .accessibilityIdentifier("editProfile.cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Save", comment: "Edit profile save button")) {
                        VAHaptics.setLogged()
                        save()
                    }
                    .fontWeight(.semibold)
                    // VOL-200 P4: stable identifier so the
                    // `profile.edit-profile` journey test can tap
                    // Save and assert the sheet dismisses.
                    .accessibilityIdentifier("editProfile.save")
                }
            }
        }
        .onAppear {
            if avatarImageData == nil {
                avatarImageData = persistedAvatarImageData
            }
        }
        #if canImport(PhotosUI)
        .onDisappear {
            avatarLoadTask?.cancel()
        }
        #endif
    }

    @ViewBuilder
    private var profilePhotoSection: some View {
        Section {
            HStack(spacing: VA.Space.md) {
                ProfileAvatarImage(
                    imageData: avatarImageData,
                    initials: editedInitials,
                    size: 72,
                    foreground: VA.Colors.textOnPrimary,
                    background: VA.Colors.primary
                )
                VStack(alignment: .leading, spacing: VA.Space.xxs) {
                    Text(String(localized: "Profile photo", comment: "Edit profile photo row title"))
                        .font(VA.Typography.body)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text(String(
                        localized: "Used across VolumeArc on this device. Apple sign-in does not provide a profile photo.",
                        comment: "Edit profile photo explanatory copy"
                    ))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("editProfile.avatar.preview")

            #if canImport(PhotosUI)
            PhotosPicker(selection: $selectedAvatarItem, matching: .images, photoLibrary: .shared()) {
                Label {
                    Text(String(localized: "Choose Photo", comment: "Edit profile choose photo action"))
                } icon: {
                    Image(systemName: "photo")
                }
            }
            .accessibilityIdentifier("editProfile.avatar.photoPicker")
            .onChange(of: selectedAvatarItem) { _, newValue in
                avatarLoadTask?.cancel()
                avatarLoadTask = Task {
                    await loadAvatar(from: newValue)
                }
            }
            #endif

            if avatarImageData != nil {
                Button(
                    String(localized: "Remove Photo", comment: "Edit profile remove photo action"),
                    role: .destructive
                ) {
                    avatarImageData = nil
                    #if canImport(PhotosUI)
                    selectedAvatarItem = nil
                    #endif
                    VAHaptics.selection()
                }
                .accessibilityIdentifier("editProfile.avatar.remove")
            }
        } header: {
            Text(String(localized: "Photo", comment: "Edit profile photo section header"))
        }
    }

    private var editedInitials: String {
        AthleteProfile(name: name).initials
    }

    #if canImport(PhotosUI)
    @MainActor
    private func loadAvatar(from item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let normalized = ProfileAvatarStorage.normalizedAvatarData(from: data)
            else {
                VAHaptics.warning()
                return
            }
            guard !Task.isCancelled else { return }
            avatarImageData = normalized
            VAHaptics.setLogged()
        } catch {
            guard !Task.isCancelled else { return }
            VAHaptics.warning()
        }
    }
    #endif

    private func save() {
        persistedAvatarImageData = avatarImageData
        let defaults = UserProfileDefaults(
            name: name,
            coachingStyle: coachingStyle,
            privacyMode: privacyMode,
            advancementLevel: advancementLevel,
            availableEquipment: Array(selectedEquipment),
            preferredRepRangeLower: initialAthlete.preferredRepRange.lowerBound,
            preferredRepRangeUpper: initialAthlete.preferredRepRange.upperBound,
            sessionTimeBudgetMinutes: sessionMinutes,
            weeklyTrainingDays: weeklyDays
        )
        onSave(defaults)
        isPresented = false
    }
}

#endif
