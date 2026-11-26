import Foundation

public enum PausePresentation: Equatable, Sendable {
    public struct MenuBarDisplay: Equatable, Sendable {
        public let countdownSeconds: Int?
        public let iconLook: MenuSceneLook

        public init(countdownSeconds: Int?, iconLook: MenuSceneLook) {
            self.countdownSeconds = countdownSeconds
            self.iconLook = iconLook
        }
    }

    case paused(resumeAt: Date)
    case expired(cueUntil: Date)

    public static let cueDuration: TimeInterval = 10

    public var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }

    public var resumeAt: Date? {
        if case .paused(let resumeAt) = self { return resumeAt }
        return nil
    }

    public func menuBarDisplay(at now: Date, reduceMotion: Bool) -> MenuBarDisplay? {
        switch self {
        case .paused(let resumeAt):
            let remaining = resumeAt.timeIntervalSince(now)
            guard remaining > 0 else { return nil }
            let isCountingDown = remaining <= Self.cueDuration
            return MenuBarDisplay(
                countdownSeconds: isCountingDown ? Int(remaining.rounded(.up)) : nil,
                iconLook: isCountingDown ? iconLook(at: now, cueUntil: resumeAt, reduceMotion: reduceMotion) : .paused
            )
        case .expired(let cueUntil):
            guard cueUntil > now else { return nil }
            return MenuBarDisplay(
                countdownSeconds: nil,
                iconLook: iconLook(at: now, cueUntil: cueUntil, reduceMotion: reduceMotion)
            )
        }
    }

    private func iconLook(at now: Date, cueUntil: Date, reduceMotion: Bool) -> MenuSceneLook {
        guard !reduceMotion else { return .paused }
        let elapsed = now.timeIntervalSince(cueUntil.addingTimeInterval(-Self.cueDuration))
        return Int(elapsed.rounded(.down)) % 2 == 0 ? .paused : .working
    }
}
