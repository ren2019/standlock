import Foundation

/// The local integration format is versioned independently of the app's internal events.
public struct LocalStatusSnapshot: Encodable, Sendable {
    public enum PlanState: String, Encodable, Sendable {
        case work, postponed, deferred, paused, inactive
        case breakActive = "break"
    }

    public let updatedAt: Date
    public let planState: PlanState
    public let nextBreakAt: Date?
    public let inputIdleSeconds: TimeInterval?

    public init(updatedAt: Date, planState: PlanState, nextBreakAt: Date?, inputIdleSeconds: TimeInterval?) {
        self.updatedAt = updatedAt
        self.planState = planState
        self.nextBreakAt = nextBreakAt
        self.inputIdleSeconds = inputIdleSeconds.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, updatedAt, planState, nextBreakAt, inputIdleSeconds
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .schemaVersion)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(planState, forKey: .planState)
        try container.encode(nextBreakAt, forKey: .nextBreakAt)
        try container.encode(inputIdleSeconds, forKey: .inputIdleSeconds)
    }
}
