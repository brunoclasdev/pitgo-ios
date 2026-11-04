import Foundation

@MainActor final class AppointmentTrackingRepository {
    var snapshot: AppointmentProviderLocationSnapshot?
    var callback: (@Sendable (Int) -> Void)?
    func connect(appointmentID: UUID, onEvent: @escaping @Sendable (Int) -> Void) async -> AppointmentProviderLocationSnapshot? {
        callback = onEvent
        return snapshot
    }
    func fetchSnapshot(appointmentID: UUID) async -> AppointmentProviderLocationSnapshot? { snapshot }
    func disconnect() async {}
}
@MainActor final class ClientAppointmentLocationPublisher {
    init(repository: AppointmentTrackingRepository) {}
    func run(appointmentID: UUID) async {}
}

@main struct AppointmentTrackingParityRegression {
    @MainActor static func main() async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        func snapshot(_ state: String, version: Int = 10) throws -> AppointmentProviderLocationSnapshot {
            let date = ISO8601DateFormatter().string(from: Date())
            return try decoder.decode(AppointmentProviderLocationSnapshot.self, from: Data("""
            {"state":"\(state)","latitude":-23.5,"longitude":-46.6,"version":\(version),"published_at":"\(date)"}
            """.utf8))
        }
        func label(_ vm: AppointmentTrackingViewModel) -> String {
            switch vm.marker {
            case .unavailable: "unavailable"
            case .live: "live"
            case .stale: "stale"
            case .ended: "ended"
            }
        }
        func wait(_ vm: AppointmentTrackingViewModel, _ expected: String) async throws {
            for _ in 0..<100 {
                if label(vm) == expected { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            preconditionFailure("Expected \(expected), got \(label(vm))")
        }
        let repository = AppointmentTrackingRepository()
        repository.snapshot = try snapshot("LIVE")
        let vm = AppointmentTrackingViewModel(repository: repository)
        vm.connect(appointmentID: UUID())
        try await wait(vm, "live")
        repository.snapshot = try snapshot("STALE")
        repository.callback?(0)
        try await wait(vm, "stale")
        repository.snapshot = try snapshot("ENDED")
        repository.callback?(0)
        try await wait(vm, "ended")
        repository.snapshot = try snapshot("LIVE", version: 20)
        repository.callback?(0)
        try await Task.sleep(nanoseconds: 30_000_000)
        precondition(label(vm) == "ended")
        vm.disconnect()
        try await Task.sleep(nanoseconds: 10_000_000)
        repository.snapshot = try snapshot("LIVE", version: 1)
        vm.connect(appointmentID: UUID())
        try await wait(vm, "live")
        let oldCallback = repository.callback
        vm.disconnect()
        repository.snapshot = try snapshot("ENDED")
        oldCallback?(0)
        try await Task.sleep(nanoseconds: 30_000_000)
        precondition(label(vm) == "live")
        print("PASS: live/stale/ended transitions, terminal state protection, version reset and callbacks after disconnect")
    }
}
