import Foundation
import Combine

enum EnvironmentConfig { static let current = Current(); struct Current { let fingerprint = "test" } }
enum DeviceLocationServiceStatus { static let isEnabled = true }
enum PublishFailure { case sessionExpired, offline, unknown }
enum DiscoveryPublishOutcome {
    case published(version: Int64, publishedAt: Date), ignored, publisherConflict, failure(PublishFailure)
}
@MainActor final class DeviceLocationRepository {
    var authorizationStatus: DeviceLocationAuthorization = .authorizedAlways
    var starts = 0
    var stops = 0
    var continuation: AsyncStream<DeviceLocationFix>.Continuation?
    func requestAlwaysAuthorization() {}
    func requestWhenInUseAuthorization() {}
    func startHighPrecisionUpdates() -> AsyncStream<DeviceLocationFix> {
        starts += 1
        return AsyncStream { continuation = $0 }
    }
    func stopHighPrecisionUpdates() { stops += 1; continuation?.finish(); continuation = nil }
    func emit() { continuation?.yield(.init(latitude: -23.55, longitude: -46.63, horizontalAccuracy: 10, timestamp: Date())) }
}
@MainActor final class MobileDispatchRepository {
    var ids: [UUID] = []
    var sequences: [Int64] = []
    var stoppedIDs: [UUID] = []
    var results: [DiscoveryPublishOutcome] = []
    var hold = false
    var held: CheckedContinuation<DiscoveryPublishOutcome, Never>?
    func publishDiscoveryLocation(fix: DeviceLocationFix, trackerInstanceID: UUID, sequence: Int64) async -> DiscoveryPublishOutcome {
        ids.append(trackerInstanceID); sequences.append(sequence)
        if hold { hold = false; return await withCheckedContinuation { held = $0 } }
        if !results.isEmpty { return results.removeFirst() }
        return .published(version: sequence, publishedAt: Date())
    }
    func stopDiscoveryLocation(trackerInstanceID: UUID) async { stoppedIDs.append(trackerInstanceID) }
}
@main struct ProviderPublisherRegression {
    @MainActor static func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        preconditionFailure("Expected publisher transition")
    }
    @MainActor static func main() async throws {
        let suite = "pitgo.publisher-test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let accountID = UUID()
        let store = ProviderPublisherLeaseStore(defaults: defaults)
        let scope = store.scope(accountID: accountID, environment: "homol")
        let lease = store.lease(scope: scope)
        let owner = UUID()
        _ = store.claim(scope: scope, ownerID: owner, stop: {})
        precondition(store.nextSequence(scope: scope, ownerID: owner) == 1)
        let afterRelaunch = ProviderPublisherLeaseStore(defaults: defaults)
        precondition(afterRelaunch.lease(scope: scope).trackerID == lease.trackerID)
        precondition(afterRelaunch.lease(scope: scope).sequence == 1)
        let otherAccount = store.scope(accountID: UUID(), environment: "homol")
        let otherEnvironment = store.scope(accountID: accountID, environment: "prod")
        precondition(store.lease(scope: otherAccount).trackerID != lease.trackerID)
        precondition(store.lease(scope: otherEnvironment).trackerID != lease.trackerID)
        store.release(scope: scope, ownerID: owner)

        let location = DeviceLocationRepository(), repository = MobileDispatchRepository()
        let tracker = ProviderDiscoveryTracker(locationRepository: location, dispatchRepository: repository,
            accountID: accountID, environment: "homol", leaseStore: store, conflictRetryDelay: 0.02)
        tracker.start()
        try await waitFor { location.starts == 1 }
        precondition(tracker.state == .starting)
        location.emit()
        try await waitFor { if case .active = tracker.state { return true }; return false }
        tracker.stop(); tracker.start()
        try await waitFor { location.starts == 2 }
        location.emit()
        try await waitFor { repository.ids.count == 2 }
        precondition(repository.ids == [lease.trackerID, lease.trackerID])
        precondition(repository.sequences == [2, 3])

        // Replace the owner while an old publish is in flight. The stale conflict cannot stop its successor.
        tracker.stop()
        try await Task.sleep(nanoseconds: 20_000_000)
        repository.hold = true
        tracker.start()
        try await waitFor { location.starts == 3 }
        location.emit()
        try await waitFor { repository.held != nil }
        tracker.stop(); tracker.stop(); tracker.start()
        try await Task.sleep(nanoseconds: 20_000_000)
        precondition(location.starts == 3)
        repository.held?.resume(returning: .publisherConflict); repository.held = nil
        try await waitFor { location.starts == 4 }
        precondition(tracker.state == .starting && !tracker.isWaitingForPublisherRecovery)
        location.emit()
        try await waitFor { if case .active = tracker.state { return true }; return false }

        // A reconstructed dashboard replaces the previous in-process publisher without changing lease identity.
        let replacement = ProviderDiscoveryTracker(locationRepository: location, dispatchRepository: repository,
            accountID: accountID, environment: "homol", leaseStore: store, conflictRetryDelay: 0.02)
        replacement.start()
        try await waitFor { location.starts == 5 }
        precondition(tracker.state == .stopped)
        location.emit()
        try await waitFor { if case .active = replacement.state { return true }; return false }
        precondition(Set(repository.ids).count == 1)
        precondition(repository.sequences == repository.sequences.sorted() && Set(repository.sequences).count == repository.sequences.count)
        replacement.stop()
        try await Task.sleep(nanoseconds: 20_000_000)

        // Migrate once past an old server lease, then respect a continuing real conflict.
        let conflictLocation = DeviceLocationRepository(), conflictRepository = MobileDispatchRepository()
        conflictRepository.results = [.publisherConflict, .publisherConflict]
        let conflicting = ProviderDiscoveryTracker(locationRepository: conflictLocation, dispatchRepository: conflictRepository,
            accountID: accountID, environment: "homol", leaseStore: store, conflictRetryDelay: 0.02)
        conflicting.start()
        try await waitFor { conflictLocation.starts == 1 }
        conflictLocation.emit()
        try await waitFor { conflicting.isWaitingForPublisherRecovery }
        try await waitFor { conflictLocation.starts == 2 }
        conflictLocation.emit()
        try await waitFor { conflicting.state == .degraded(reason: .publisherConflict) && !conflicting.isWaitingForPublisherRecovery }
        try await Task.sleep(nanoseconds: 80_000_000)
        precondition(conflictLocation.starts == 2 && conflictRepository.ids.count == 2)
        precondition(Set(conflictRepository.ids).count == 1)
        conflicting.stop()
        try await Task.sleep(nanoseconds: 20_000_000)

        let cancelledLocation = DeviceLocationRepository(), cancelledRepository = MobileDispatchRepository()
        cancelledRepository.results = [.publisherConflict]
        let cancelled = ProviderDiscoveryTracker(locationRepository: cancelledLocation, dispatchRepository: cancelledRepository,
            accountID: accountID, environment: "homol", leaseStore: store, conflictRetryDelay: 0.05)
        cancelled.start()
        try await waitFor { cancelledLocation.starts == 1 }
        cancelledLocation.emit()
        try await waitFor { cancelled.isWaitingForPublisherRecovery }
        cancelled.stop()
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(cancelled.state == .stopped && cancelledLocation.starts == 1)
        print("PASS: account/environment lease persistence, monotonic sequences, restart cleanup, stale response isolation, single in-process publisher and bounded conflict recovery without takeover")
    }
}
