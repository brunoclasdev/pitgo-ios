import Foundation
import CoreLocation

enum MobileDispatchFailureReason { case offline, timeout, sessionExpired, paymentRequired, notFound, serviceUnavailable, contract, unknown }
enum MobileDispatchOperationResult { case snapshot(MobileDispatchSnapshot), noActiveFlow, failure(MobileDispatchFailureReason) }
enum ExternalNavigator {
    static func isValid(_ point: CLLocationCoordinate2D) -> Bool { CLLocationCoordinate2DIsValid(point) }
}
@MainActor final class MobileDispatchRepository {
    var snapshot: MobileDispatchSnapshot
    var offline = false
    var reads = 0
    var starts = 0
    var startedRevision: Int64?
    var callback: (@Sendable () -> Void)?
    init(_ snapshot: MobileDispatchSnapshot) { self.snapshot = snapshot }
    func getActiveDispatch() async -> MobileDispatchOperationResult { reads += 1; return offline ? .failure(.offline) : .snapshot(snapshot) }
    func getGuinchoSnapshot(appointmentID: UUID) async -> MobileDispatchOperationResult { await getActiveDispatch() }
    func subscribeToProvider(providerID: UUID, onInvalidated: @escaping @Sendable () -> Void) async {
        callback = onInvalidated
        try? await Task.sleep(nanoseconds: 60_000_000_000) // Realtime subscription stalls; polling must still update.
    }
    func disconnectAll() {}
    func respond(appointmentID: UUID, accept: Bool, expectedRevision: Int64) async -> MobileDispatchOperationResult { .snapshot(snapshot) }
    func startAppointment(appointmentID: UUID, expectedRevision: Int64) async -> MobileDispatchOperationResult { .snapshot(snapshot) }
    func completeAppointment(appointmentID: UUID, expectedRevision: Int64) async -> MobileDispatchOperationResult { .snapshot(snapshot) }
    func arriveGuincho(appointmentID: UUID, expectedRevision: Int64) async -> MobileDispatchOperationResult { .snapshot(snapshot) }
    func startGuinchoTransport(appointmentID: UUID, expectedRevision: Int64) async -> MobileDispatchOperationResult {
        starts += 1; startedRevision = expectedRevision
        try? await Task.sleep(nanoseconds: 100_000_000)
        return .snapshot(snapshot)
    }
    func cancelAppointment(appointmentID: UUID, reason: String, expectedRevision: Int64) async -> MobileDispatchOperationResult { .snapshot(snapshot) }
}
@main struct ProviderStartTransportRegression {
    static let appointmentID = UUID(), serviceID = UUID(), searchID = UUID()
    static func snapshot(state: String = "SUBMITTED", required: Bool = true, inspection: Bool = true,
                         arrived: Bool = true, startAllowed: Bool = true, status: String = "ACCEPTED", appointmentRevision: Int = 11) throws -> MobileDispatchSnapshot {
        var appointment: [String: Any] = ["appointment_id": appointmentID.uuidString, "status": status, "revision": appointmentRevision, "quoted_price": 100]
        if arrived { appointment["arrived_at"] = 0 }
        var value: [String: Any] = ["search_id": searchID.uuidString, "service_id": serviceID.uuidString,
            "service_name": "Guincho", "dispatch_kind": "GUINCHO_DIRECT", "status": status, "revision": 7,
            "radius_meters": 25000, "server_now": 0, "allowed_actions": startAllowed ? ["CANCEL", "START"] : ["CANCEL"], "appointment": appointment]
        if inspection { value["inspection"] = ["required": required, "state": state, "required_points_ready": 4, "photo_count": 4, "allowed_actions": []] }
        return try JSONDecoder().decode(MobileDispatchSnapshot.self, from: JSONSerialization.data(withJSONObject: value))
    }
    @MainActor static func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        preconditionFailure("Expected provider update without Realtime")
    }
    @MainActor static func main() async throws {
        for state in ["DRAFT", "SUBMITTED", "CORRECTION_REQUESTED"] {
            let value = try snapshot(state: state)
            precondition(!value.canStartGuinchoTransport)
        }
        let noArrival = try snapshot(state: "APPROVED", arrived: false)
        let noAction = try snapshot(state: "APPROVED", startAllowed: false)
        let noInspection = try snapshot(state: "APPROVED", inspection: false)
        let waived = try snapshot(required: false)
        precondition(!noArrival.canStartGuinchoTransport && !noAction.canStartGuinchoTransport && !noInspection.canStartGuinchoTransport)
        precondition(waived.canStartGuinchoTransport)

        let repository = MobileDispatchRepository(try snapshot(startAllowed: false))
        let vm = ProviderIncomingRequestViewModel(providerID: UUID(), repository: repository)
        func current() -> MobileDispatchSnapshot? {
            if case let .reserved(snapshot, _) = vm.state { return snapshot }
            return nil
        }
        vm.start()
        try await waitFor { current() != nil }
        vm.startTransport()
        precondition(repository.starts == 0)
        try await Task.sleep(nanoseconds: 100_000_000) // Let the guarded action's refresh finish before approval.
        // Approval can change actions while retaining the same search revision.
        repository.snapshot = try snapshot(state: "APPROVED")
        try await waitFor { current()?.canStartGuinchoTransport == true }
        repository.offline = true
        vm.refreshNow()
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(current()?.canStartGuinchoTransport == true)
        repository.offline = false
        vm.startTransport(); vm.startTransport()
        try await waitFor { repository.starts == 1 }
        precondition(repository.startedRevision == 11)
        try await Task.sleep(nanoseconds: 150_000_000)
        vm.stop()
        let reads = repository.reads
        repository.callback?()
        try await Task.sleep(nanoseconds: 50_000_000)
        precondition(repository.reads == reads)

        let waitingRepository = MobileDispatchRepository(try snapshot(arrived: false, startAllowed: false, status: "AWAITING_PAYMENT"))
        let waiting = ProviderIncomingRequestViewModel(providerID: UUID(), repository: waitingRepository)
        waiting.start()
        try await waitFor { if case .reserved = waiting.state { return true }; return false }
        precondition(!waiting.didFinishGuincho)
        waiting.stop()
        print("PASS: Android start gate, inspection approval without Realtime, same-search revision updates, offline preservation, single start with latest revision, stop cleanup and payment wait")
    }
}
