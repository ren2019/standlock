import Foundation

/// The target for a flexible-work break and the rest already credited before it opens.
public struct FlexibleBreakProgress: Sendable {
    public let targetDuration: TimeInterval
    public let creditedDuration: TimeInterval
    public let deadline: Date

    public init(targetDuration: TimeInterval, idleCredit: TimeInterval, startedAt: Date = Date()) {
        self.targetDuration = targetDuration
        let credit = min(targetDuration, idleCredit)
        self.creditedDuration = credit
        self.deadline = startedAt.addingTimeInterval(targetDuration - credit)
    }

    public var remainingDuration: TimeInterval { targetDuration - creditedDuration }
}
