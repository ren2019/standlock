import SwiftUI
import StandLockCore

struct WorkModeSettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        SettingsSection {
            SettingsRow(
                "Work schedule mode", symbol: "calendar",
                description: "Flexible work starts after one minute of sustained activity or when you choose Start work."
            ) {
                Picker("Work schedule mode", selection: $coordinator.preferences.workScheduleMode) {
                    Text("Fixed work hours").tag(WorkScheduleMode.fixed)
                    Text("Flexible work").tag(WorkScheduleMode.flexible)
                }
                .labelsHidden()
                .fixedSize()
            }
        }

        if coordinator.preferences.workScheduleMode == .flexible {
            FlexibleWorkForm(
                saved: coordinator.preferences.flexibleWork,
                onSave: { settings in
                    guard coordinator.preferences.flexibleWork != settings else { return }
                    coordinator.preferences.flexibleWork = settings
                    coordinator.savePreferences()
                }
            )
        }
    }
}

private struct FlexibleWorkForm: View {
    let saved: FlexibleWorkSettings
    let onSave: (FlexibleWorkSettings) -> Void

    @State private var draft: ScheduleDraft
    @State private var cap: Int
    @State private var hasCap: Bool

    init(saved: FlexibleWorkSettings, onSave: @escaping (FlexibleWorkSettings) -> Void) {
        self.saved = saved
        self.onSave = onSave
        _draft = State(initialValue: ScheduleDraft(schedule: saved.schedule))
        _cap = State(initialValue: saved.dailyBreakCap ?? 5)
        _hasCap = State(initialValue: saved.dailyBreakCap != nil)
    }

    private var settings: FlexibleWorkSettings {
        FlexibleWorkSettings(rhythm: draft.build(existing: saved.schedule), dailyBreakCap: hasCap ? cap : nil)
    }

    var body: some View {
        Group {
            ScheduleFormView(
                draft: Binding(
                    get: { draft },
                    set: { value in
                        draft = value
                        onSave(settings)
                    }
                ),
                schedule: saved.schedule,
                rhythmOnly: true
            )
            SettingsSection {
                SettingsToggleRow("Daily break limit", symbol: "number", isOn: Binding(
                    get: { hasCap },
                    set: {
                        hasCap = $0
                        onSave(settings)
                    }
                ))
                if hasCap {
                    SettingsRowDivider()
                    SettingsRow("Maximum breaks per day", symbol: "number") {
                        Stepper(value: Binding(
                            get: { cap },
                            set: {
                                cap = $0
                                onSave(settings)
                            }
                        ), in: 1...100) {
                            Text(verbatim: String(cap)).monospacedDigit()
                        }
                        .accessibilityLabel("Maximum breaks per day")
                    }
                }
            }
        }
        .onChange(of: saved) { values in
            guard settings != values else { return }
            draft = ScheduleDraft(schedule: values.schedule)
            cap = values.dailyBreakCap ?? 5
            hasCap = values.dailyBreakCap != nil
        }
    }
}
