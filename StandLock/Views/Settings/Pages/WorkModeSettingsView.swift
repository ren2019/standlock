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
                onSave: { coordinator.preferences.flexibleWork = $0 }
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
            ScheduleFormView(draft: $draft, schedule: saved.schedule, rhythmOnly: true)
            SettingsSection {
                SettingsToggleRow("Daily break limit", symbol: "number", isOn: $hasCap)
                if hasCap {
                    SettingsRowDivider()
                    SettingsRow("Maximum breaks per day", symbol: "number") {
                        Stepper(value: $cap, in: 1...100) {
                            Text(verbatim: String(cap)).monospacedDigit()
                        }
                        .accessibilityLabel("Maximum breaks per day")
                    }
                }
            }
            Button("Save") { onSave(settings) }
                .buttonStyle(.borderedProminent)
                .disabled(settings == saved)
        }
        .onChange(of: saved) { values in
            draft = ScheduleDraft(schedule: values.schedule)
            cap = values.dailyBreakCap ?? 5
            hasCap = values.dailyBreakCap != nil
        }
    }
}
