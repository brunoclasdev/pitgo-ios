import CoreLocation
import Foundation

@main struct GuinchoRouteProgressRegression {
    static func main() {
        let now = Date()
        func fix(_ longitude: Double, latitude: Double = -23.5, age: TimeInterval = 0) -> DeviceLocationFix {
            .init(latitude: latitude, longitude: longitude, horizontalAccuracy: 10, timestamp: now.addingTimeInterval(-age))
        }
        let path = [-46.63, -46.62, -46.61].map { CLLocationCoordinate2D(latitude: -23.5, longitude: $0) }
        var progress = GuinchoRouteProgress()
        let first = progress.update(path: path, fix: fix(-46.625), now: now)
        precondition(first.count == 3 && abs(first[0].longitude + 46.625) < 0.000001)
        let next = progress.update(path: path, fix: fix(-46.615), now: now)
        precondition(next.count == 2 && abs(next[0].longitude + 46.615) < 0.000001)
        let jitter = progress.update(path: path, fix: fix(-46.616), now: now)
        precondition(jitter[0].longitude == next[0].longitude, "GPS jitter must not restore traveled segments")
        let offRoute = progress.update(path: path, fix: fix(-46.615, latitude: -23.6), now: now)
        precondition(offRoute[0].longitude == next[0].longitude)
        let stale = progress.update(path: path, fix: fix(-46.611, age: 60), now: now)
        precondition(stale[0].longitude == next[0].longitude)
        precondition(progress.update(path: path, fix: fix(-46.61), now: now).isEmpty)
        precondition(progress.update(path: path, fix: fix(-46.611), now: now).isEmpty)

        let rerouted = [-46.615, -46.60].map { CLLocationCoordinate2D(latitude: -23.5, longitude: $0) }
        precondition(progress.update(path: rerouted, fix: fix(-46.615), now: now).count == 2)
        precondition(progress.update(path: [], fix: nil, now: now).isEmpty)
        print("PASS: traveled segments removed on every GPS fix, monotonic progress, GPS validation, arrival clears line and rerouting resets progress")
    }
}
