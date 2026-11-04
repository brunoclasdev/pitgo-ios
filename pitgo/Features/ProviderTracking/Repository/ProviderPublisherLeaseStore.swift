import Foundation

/// A device-local, account/environment-scoped publisher identity, matching Android's persisted lease.
@MainActor
final class ProviderPublisherLeaseStore {
    static let shared = ProviderPublisherLeaseStore()

    struct Lease: Codable {
        let trackerID: UUID
        var sequence: Int64
    }
    private struct Owner {
        let id: UUID
        let stop: () -> Void
    }
    private struct Cleanup {
        let ownerID: UUID
        let task: Task<Void, Never>
    }
    private let defaults: UserDefaults
    private var owners: [String: Owner] = [:]
    private var cleanups: [String: Cleanup] = [:]

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func scope(accountID: UUID, environment: String) -> String {
        "pitgo.provider-publisher.\(environment).\(accountID.uuidString.lowercased())"
    }

    func lease(scope: String) -> Lease {
        if let data = defaults.data(forKey: scope), let lease = try? JSONDecoder().decode(Lease.self, from: data) { return lease }
        let lease = Lease(trackerID: UUID(), sequence: 0)
        persist(lease, scope: scope)
        return lease
    }

    /// Stop a replaced in-process tracker before its successor starts GPS; await any release already in flight.
    func claim(scope: String, ownerID: UUID, stop: @escaping () -> Void) -> Task<Void, Never>? {
        if let previous = owners[scope], previous.id != ownerID { previous.stop() }
        owners[scope] = Owner(id: ownerID, stop: stop)
        return cleanups[scope]?.task
    }

    func hasCleanup(scope: String, ownerID: UUID) -> Bool { cleanups[scope]?.ownerID == ownerID }

    func isOwner(scope: String, ownerID: UUID) -> Bool { owners[scope]?.id == ownerID }

    func nextSequence(scope: String, ownerID: UUID) -> Int64? {
        guard isOwner(scope: scope, ownerID: ownerID) else { return nil }
        var lease = lease(scope: scope)
        guard lease.sequence < Int64.max else { return nil }
        lease.sequence += 1
        // Persist before sending: a lost response must not cause sequence reuse after restart.
        persist(lease, scope: scope)
        return lease.sequence
    }

    func setCleanup(_ task: Task<Void, Never>, scope: String, ownerID: UUID) {
        guard isOwner(scope: scope, ownerID: ownerID) else { return }
        cleanups[scope] = Cleanup(ownerID: ownerID, task: task)
    }

    func release(scope: String, ownerID: UUID) {
        guard isOwner(scope: scope, ownerID: ownerID) else { return }
        owners[scope] = nil
        cleanups[scope] = nil
    }

    private func persist(_ lease: Lease, scope: String) {
        if let data = try? JSONEncoder().encode(lease) { defaults.set(data, forKey: scope) }
    }
}
