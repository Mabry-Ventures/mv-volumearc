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
                Section(String(localized: "About You", comment: "Edit profile section header — personal info")) {
                    TextField(
                        String(localized: "Name", comment: "Edit profile name field placeholder"),
                        text: $name
                    )
                    Picker(
                        String(localized: "Experience", comment: "Edit profile experience level picker"),
                        selection: $advancementLevel
                    ) {
                        ForEach(AdvancementLevel.allCases, id: \.self) { level in
                            Text(advancementLevelLabel(level)).tag(level)
                        }
                    }
                }

                Section(String(localized: "Training Schedule", comment: "Edit profile section header — schedule")) {
                    Stepper(
                        String(localized: "Days per week: \(weeklyDays)", comment: "Edit profile days-per-week stepper label"),
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
                        Toggle(equipmentLabel(equipment), isOn: Binding(
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
                            Text(coachingStyleLabel(style)).tag(style)
                        }
                    }
                }

                Section {
                    Picker(
                        String(localized: "Privacy mode", comment: "Edit profile privacy mode picker"),
                        selection: $privacyMode
                    ) {
                        Text(String(localized: "Standard", comment: "Privacy mode — standard")).tag(PrivacyMode.standard)
                        Text(String(localized: "Strict", comment: "Privacy mode — strict")).tag(PrivacyMode.strict)
                    }
                } header: {
                    Text(String(localized: "Privacy", comment: "Edit profile section header — privacy"))
                } footer: {
                    Text(privacyFooter)
                        .font(.caption)
                }
            }
            .navigationTitle(String(localized: "Edit Profile", comment: "Edit profile screen navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "Cancel", comment: "Edit profile cancel button")) {
                        VAHaptics.tap()
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Save", comment: "Edit profile save button")) {
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
            return String(
                localized: "Your name and training history are included in coach prompts for personalized responses.",
                comment: "Edit profile privacy footer — standard mode"
            )
        case .strict:
            return String(
                localized: "Strict mode strips your name and anonymizes history before sending to the AI coach.",
                comment: "Edit profile privacy footer — strict mode"
            )
        }
    }

    private func advancementLevelLabel(_ level: AdvancementLevel) -> String {
        switch level {
        case .beginner: return String(localized: "Beginner", comment: "Advancement level — beginner")
        case .intermediate: return String(localized: "Intermediate", comment: "Advancement level — intermediate")
        case .advanced: return String(localized: "Advanced", comment: "Advancement level — advanced")
        }
    }

    private func coachingStyleLabel(_ style: CoachingStyle) -> String {
        switch style {
        case .motivational: return String(localized: "Motivational", comment: "Coaching style — motivational")
        case .analytical: return String(localized: "Analytical", comment: "Coaching style — analytical")
        case .minimal: return String(localized: "Minimal", comment: "Coaching style — minimal")
        }
    }

    private func equipmentLabel(_ equipment: Equipment) -> String {
        switch equipment {
        case .barbell: return String(localized: "Barbell", comment: "Equipment type — barbell")
        case .dumbbell: return String(localized: "Dumbbell", comment: "Equipment type — dumbbell")
        case .machine: return String(localized: "Machine", comment: "Equipment type — machine")
        case .bodyweight: return String(localized: "Bodyweight", comment: "Equipment type — bodyweight")
        case .cable: return String(localized: "Cable", comment: "Equipment type — cable")
        case .kettlebell: return String(localized: "Kettlebell", comment: "Equipment type — kettlebell")
        case .band: return String(localized: "Resistance band", comment: "Equipment type — band")
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
