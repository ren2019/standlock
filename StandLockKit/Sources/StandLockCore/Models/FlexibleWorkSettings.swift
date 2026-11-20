import Foundation

public enum WorkScheduleMode: String, Codable, Sendable {
    case fixed
    case flexible
}

/// Break rhythm for activity-based work, saved separately from the calendar schedules.
public struct FlexibleWorkSettings: Codable, Equatable, Sendable {
    public static let scheduleID = UUID(uuidString: "92E759FC-6901-4DBD-9957-AB6ADBFC4160")!

    public var breakInterval: TimeInterval
    public var breakDuration: TimeInterval
    public var intervalCycle: [IntervalStep]?
    public var repetitionRule: RepetitionRule?
    public var disciplineLevel: DisciplineLevel
    public var dailyBreakCap: Int?
    public var progressiveEnforcement: Bool

    public init(
        breakInterval: TimeInterval = 40 * 60,
        breakDuration: TimeInterval = 10 * 60,
        intervalCycle: [IntervalStep]? = nil,
        repetitionRule: RepetitionRule? = nil,
        disciplineLevel: DisciplineLevel = .gentle,
        dailyBreakCap: Int? = nil,
        progressiveEnforcement: Bool = false
    ) {
        self.breakInterval = breakInterval
        self.breakDuration = breakDuration
        self.intervalCycle = intervalCycle
        self.repetitionRule = repetitionRule
        self.disciplineLevel = disciplineLevel
        self.dailyBreakCap = dailyBreakCap
        self.progressiveEnforcement = progressiveEnforcement
    }

    public init(rhythm: Schedule, dailyBreakCap: Int?) {
        self.init(
            breakInterval: rhythm.breakInterval, breakDuration: rhythm.breakDuration,
            intervalCycle: rhythm.intervalCycle, repetitionRule: rhythm.repetitionRule,
            disciplineLevel: rhythm.disciplineLevel, dailyBreakCap: dailyBreakCap,
            progressiveEnforcement: rhythm.progressiveEnforcement
        )
    }

    /// Adapts the rhythm to the existing accounting, forms and full-screen break path. The
    /// coordinator measures its interval from activity, without evaluating calendar windows.
    public var schedule: Schedule {
        Schedule(
            id: Self.scheduleID, name: "", days: .everyDay, windows: [],
            breakInterval: breakInterval, breakDuration: breakDuration,
            intervalCycle: intervalCycle, repetitionRule: repetitionRule,
            disciplineLevel: disciplineLevel, dailyBreakCap: dailyBreakCap,
            progressiveEnforcement: progressiveEnforcement
        )
    }
}
