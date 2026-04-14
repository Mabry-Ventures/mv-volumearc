#if canImport(SwiftUI)
import SwiftUI
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
            Form {
                Section("About You") {
                    TextField("Name", text: $name)
                    Picker("Experience", selection: $advancementLevel) {
                        ForEach(AdvancementLevel.allCases, id: \.self) { level in
                            Text(level.rawValue.capitalized).tag(level)
                        }
                    }
                }

                Section("Training Schedule") {
                    Stepper("Days per week: \(weeklyDays)", value: $weeklyDays, in: 1...7)
                    Picker("Session length", selection: $sessionMinutes) {
                        Text("30 min").tag(30)
                        Text("45 min").tag(45)
                        Text("60 min").tag(60)
                        Text("75 min").tag(75)
                        Text("90 min").tag(90)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Equipment") {
                    ForEach(Equipment.allCases, id: \.self) { equipment in
                        Toggle(equipment.rawValue.capitalized, isOn: Binding(
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

                Section("Coach") {
                    Picker("Coaching style", selection: $coachingStyle) {
                        ForEach(CoachingStyle.allCases, id: \.self) { style in
                            Text(style.rawValue.capitalized).tag(style)
                        }
                    }
                }

                Section {
                    Picker("Privacy mode", selection: $privacyMode) {
                        Text("Standard").tag(PrivacyMode.standard)
                        Text("Strict").tag(PrivacyMode.strict)
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text(privacyFooter)
                        .font(.caption)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        VAHaptics.tap()
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        VAHaptics.setLogged()
                        save()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private var privacyFooter: String {
        switch privacyMode {
        case .standard:
            return "Your name and training history are included in coach prompts for personalized responses."
        case .strict:
            return "Strict mode strips your name and anonymizes history before sending to the AI coach."
        }
    }

    private func save() {
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
