import Foundation

// Standalone network doubles: exercise the production VM without broadcasts or real requests.
enum MobileDispatchFailureReason { case offline, timeout, sessionExpired, paymentRequired, notFound, serviceUnavailable, contract, unknown }
enum MobileDispatchOperationResult { case snapshot(MobileDispatchSnapshot), noActiveFlow, failure(MobileDispatchFailureReason) }
enum PaymentStatusResult { case found(UUID, PaymentStatus, PaymentMethodKind), notFound }
enum PaymentRefundOutcome { case resolved(PaymentStatus), failure }
@MainActor protocol PaymentGateway {
    func status(requestID: UUID) async -> PaymentStatusResult
    func refund(paymentID: UUID) async -> PaymentRefundOutcome
}
@MainActor final class NoPayments: PaymentGateway {
    func status(requestID: UUID) async -> PaymentStatusResult { .notFound }
    func refund(paymentID: UUID) async -> PaymentRefundOutcome { .failure }
}
enum DeviceLocationServiceStatus { static var isEnabled: Bool { true } }
enum LocationAuthorization { case denied, restricted, notDetermined, authorizedWhenInUse, authorizedAlways }
struct TestFix { let latitude: Double; let longitude: Double; let horizontalAccuracy: Double }
enum FixResult { case success(TestFix), permissionDenied, serviceDisabled, timeout, failure }
@MainActor final class DeviceLocationRepository {
    var authorizationStatus: LocationAuthorization { .authorizedWhenInUse }
    func requestWhenInUseAuthorization() {}
    func requestOneShotFix(timeout: Int) async -> FixResult { .failure }
}
@MainActor final class MobileDispatchRepository {
    var snapshot: MobileDispatchSnapshot
    var offline = false
    var reads = 0
    var requestedAppointment: UUID?
    init(_ snapshot: MobileDispatchSnapshot) { self.snapshot = snapshot }
    func getActiveDispatch() async -> MobileDispatchOperationResult { .snapshot(snapshot) }
    func getGuinchoSnapshot(appointmentID: UUID) async -> MobileDispatchOperationResult {
        reads += 1; requestedAppointment = appointmentID
        return offline ? .failure(.offline) : .snapshot(snapshot)
    }
    func subscribeToSearch(searchID: UUID, onInvalidated: @escaping @Sendable () -> Void) async {}
    func disconnectAll() {}
    func startSearch(searchID: UUID, serviceID: UUID, latitude: Double, longitude: Double, accuracyMeters: Double) async -> MobileDispatchOperationResult { .snapshot(snapshot) }
    func nextCandidate(searchID: UUID, expectedRevision: Int64) async -> MobileDispatchOperationResult { .snapshot(snapshot) }
    func requestCandidate(searchID: UUID, expectedRevision: Int64) async -> MobileDispatchOperationResult { .snapshot(snapshot) }
    func confirmCompletion(appointmentID: UUID, expectedRevision: Int64) async -> MobileDispatchOperationResult { .snapshot(snapshot) }
    func disputeCompletion(appointmentID: UUID, expectedRevision: Int64, reason: String) async -> MobileDispatchOperationResult { .snapshot(snapshot) }
    func cancelAppointment(appointmentID: UUID, reason: String, expectedRevision: Int64) async -> MobileDispatchOperationResult { .snapshot(snapshot) }
}
@main struct ClientDispatchRefreshRegression {
    @MainActor static func main() async throws {
        let searchID = UUID(), appointmentID = UUID(), serviceID = UUID()
        func snapshot(_ status: String, appointmentStatus: String, revision: Int) throws -> MobileDispatchSnapshot {
            let data = try JSONSerialization.data(withJSONObject: [
                "search_id": searchID.uuidString, "service_id": serviceID.uuidString,
                "service_name": "Guincho", "dispatch_kind": "GUINCHO_DIRECT", "status": status,
                "revision": revision, "radius_meters": 25000, "server_now": 0,
                "allowed_actions": ["CANCEL"], "appointment": ["appointment_id": appointmentID.uuidString,
                    "status": appointmentStatus, "revision": revision, "quoted_price": 123.45]
            ])
            return try JSONDecoder().decode(MobileDispatchSnapshot.self, from: data)
        }
        let repository = MobileDispatchRepository(try snapshot("AWAITING_PROVIDER", appointmentStatus: "PENDING", revision: 1))
        let vm = ClientMobileDispatchViewModel(serviceID: nil, repository: repository,
            paymentRepository: NoPayments(), locationRepository: DeviceLocationRepository())
        vm.start()
        try await Task.sleep(nanoseconds: 100_000_000)
        repository.snapshot = try snapshot("AWAITING_PAYMENT", appointmentStatus: "AWAITING_PAYMENT", revision: 2)
        // No realtime callback. Polling alone must pick up acceptance.
        try await Task.sleep(nanoseconds: 3_300_000_000)
        precondition(vm.guinchoPaymentContext?.appointmentID == appointmentID)
        precondition(repository.requestedAppointment == appointmentID)
        repository.offline = true
        vm.refresh()
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(vm.guinchoPaymentContext != nil)
        repository.offline = false
        repository.snapshot = try snapshot("CANCELLED", appointmentStatus: "CANCELLED", revision: 3)
        vm.refresh()
        try await Task.sleep(nanoseconds: 100_000_000)
        guard case .terminal = vm.state else { preconditionFailure("Expected terminal snapshot") }
        let reads = repository.reads
        try await Task.sleep(nanoseconds: 3_200_000_000)
        precondition(repository.reads == reads)
        vm.stop()
        print("PASS: acceptance without realtime opens checkout; offline preserves state; terminal snapshot stops polling")
    }
}
