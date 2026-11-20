import Foundation
import Testing
@testable import Coordination
import StandLockCore

@Suite("Flexible work")
@MainActor
struct FlexibleWorkTests {
    @Test
    func activityStartsOneIntervalAndIgnoresFixedHours() {
        let scheduler = MockScheduler()
        let coordinator = BreakCoordinator(scheduler: scheduler, detector: MockDetector(), locker: MockLocker())
        defer { coordinator.stop() }
        let interval: TimeInterval = 40 * 60
        coordinator.start(with: [], preferences: AppPreferences(workScheduleMode: .flexible))
        let first = Date()
        #expect(coordinator.isWaitingForWork)
        coordinator.observeWorkInput(lastInputAt: first, now: first)
        coordinator.observeWorkInput(lastInputAt: first, now: first + 60)
        #expect(coordinator.isWaitingForWork)
        coordinator.observeWorkInput(lastInputAt: first + 45, now: first + 45)
        coordinator.observeWorkInput(lastInputAt: first + 75, now: first + 75)
        coordinator.observeWorkInput(lastInputAt: first + 90, now: first + 90)
        #expect(coordinator.isWaitingForWork)
        coordinator.observeWorkInput(lastInputAt: first + 90, now: first + 105)
        coordinator.startWork(now: first + 106) // A simultaneous menu click cannot reset the slot.
        #expect(!coordinator.isWaitingForWork)
        let status = coordinator.localStatus(now: first + 105)
        #expect(status.planState == .work)
        #expect(status.nextBreakAt == first + 105 + interval)
        #expect(scheduler.receivedAfterDates.isEmpty)
    }

    @Test
    func oldInputCannotStartWorkAfterAwakeningResumeOrPomodoro() {
        let coordinator = BreakCoordinator(scheduler: MockScheduler(), detector: MockDetector(), locker: MockLocker())
        defer { coordinator.stop() }
        coordinator.start(with: [], preferences: AppPreferences(workScheduleMode: .flexible))
        coordinator.startWork()
        coordinator.handleSystemSleep()
        #expect(!coordinator.isWaitingForWork)
        coordinator.handleSystemWake()
        #expect(coordinator.isWaitingForWork)
        let now = Date()
        coordinator.observeWorkInput(lastInputAt: now - 5, now: now)
        coordinator.observeWorkInput(lastInputAt: now + 22, now: now + 22)
        coordinator.observeWorkInput(lastInputAt: now + 50, now: now + 55)
        #expect(coordinator.isWaitingForWork)
        coordinator.pause(for: 600)
        coordinator.startWork()
        #expect(coordinator.localStatus().planState == .paused)
        coordinator.resume()
        #expect(coordinator.isWaitingForWork)
        coordinator.startPomodoro(.standard, level: .gentle)
        #expect(!coordinator.isWaitingForWork)
        coordinator.stopPomodoro()
        #expect(coordinator.isWaitingForWork)
    }

    @Test
    func idleCreditRequiresConfirmationAndStartsNextRhythmStepExactlyOnce() async throws {
        let detector = MockDetector()
        detector.contextToReturn = DetectionContext(idleDuration: 120)
        let locker = MockLocker()
        let coordinator = BreakCoordinator(scheduler: MockScheduler(), detector: detector, locker: locker)
        defer { coordinator.stop() }
        var preferences = AppPreferences(workScheduleMode: .flexible)
        preferences.flexibleWork = FlexibleWorkSettings(
            breakDuration: 10, intervalCycle: [IntervalStep(duration: 60), IntervalStep(duration: 120, label: "Standing")],
            repetitionRule: RepetitionRule(shortBreakCount: 2, shortBreakDuration: 10, longBreakDuration: 90),
            disciplineLevel: .strict
        )
        coordinator.start(with: [], preferences: preferences)
        coordinator.startWork(now: Date() - 60)

        #expect(await waitUntil { locker.isShowing })
        #expect(locker.lastLevel == .strict)
        #expect(locker.lastDuration == 0)
        #expect(locker.lastWaitsForReturn == true)
        #expect(locker.lastNextIntervalLabel == "Standing")
        #expect(locker.lastCanPostpone == false)
        #expect(coordinator.localStatus().planState == .breakActive)
        #expect(coordinator.localStatus().nextBreakAt == nil)
        let id = FlexibleWorkSettings.scheduleID
        #expect(coordinator.captureEnforcementState().repetitionIndices[id] == 0)

        let before = Date()
        coordinator.completeActiveBreak()
        coordinator.completeActiveBreak()
        let status = coordinator.localStatus()
        let next = try #require(status.nextBreakAt)
        #expect(status.planState == .work)
        #expect((120...121).contains(next.timeIntervalSince(before)))
        #expect(coordinator.captureEnforcementState().cycleIndices[id] == 1)
        #expect(coordinator.captureEnforcementState().repetitionIndices[id] == 1)
    }

