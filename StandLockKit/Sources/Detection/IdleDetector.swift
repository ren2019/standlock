import CoreGraphics
import Foundation

public struct IdleDetector: Sendable {
    public init() {}

    /// Hardware input only. Reading timestamps does not monitor or record individual events.
    public func latestWorkInput(at now: Date = Date()) -> Date? {
        let types: [CGEventType] = [
            .keyDown, .flagsChanged, .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel,
        ]
        let idle = types.map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }.min()
        guard let idle, idle.isFinite, (0...60).contains(idle) else { return nil }
        return now.addingTimeInterval(-idle)
    }

    public func idleDuration() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )
    }
}
