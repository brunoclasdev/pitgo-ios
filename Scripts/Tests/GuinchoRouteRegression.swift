import Foundation
import CoreLocation
import Combine

@MainActor final class ProviderDiscoveryTracker {
    @Published var lastFix: DeviceLocationFix?
}
@MainActor final class GuinchoRouteRepository {
    var cached: GuinchoRoutePayload
    var results: [Result<GuinchoRoutePayload, Error>]
    var refreshes = 0
    init(cached: GuinchoRoutePayload, results: [Result<GuinchoRoutePayload, Error>]) { self.cached = cached; self.results = results }
    func snapshot(appointmentID: UUID) async throws -> GuinchoRoutePayload { cached }
    func refresh(appointmentID: UUID, reason: GuinchoRouteReason, knownVersion: Int64) async throws -> GuinchoRoutePayload {
        refreshes += 1
        return try results.removeFirst().get()
    }
}
@main struct GuinchoRouteRegression {
    static let appointmentID = UUID()
    static let destination = GuinchoRouteSnapshot.Point(latitude: -23.54, longitude: -46.62)
    static func payload(status: String? = "ROUTE", outcome: String = "UPDATED", timestamp: String = "2026-11-04T01:00:00.123456Z") throws -> GuinchoRoutePayload {
        var json: [String: Any] = ["outcome": outcome, "appointment_id": appointmentID.uuidString, "route_version": 3,
            "provider_location_revision": 17, "provider_location_published_at": timestamp, "generated_at": timestamp,
            "origin": ["latitude": -23.55, "longitude": -46.63, "accuracy_m": 12,
                       "captured_at": timestamp, "published_at": timestamp],
            "destination": ["latitude": destination.latitude, "longitude": destination.longitude],
            "geometry": ["type": "LineString", "coordinates": [[-46.63, -23.55], [-46.62, -23.54]], "duration_seconds": 500],
            "distance_meters": 1500, "reused": false]
        if let status { json["status"] = status }
        return try GuinchoRouteResponseDecoder.make().decode(GuinchoRoutePayload.self, from: JSONSerialization.data(withJSONObject: json))
    }
    @MainActor static func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        preconditionFailure("Expected route transition")
    }
    @MainActor static func main() async throws {
        for date in ["2026-11-04T01:00:00Z", "2026-11-04T01:00:00.123Z", "2026-11-04T01:00:00.123456+00:00"] {
            let route = try payload(timestamp: date).snapshot()!
            precondition(route.isValid(for: appointmentID, expectedDestination: destination))
            precondition(route.origin.accuracyM == 12 && route.origin.publishedAt == route.providerLocationPublishedAt)
        }
        let cached = try payload(status: nil, outcome: "FOUND")
        precondition(cached.snapshot() != nil)
        let wrongStatus = try payload(status: "UNAVAILABLE")
        precondition(wrongStatus.snapshot() == nil)
        let noRoute = try GuinchoRouteResponseDecoder.make().decode(GuinchoRoutePayload.self, from: Data(#"{"outcome":"NOT_FOUND"}"#.utf8))

        // A fix on the route must not look miles away merely because longitude is negative.
        let fix = DeviceLocationFix(latitude: -23.545, longitude: -46.625, horizontalAccuracy: 10, timestamp: Date())
        let path = [CLLocationCoordinate2D(latitude: -23.55, longitude: -46.63), .init(latitude: -23.54, longitude: -46.62)]
        precondition(GuinchoRouteViewModel.distance(fix: fix, to: path) < 0.01)
        let away = DeviceLocationFix(latitude: -23.53, longitude: -46.60, horizontalAccuracy: 10, timestamp: Date())
        precondition(GuinchoRouteViewModel.distance(fix: away, to: path) > 100)

        let locationFailure = GuinchoRouteFailure(status: 409, code: "LOCATION_NOT_READY", retryable: true, retryAfterMs: 5000)
        let authFailure = GuinchoRouteFailure(status: 401, code: "AUTH_REQUIRED", retryable: true, retryAfterMs: nil)
        precondition(locationFailure.shouldRetry && !authFailure.shouldRetry)
        let repository = GuinchoRouteRepository(cached: noRoute,
            results: [.success(try payload()), .failure(locationFailure), .success(try payload()), .failure(authFailure)])
        let vm = GuinchoRouteViewModel(repository: repository, tracker: ProviderDiscoveryTracker())
        vm.activate(appointmentID: appointmentID, destination: destination.coordinate)
        try await waitFor { if case .ready = vm.state { return true }; return false }
        vm.retry()
        try await waitFor {
            if case let .unavailable(route?, message) = vm.state { return route.routeVersion == 3 && message.contains("localização precisa") }
            return false
        }
        vm.retry()
        try await waitFor { if case .ready = vm.state { return true }; return false }
        vm.retry()
        try await waitFor { if case .unavailable(nil, _) = vm.state { return true }; return false }
        let count = repository.refreshes
        vm.retry(); vm.activate(appointmentID: appointmentID, destination: destination.coordinate)
        try await Task.sleep(nanoseconds: 50_000_000)
        precondition(repository.refreshes == count)
        vm.stop()
        print("PASS: backend snake_case origin, ISO8601 dates with/without fractions, cached routes, geographic deviation, retained route on GPS wait, manual retry and denied-access cleanup")
    }
}
