import Testing
import StandLockCore

struct FixedScheduleStatusTests {
    @Test
    func enabledFixedScheduleIsInactiveInFlexibleModeAndResumesInFixedMode() {
        let schedule = workHours(isEnabled: true)

        #expect(FixedScheduleStatus(schedule: schedule, mode: .flexible) == .inactive)
        #expect(FixedScheduleStatus(schedule: schedule, mode: .fixed) == .enabled)
    }

    @Test
    func disabledFixedScheduleIsInactiveInFlexibleModeAndStaysDisabledInFixedMode() {
        let schedule = workHours(isEnabled: false)

        #expect(FixedScheduleStatus(schedule: schedule, mode: .flexible) == .inactive)
        #expect(FixedScheduleStatus(schedule: schedule, mode: .fixed) == .disabled)
    }

    private func workHours(isEnabled: Bool) -> Schedule {
        Schedule(
            name: "Work Hours", isEnabled: isEnabled, days: .weekdays,
            windows: [TimeWindow(startHour: 9, startMinute: 0, endHour: 23, endMinute: 0)],
            breakInterval: 45 * 60, breakDuration: 5 * 60
        )
    }
}
