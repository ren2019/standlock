import Foundation
import Testing
@testable import Coordination
import StandLockCore

@Suite("Break now")
@MainActor
struct BreakNowTests {
    @Test
    func earlyBreakTakesThePendingSchedulesSlotOnlyOnce() async throws {
        let scheduler = MockScheduler()
        let locker = MockLocker()
        let detector = MockDetector()
        detector.contextToReturn = DetectionContext(cameraActive: true, idleDuration: 900)
        let coordinator = BreakCoordinator(scheduler: scheduler, detector: detector, locker: locker)
        defer { coordinator.stop() }
        let schedule = makeSchedule(
            level: .firm,
            intervalCycle: [IntervalStep(duration: 60), IntervalStep(duration: 120, label: "Standing")],
            repetitionRule: RepetitionRule(shortBreakCount: 2, shortBreakDuration: 24, longBreakDuration: 90)
        )
        let other = makeSchedule()
        scheduler.nextBreakTimes = [schedule.id: Date() + 0.12, other.id: Date() + 900]
        coordinator.start(with: [other, schedule], preferences: AppPreferences(breakNowDelaySeconds: 1))
        let clicked = Date()
        coordinator.startBreakNow(now: clicked)
        coordinator.startBreakNow(now: clicked + 1)
        #expect(!coordinator.canStartBreakNow)
        #expect(coordinator.localStatus().nextBreakAt == clicked + 1)

        #expect(await waitUntil { locker.isShowing })
        let shownAt = try #require(locker.lastShownAt)
        #expect(shownAt.timeIntervalSince(clicked) >= 0.95)
        #expect(locker.showCount == 1)
        #expect(locker.lastDuration == 24)
        #expect(locker.lastLevel == .firm)
        #expect(locker.lastNextIntervalLabel == "Standing")
        scheduler.nextBreakTimes[schedule.id] = Date() + 600
        coordinator.completeActiveBreak()
        coordinator.completeActiveBreak()
        let state = coordinator.captureEnforcementState()
        #expect(state.dailyBreakCounts[schedule.id] == 1)
        #expect(state.dailyBreakCounts[other.id] == nil)
        #expect(state.cycleIndices[schedule.id] == 1)
        #expect(state.repetitionIndices[schedule.id] == 1)
    }

    @Test
    func pausingCancelsTheBufferRatherThanRearmingItsDate() async {
        let scheduler = MockScheduler()
        let locker = MockLocker()
        let coordinator = BreakCoordinator(scheduler: scheduler, detector: MockDetector(), locker: locker)
        defer { coordinator.stop() }
        scheduler.nextBreakTimeToReturn = Date() + 600
        let schedule = makeSchedule()
        coordinator.start(with: [schedule], preferences: AppPreferences(breakNowDelaySeconds: 1))
        coordinator.startBreakNow()
        #expect(coordinator.captureEnforcementState().pendingBreakDates[schedule.id] == nil)
        coordinator.pause(for: 60)
        coordinator.resume()
        #expect(coordinator.localStatus().nextBreakAt == scheduler.nextBreakTimeToReturn)
        try? await Task.sleep(for: .milliseconds(1100))
        #expect(locker.showCount == 0)
    }
}
