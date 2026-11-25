import Foundation
import StandLockCore
import Testing
@testable import Coordination

@MainActor
struct FlexibleBreakProgressTests {
    @Test(arguments: [
        (idle: 120.0, enabled: true, remaining: 180.0),
        (idle: 60.0, enabled: true, remaining: 240.0),
        (idle: 59.0, enabled: true, remaining: 300.0),
        (idle: 120.0, enabled: false, remaining: 300.0),
    ])
    func scheduledBreakCountsOnlyEligibleIdleTime(
        idle: TimeInterval, enabled: Bool, remaining: TimeInterval
    ) async throws {
        let locker = MockLocker()
        let detector = MockDetector()
        detector.contextToReturn = DetectionContext(idleDuration: idle)
        let coordinator = BreakCoordinator(scheduler: MockScheduler(), detector: detector, locker: locker)
        defer { coordinator.stop() }
        let preferences = AppPreferences(
            idleDetectionEnabled: enabled,
            workScheduleMode: .flexible,
            flexibleWork: FlexibleWorkSettings(breakInterval: 1800, breakDuration: 300)
        )
        coordinator.start(with: [], preferences: preferences)
        coordinator.startWork(now: Date() - 1800)

        try #require(await waitUntil { locker.isShowing })
        let progress = try #require(locker.lastFlexibleProgress)
        #expect(progress.targetDuration == 300)
        #expect(progress.creditedDuration == 300 - remaining)
        #expect(locker.lastDuration == remaining)
        #expect(locker.lastWaitsForReturn == true)
        #expect(locker.lastCanPostpone == true)
        #expect(coordinator.localStatus().planState == .breakActive)
    }

    @Test
    func longBreakKeepsItsFifteenMinuteTarget() async throws {
        let locker = MockLocker()
        let detector = MockDetector()
        detector.contextToReturn = DetectionContext(idleDuration: 300)
        let coordinator = BreakCoordinator(scheduler: MockScheduler(), detector: detector, locker: locker)
        defer { coordinator.stop() }
        let rhythm = FlexibleWorkSettings(
            breakInterval: 1800, breakDuration: 300,
            repetitionRule: RepetitionRule(shortBreakCount: 3, shortBreakDuration: 300, longBreakDuration: 900)
        )
        coordinator.start(
            with: [], preferences: AppPreferences(workScheduleMode: .flexible, flexibleWork: rhythm),
            restoring: EnforcementState(repetitionIndices: [FlexibleWorkSettings.scheduleID: 3])
        )
        coordinator.startWork(now: Date() - 1800)

        try #require(await waitUntil { locker.isShowing })
        #expect(locker.lastFlexibleProgress?.targetDuration == 900)
        #expect(locker.lastFlexibleProgress?.creditedDuration == 300)
        #expect(locker.lastDuration == 600)
    }

    @Test
    func manuallyStartedBreakBeginsAtZeroProgress() async throws {
        let locker = MockLocker()
        let detector = MockDetector()
        detector.contextToReturn = DetectionContext(idleDuration: 120)
        let coordinator = BreakCoordinator(scheduler: MockScheduler(), detector: detector, locker: locker)
        defer { coordinator.stop() }
        let preferences = AppPreferences(
            breakNowDelaySeconds: 5, workScheduleMode: .flexible,
            flexibleWork: FlexibleWorkSettings(breakInterval: 1800, breakDuration: 300)
        )
        coordinator.start(with: [], preferences: preferences)
        coordinator.startWork()
        coordinator.startBreakNow(now: Date() - 5)

        try #require(await waitUntil { locker.isShowing })
        #expect(locker.lastIsScheduledBreak == true)
        #expect(locker.lastFlexibleProgress?.creditedDuration == 0)
        #expect(locker.lastDuration == 300)
    }

    @Test
    func deadlineSeparatesEarlyExitFromReturnConfirmation() async throws {
        let locker = MockLocker()
        let detector = MockDetector()
        detector.contextToReturn = DetectionContext(idleDuration: 120)
        let coordinator = BreakCoordinator(scheduler: MockScheduler(), detector: detector, locker: locker)
        var completions = 0
        var statistics: BreakStatistics?
        let listener = Task {
            for await event in coordinator.events {
                if case .breakCompleted = event { completions += 1 }
                if case .statisticsUpdated(let stats) = event { statistics = stats }
            }
        }
        defer {
            coordinator.stop()
            listener.cancel()
        }
        let preferences = AppPreferences(
            workScheduleMode: .flexible,
            flexibleWork: FlexibleWorkSettings(breakInterval: 1800, breakDuration: 300, disciplineLevel: .strict)
        )
        coordinator.start(with: [], preferences: preferences)
        coordinator.startWork(now: Date() - 1800)

        try #require(await waitUntil { locker.isShowing })
        let progress = try #require(locker.lastFlexibleProgress)
        coordinator.completeActiveBreak(now: progress.deadline - 1)
        coordinator.skipActiveBreak(now: progress.deadline)
        coordinator.postponeActiveBreak(now: progress.deadline)
        #expect(locker.isShowing)
        #expect(coordinator.localStatus().nextBreakAt == nil)
        #expect(completions == 0)

        let beforeReturn = Date()
        coordinator.completeActiveBreak(now: progress.deadline)
        coordinator.completeActiveBreak(now: progress.deadline)
        let afterReturn = Date()
        let next = try #require(coordinator.localStatus().nextBreakAt)
        #expect((beforeReturn + 1800 ... afterReturn + 1800).contains(next))
        try #require(await waitUntil { statistics?.breaksCompleted == 1 })
        #expect(statistics?.breaksSkipped == 0)
        #expect(completions == 1)
    }
}
