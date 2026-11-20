import Foundation
import Testing
import Coordination
import StandLockCore

@MainActor
@Suite("Local status file")
struct LocalStatusTests {
    @Test
    func staysPostponedWhileReturnTimeAppearsAndDisappears() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("status.json")
        let scheduler = MockScheduler()
        scheduler.nextBreakTimeToReturn = Date().addingTimeInterval(0.05)
        let detector = MockDetector()
        detector.contextToReturn = DetectionContext(cameraActive: true)
        let coordinator = BreakCoordinator(
            scheduler: scheduler, detector: detector, locker: MockLocker(), deferralPollingInterval: 0.05
        )
        let publisher = LocalStatusPublisher(directory: directory, notificationName: .init(UUID().uuidString)) {
            let now = Date()
            let plan = coordinator.localStatus(now: now)
            return LocalStatusSnapshot(
                updatedAt: now, planState: plan.planState, nextBreakAt: plan.nextBreakAt,
                postponeCount: plan.postponeCount, inputIdleSeconds: nil
            )
        }
        let listener = Task {
            for await _ in coordinator.events { publisher.refreshForPlanChange() }
        }
        defer {
            listener.cancel()
            publisher.stop()
            coordinator.stop()
        }

        func status() -> [String: Any] { (try? readStatus(file)) ?? [:] }

        coordinator.start(with: [makeSchedule()], preferences: AppPreferences(
            cameraDetection: .deferBreak, postponeReturnDelay: 30, idleDetectionEnabled: false
        ))
        publisher.start()
        #expect(await waitUntil { status()["planState"] as? String == "deferred" })
        #expect(try readStatus(file)["postponeCount"] as? Int == 0)
        detector.contextToReturn = .clear
        #expect(await waitUntil { status()["planState"] as? String == "break" })
        #expect(try readStatus(file)["postponeCount"] as? Int == 0)

        let nextScheduledBreak = Date().addingTimeInterval(120)
        scheduler.nextBreakTimeToReturn = nextScheduledBreak
        detector.contextToReturn = DetectionContext(cameraActive: true)
        coordinator.postponeActiveBreak()
        #expect(await waitUntil { status()["planState"] as? String == "postponed" })
        #expect(try readStatus(file)["nextBreakAt"] is NSNull)
        #expect(try readStatus(file)["postponeCount"] as? Int == 1)

        detector.contextToReturn = .clear
        #expect(await waitUntil { status()["nextBreakAt"] is String })
        #expect(try readStatus(file)["planState"] as? String == "postponed")

        detector.contextToReturn = DetectionContext(cameraActive: true)
        #expect(await waitUntil { status()["nextBreakAt"] is NSNull })
        #expect(try readStatus(file)["planState"] as? String == "postponed")

        detector.contextToReturn = .clear
        #expect(await waitUntil { status()["nextBreakAt"] is String })
        coordinator.pause(for: 120)
        publisher.refreshForPlanChange()
        #expect(try readStatus(file)["planState"] as? String == "postponed")
        #expect(try readStatus(file)["nextBreakAt"] is NSNull)
        coordinator.resume()
        #expect(await waitUntil { status()["nextBreakAt"] is String })

        coordinator.handleScreenLock()
        publisher.refreshForPlanChange()
        #expect(try readStatus(file)["planState"] as? String == "postponed")
        #expect(try readStatus(file)["nextBreakAt"] is NSNull)
        coordinator.handleScreenUnlock()
        #expect(await waitUntil { status()["nextBreakAt"] is String })

        coordinator.updatePreferences(AppPreferences(postponeReturnDelay: 0, idleDetectionEnabled: false))
        publisher.refreshForPlanChange()
        #expect(try readStatus(file)["planState"] as? String == "postponed")
        #expect(try readStatus(file)["nextBreakAt"] is NSNull)
        #expect(await waitUntil { status()["planState"] as? String == "break" })
        #expect(try readStatus(file)["nextBreakAt"] is NSNull)
        #expect(try readStatus(file)["postponeCount"] as? Int == 1)

        detector.contextToReturn = DetectionContext(cameraActive: true)
        coordinator.postponeActiveBreak()
        #expect(await waitUntil { status()["planState"] as? String == "postponed" })
        #expect(try readStatus(file)["postponeCount"] as? Int == 2)
        detector.contextToReturn = .clear
        #expect(await waitUntil { status()["planState"] as? String == "break" })
        #expect(try readStatus(file)["postponeCount"] as? Int == 2)

        coordinator.completeActiveBreak()
        #expect(await waitUntil { status()["planState"] as? String == "work" })
        #expect(try readStatus(file)["postponeCount"] as? Int == 0)
        #expect(try readStatus(file)["nextBreakAt"] as? String == ISO8601DateFormatter().string(from: nextScheduledBreak))
    }

    private func readStatus(_ file: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    }
}
