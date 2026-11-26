import SwiftUI
import StandLockCore

struct MenuBarSettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var languageStore: LanguageStore

    /// Fixed sample input, so the preview follows the toggle while paused or with no schedule.
    private var previewTimer: String? {
        formatMenuBarTimer(
            secondsRemaining: 12 * 60,
            showFullTimer: coordinator.preferences.showFullWorkTimer,
            countdownMinutes: coordinator.preferences.menuBarCountdownMinutes,
            isBreakActive: false,
            isPaused: false,
            hasScheduledBreak: true,
            minuteSuffix: languageStore.string("m"),
            hourSuffix: languageStore.string("h")
        )
    }

    private let iconPreviews: [(look: MenuSceneLook, title: LocalizedStringKey)] = [
        (.working, "Working"),
        (.breakSoon, "Break soon"),
        (.timeToStand, "Time to stand"),
        (.paused, "Paused"),
        (.breakWaiting, "Break waiting"),
        (.noSchedules, "No active schedules")
    ]

    var body: some View {
        SettingsPageLayout("Menu Bar") {
            SettingsSection("Preview") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: SettingsTokens.stripItemSpacing) {
                        Image(nsImage: MenuBarIcon.make(progress: 0.5))
                            .renderingMode(.template)
                            .foregroundStyle(.primary)
                            .accessibilityHidden(true)
                        if let previewTimer {
                            Text(previewTimer)
                                .monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(SettingsTokens.stripInsets)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: SettingsTokens.stripRadius))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], spacing: 12) {
                        ForEach(iconPreviews.indices, id: \.self) { index in
                            let preview = iconPreviews[index]
                            HStack(spacing: 8) {
                                Image(nsImage: MenuBarIcon.make(progress: 0.5, look: preview.look))
                                    .renderingMode(.template)
                                    .foregroundStyle(.primary)
                                    .accessibilityHidden(true)
                                Text(preview.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(SettingsTokens.rowInsets)
            }

            SettingsSection("Scene", note: "The picture at the top of the menu bar panel") {
                MenuScenePicker(selection: $coordinator.preferences.menuScene)
            }

            SettingsSection("Timer") {
                SettingsToggleRow(
                    "Show Full Work Timer",
                    symbol: "timer",
                    description: "Shows the time left until the next break next to the menu bar icon all the time. When off, it shows only in the last minutes.",
                    isOn: $coordinator.preferences.showFullWorkTimer
                )

                if !coordinator.preferences.showFullWorkTimer {
                    SettingsRowDivider()
                    SettingsRow("Countdown Start", symbol: "arrow.turn.down.right", description: "How many minutes before a break the time left starts showing next to the icon.") {
                        Picker("Countdown Start", selection: $coordinator.preferences.menuBarCountdownMinutes) {
                            Text("1 min").tag(1)
                            Text("2 min").tag(2)
                            Text("3 min").tag(3)
                            Text("5 min").tag(5)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
            }
        }
    }
}
