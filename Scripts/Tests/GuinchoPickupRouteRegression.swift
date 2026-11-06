import Combine
import CoreLocation
import Foundation

@MainActor final class ProviderDiscoveryTracker {
    @Published var lastFix: DeviceLocationFix?
}

@main struct GuinchoPickupRouteRegression {
    @MainActor static func main() async throws {
        func waitFor(_ condition: () -> Bool) async throws {
            for _ in 0..<100 {
                if condition() { return }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            preconditionFailure("Expected pickup route transition")
        }
        let tracker = ProviderDiscoveryTracker()
        let pickup = CLLocationCoordinate2D(latitude: -23.5, longitude: -46.6)
        let fix = DeviceLocationFix(latitude: -23.55, longitude: -46.65, horizontalAccuracy: 10, timestamp: Date())
        var requests = 0
        let model = GuinchoPickupRouteViewModel(tracker: tracker) { start, end in
            requests += 1
            precondition(start.latitude == fix.latitude && end.latitude == pickup.latitude)
            return [start, end]
        }
        let appointmentID = UUID()
        model.activate(appointmentID: appointmentID, pickup: pickup, fallbackFix: fix)
        try await waitFor { model.coordinates.count == 2 }
        precondition(model.coordinates.last?.longitude == pickup.longitude && model.fitTrigger == 1)
        model.activate(appointmentID: appointmentID, pickup: pickup, fallbackFix: fix)
        precondition(requests == 1, "Repeated status updates must not recalculate the same route")
        tracker.lastFix = .init(latitude: -23.525, longitude: -46.625, horizontalAccuracy: 10, timestamp: Date())
        try await waitFor { abs((model.coordinates.first?.latitude ?? 0) + 23.525) < 0.000001 }
        precondition(requests == 1, "Traveled line must disappear without a routing request")
        model.stop()
        precondition(model.coordinates.isEmpty)
        tracker.lastFix = nil

        let stale = DeviceLocationFix(latitude: fix.latitude, longitude: fix.longitude, horizontalAccuracy: 10,
                                      timestamp: Date().addingTimeInterval(-60))
        model.activate(appointmentID: UUID(), pickup: pickup, fallbackFix: stale)
        try await Task.sleep(nanoseconds: 30_000_000)
        precondition(requests == 1 && model.coordinates.isEmpty)
        tracker.lastFix = fix
        try await waitFor { model.coordinates.count == 2 }
        model.stop()

        var pending: CheckedContinuation<[CLLocationCoordinate2D], Error>?
        let cancelled = GuinchoPickupRouteViewModel(tracker: tracker) { _, _ in
            try await withCheckedThrowingContinuation { pending = $0 }
        }
        cancelled.activate(appointmentID: UUID(), pickup: pickup, fallbackFix: fix)
        try await waitFor { pending != nil }
        cancelled.stop()
        pending?.resume(returning: [.init(latitude: fix.latitude, longitude: fix.longitude), pickup])
        try await Task.sleep(nanoseconds: 30_000_000)
        precondition(cancelled.coordinates.isEmpty, "Pickup directions must not reappear after transport starts")
        print("PASS: route uses truck GPS and pickup target; polling reuses route; stale GPS rejected; cancelled directions cannot overwrite transport")
    }
}
