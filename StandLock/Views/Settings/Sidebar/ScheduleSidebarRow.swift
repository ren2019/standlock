import SwiftUI
import StandLockCore

struct ScheduleSidebarRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let schedule: Schedule
    let status: FixedScheduleStatus
    let isSelected: Bool

    var body: some View {
        Label {
            HStack {
                Text(verbatim: schedule.name)
                    .lineLimit(1)
                    .foregroundStyle(status == .enabled ? .primary : .secondary)
                Spacer(minLength: 0)
                if status == .enabled {
                    dot(Color(nsColor: .systemGreen))
                }
            }
        } icon: {
            // A fixed hue does not read on the selection fill.
            dot(isSelected ? AnyShapeStyle(.secondary) : AnyShapeStyle(levelColor))
                .frame(width: 20, height: 20)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: schedule.name))
        .accessibilityValue(
            Text(statusLabel)
                + Text(verbatim: ", ")
                + Text(LocalizedStringKey(schedule.disciplineLevel.displayName))
        )
    }

    private var statusLabel: LocalizedStringKey {
        switch status {
        case .enabled: "Enabled"
        case .disabled: "Disabled"
        case .inactive: "Inactive"
        }
    }

    private func dot(_ style: some ShapeStyle) -> some View {
        Circle()
            .fill(style)
            .frame(width: SettingsTokens.statusDotSize, height: SettingsTokens.statusDotSize)
    }

    private var levelColor: Color {
        guard status == .enabled else { return Color(nsColor: .systemGray) }
        // `themeStore.current` is not published, so it would miss a change of appearance.
        let theme = colorScheme == .dark ? AppTheme.dark : AppTheme.light
        return theme.palette(for: schedule.disciplineLevel).accent
    }
}