    @Test
    func modeSwitchKeepsTheActiveBreakButUsesTheNewProfileAfterCompletion() async {
        let scheduler = MockScheduler()
        let locker = MockLocker()
        let coordinator = BreakCoordinator(scheduler: scheduler, detector: MockDetector(), locker: locker)
        defer { coordinator.stop() }
        let fixed = makeSchedule()
        scheduler.nextBreakTimes[fixed.id] = Date() + 600
        var preferences = AppPreferences(workScheduleMode: .flexible)
        preferences.flexibleWork = FlexibleWorkSettings(breakInterval: 60, breakDuration: 30)
        coordinator.start(with: [fixed], preferences: preferences)
        coordinator.startWork(now: Date() - 60)

        #expect(await waitUntil { locker.isShowing })
        preferences.workScheduleMode = .fixed
        coordinator.updatePreferences(preferences)
        #expect(locker.isShowing)
        #expect(locker.lastWaitsForReturn == true)
        #expect(coordinator.localStatus().nextBreakAt == nil)
        coordinator.completeActiveBreak()
        #expect(coordinator.localStatus().nextBreakAt == scheduler.nextBreakTimes[fixed.id])
        coordinator.pause(for: 600)
        preferences.workScheduleMode = .flexible
        coordinator.updatePreferences(preferences)
        #expect(!coordinator.isWaitingForWork)
        #expect(coordinator.localStatus().planState == .paused)
        coordinator.resume()
        #expect(coordinator.isWaitingForWork)
    }

    @Test
    func switchingModesCancelsTheOldPendingBreak() async {
        let fixed = makeSchedule()
        let scheduler = MockScheduler()
        scheduler.nextBreakTimes[fixed.id] = Date() + 0.15
        let locker = MockLocker()
        let coordinator = BreakCoordinator(scheduler: scheduler, detector: MockDetector(), locker: locker)
        defer { coordinator.stop() }
        coordinator.start(with: [fixed], preferences: AppPreferences())
        #expect(coordinator.localStatus().nextBreakAt == scheduler.nextBreakTimes[fixed.id])

        coordinator.updatePreferences(AppPreferences(workScheduleMode: .flexible))
        #expect(coordinator.isWaitingForWork)
        #expect(coordinator.localStatus().nextBreakAt == nil)
        try? await Task.sleep(for: .milliseconds(210))
        #expect(!locker.isShowing)
    }

    @Test
    func relaunchRequiresFreshActivityAndKeepsTheFlexibleDailyCap() {
        let id = FlexibleWorkSettings.scheduleID
        let restored = EnforcementState(dailyBreakCounts: [id: 2], pendingBreakDates: [id: Date() + 90])
        let locker = MockLocker()
        let coordinator = BreakCoordinator(scheduler: MockScheduler(), detector: MockDetector(), locker: locker)
        defer { coordinator.stop() }
        var preferences = AppPreferences(workScheduleMode: .flexible)
        preferences.flexibleWork.dailyBreakCap = 3
        coordinator.start(with: [], preferences: preferences, restoring: restored)
        #expect(coordinator.isWaitingForWork)
        #expect(coordinator.localStatus().nextBreakAt == nil)
        #expect(coordinator.captureEnforcementState().dailyBreakCounts[id] == 2)
    }

    @Test
    func repeatedPostponesConsumeOnlyOneFlexibleBreak() async throws {
        let locker = MockLocker()
        let scheduler = MockScheduler()
        let coordinator = BreakCoordinator(
            scheduler: scheduler, detector: MockDetector(), locker: locker, deferralPollingInterval: 0.01
        )
        defer { coordinator.stop() }
        var preferences = AppPreferences(postponeReturnDelay: 0, workScheduleMode: .flexible)
        preferences.flexibleWork = FlexibleWorkSettings(breakInterval: 60, breakDuration: 10, dailyBreakCap: 1)
        coordinator.start(with: [], preferences: preferences)
        coordinator.startWork(now: Date() - 60)

        try #require(await waitUntil { locker.isShowing })
        coordinator.postponeActiveBreak()
        #expect(coordinator.localStatus().planState == .postponed)
        try #require(await waitUntil { locker.showCount == 2 })
        #expect(locker.lastCanPostpone == true)
        coordinator.postponeActiveBreak()
        #expect(coordinator.localStatus().planState == .postponed)
        try #require(await waitUntil { locker.showCount == 3 })
        #expect(locker.lastCanPostpone == true)
        #expect(locker.lastWaitsForReturn == true)
        coordinator.completeActiveBreak()
        coordinator.startWork()
        #expect(!coordinator.isWaitingForWork)
        #expect(coordinator.localStatus().nextBreakAt == nil)
        #expect(coordinator.captureEnforcementState().dailyBreakCounts[FlexibleWorkSettings.scheduleID] == 1)
    }
}
