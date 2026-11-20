import Foundation
import Testing
import StandLockCore

@MainActor
@Suite("Local status publisher")
struct LocalStatusPublisherTests {
    @Test
    func publishesAnExplicitVersionedSnapshotOnlyWhenEnabled() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("status.json")
        let now = Date(timeIntervalSince1970: 1_794_010_000)
        let publisher = LocalStatusPublisher(directory: directory, notificationName: .init(UUID().uuidString)) {
            LocalStatusSnapshot(updatedAt: now, planState: .work, nextBreakAt: nil, inputIdleSeconds: 42.5)
        }

        publisher.refreshForPlanChange()
        #expect(!FileManager.default.fileExists(atPath: file.path))

        publisher.start()
        defer { publisher.stop() }
        let exported = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(Set(exported.keys) == ["schemaVersion", "updatedAt", "planState", "nextBreakAt", "postponeCount", "inputIdleSeconds"])
        #expect(exported["schemaVersion"] as? Int == 1)
        #expect(exported["updatedAt"] as? String == "2026-11-07T00:06:40Z")
        #expect(exported["planState"] as? String == "work")
        #expect(exported["nextBreakAt"] is NSNull)
        #expect(exported["inputIdleSeconds"] as? Double == 42.5)

        publisher.stop()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test
    func publishesWhenOnlyPostponeCountChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("status.json")
        let now = Date()
        var count = 1
        let publisher = LocalStatusPublisher(directory: directory, notificationName: .init(UUID().uuidString)) {
            LocalStatusSnapshot(
                updatedAt: now, planState: .postponed, nextBreakAt: nil, postponeCount: count, inputIdleSeconds: nil
            )
        }
        publisher.start()
        defer { publisher.stop() }

        count = 2
        publisher.refreshForPlanChange()
        let exported = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(exported["postponeCount"] as? Int == 2)
    }
}
