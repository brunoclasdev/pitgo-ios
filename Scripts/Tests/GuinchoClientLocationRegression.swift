import Foundation
import CoreLocation

@MainActor final class AppointmentTrackingRepository {
    var snapshot: AppointmentProviderLocationSnapshot?
    func fetchSnapshot(appointmentID: UUID) async -> AppointmentProviderLocationSnapshot? { snapshot }
}
struct GuinchoTripSummary {
    let pickup: CLLocationCoordinate2D
    let destination: CLLocationCoordinate2D
}
enum GuinchoClientRoutePhase {
    case approaching, transporting
    func target(_ trip: GuinchoTripSummary) -> CLLocationCoordinate2D {
        self == .approaching ? trip.pickup : trip.destination
    }
}

@main struct GuinchoClientLocationRegression {
    @MainActor static func main() async throws {
        func snapshot(_ latitude: Double, state: String = "LIVE", longitude: Double = -46.7) throws -> AppointmentProviderLocationSnapshot {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let timestamp = ISO8601DateFormatter().string(from: Date())
            return try decoder.decode(AppointmentProviderLocationSnapshot.self,
                from: Data("{\"state\":\"\(state)\",\"latitude\":\(latitude),\"longitude\":\(longitude),\"accuracy_m\":10,\"captured_at\":\"\(timestamp)\"}".utf8))
        }
        func waitFor(_ condition: () -> Bool) async throws {
            for _ in 0..<100 {
                if condition() { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            preconditionFailure("Expected location transition")
        }
        let trip = GuinchoTripSummary(pickup: .init(latitude: -23.5, longitude: -46.6),
                                     destination: .init(latitude: -23.6, longitude: -46.5))
        let repository = AppointmentTrackingRepository()
        repository.snapshot = try snapshot(-23.9)
        // A stalled router must neither hide the first fix nor block later location updates.
        let model = GuinchoClientRouteMapModel(pollInterval: 1_000_000) { _, _ in
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return []
        }
        let observing = Task { await model.observe(appointmentID: UUID(), trip: trip, phase: .approaching, repository: repository) }
        try await waitFor { model.provider != nil }
        precondition(model.route.isEmpty && model.fitTrigger > 0)
        precondition(model.fitCoordinates(trip: trip, phase: .approaching).contains { $0.latitude == -23.9 })
        let firstFit = model.fitTrigger
        repository.snapshot = try snapshot(-23.8, state: "STALE")
        try await waitFor { model.provider?.latitude == -23.8 }
        precondition(model.fitTrigger == firstFit, "GPS updates change framing coordinates without a manual recenter request")
        let approachingFrame = model.fitCoordinates(trip: trip, phase: .approaching)
        precondition(approachingFrame.count == 2 && approachingFrame[0].latitude == -23.8)
        precondition(approachingFrame[1].latitude == trip.pickup.latitude)
        let transportFrame = model.fitCoordinates(trip: trip, phase: .transporting)
        precondition(transportFrame.count == 2 && transportFrame[0].latitude == -23.8)
        precondition(transportFrame[1].latitude == trip.destination.latitude)
        precondition(model.message?.contains("última localização") == true)
        model.recenter()
        precondition(model.fitTrigger > firstFit)
        precondition(model.fitCoordinates(trip: trip, phase: .approaching).contains { $0.latitude == -23.8 })
        repository.snapshot = try snapshot(-23.8, state: "ENDED")
        try await waitFor { model.provider == nil }
        await observing.value

        // Routing failure still leaves the truck visible and included in the camera bounds.
        repository.snapshot = try snapshot(-24)
        let failed = GuinchoClientRouteMapModel(pollInterval: 1_000_000) { _, _ in throw URLError(.notConnectedToInternet) }
        let failingObservation = Task { await failed.observe(appointmentID: UUID(), trip: trip, phase: .transporting, repository: repository) }
        try await waitFor { failed.message?.contains("Não foi possível") == true }
        precondition(failed.provider?.latitude == -24 && failed.route.isEmpty)
        precondition(failed.fitCoordinates(trip: trip, phase: .transporting).contains { $0.latitude == -24 })
        failingObservation.cancel()
        await failingObservation.value
        // Client-side clipping follows remote truck fixes without waiting for route recalculation.
        for phase in [GuinchoClientRoutePhase.approaching, .transporting] {
            var calculations = 0
            repository.snapshot = try snapshot(-23.5, longitude: -46.63)
            let clipping = GuinchoClientRouteMapModel(pollInterval: 1_000_000) { _, _ in
                calculations += 1
                return [-46.63, -46.62, -46.61].map { .init(latitude: -23.5, longitude: $0) }
            }
            let observation = Task { await clipping.observe(appointmentID: UUID(), trip: trip, phase: phase, repository: repository) }
            try await waitFor { clipping.route.count == 3 }
            let initialVersion = clipping.routeVersion
            repository.snapshot = try snapshot(-23.5, longitude: -46.615)
            try await waitFor { clipping.route.count == 2 }
            precondition(abs(clipping.route[0].longitude + 46.615) < 0.000001)
            precondition(clipping.routeVersion > initialVersion && calculations == 1)
            repository.snapshot = try snapshot(-23.5, longitude: -46.616)
            try await waitFor { clipping.provider?.longitude == -46.616 }
            precondition(abs(clipping.route[0].longitude + 46.615) < 0.000001)
            repository.snapshot = try snapshot(-23.5, longitude: -46.61)
            try await waitFor { clipping.route.isEmpty }
            precondition(calculations == 1)
            observation.cancel()
            await observation.value
        }
        print("PASS: client removes traveled sections in both phases, updates map geometry version, ignores backwards GPS jitter and clears route on arrival")
        print("PASS: truck visible without directions, polling during routing, stale/ended states and recentering")
    }
}
