import Foundation

@MainActor
public final class LocalStatusPublisher {
    private let directory: URL
    private let notificationName: Notification.Name
    private let snapshot: () -> LocalStatusSnapshot
    private let encoder = JSONEncoder()
    private var lastPublished: LocalStatusSnapshot?
    private var heartbeat: Task<Void, Never>?

    private var file: URL { directory.appendingPathComponent("status.json") }

    public init(directory: URL, notificationName: Notification.Name, snapshot: @escaping () -> LocalStatusSnapshot) {
        self.directory = directory
        self.notificationName = notificationName
        self.snapshot = snapshot
        encoder.dateEncodingStrategy = .iso8601
    }

    public func start() {
        guard heartbeat == nil else { return }
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                self.publish(heartbeat: true)
            }
        }
        publish(heartbeat: true)
    }

    public func stop() {
        heartbeat?.cancel()
        heartbeat = nil
        lastPublished = nil
        // This also cleans up a file left by a previous process when starting disabled.
        if (try? FileManager.default.removeItem(at: file)) != nil {
            notify()
        }
    }

    public func refreshForPlanChange() {
        guard heartbeat != nil else { return }
        publish(heartbeat: false)
    }

    private func publish(heartbeat: Bool) {
        let status = snapshot()
        let planChanged = lastPublished?.planState != status.planState || lastPublished?.nextBreakAt != status.nextBreakAt
        guard heartbeat || planChanged else { return }
        do {
            let files = FileManager.default
            try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try encoder.encode(status).write(to: file, options: .atomic)
            lastPublished = status
            if planChanged { notify() }
        } catch {
            // A failed update leaves the old timestamp in place so readers can expire it.
        }
    }

    private func notify() {
        DistributedNotificationCenter.default().postNotificationName(
            notificationName, object: nil, userInfo: nil, deliverImmediately: true
        )
    }
}
