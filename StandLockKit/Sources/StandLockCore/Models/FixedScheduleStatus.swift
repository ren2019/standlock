public enum FixedScheduleStatus {
    case enabled
    case disabled
    case inactive

    public init(schedule: Schedule, mode: WorkScheduleMode) {
        guard mode == .fixed else {
            self = .inactive
            return
        }
        self = schedule.isEnabled ? .enabled : .disabled
    }
}
