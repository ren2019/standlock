import Foundation

/// The target for a flexible-work break and the rest already credited before it opens.
public struct FlexibleBreakProgress: Sendable {
    public let targetDuration: TimeInterval
    public let creditedDuration: TimeInterval

    public init(targetDuration: TimeInterval, idleCredit: TimeInterval) {
        self.targetDuration = targetDuration
        self.creditedDuration = min(targetDuration, idleCredit)
    }

    public var remainingDuration: TimeInterval { targetDuration - creditedDuration }
}
