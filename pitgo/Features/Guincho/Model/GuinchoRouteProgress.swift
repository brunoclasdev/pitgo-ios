import CoreLocation
import Foundation

/// Clips the displayed line locally; the full route remains available for deviation checks.
struct GuinchoRouteProgress {
    private var path: [CLLocationCoordinate2D] = []
    private var remaining: [CLLocationCoordinate2D] = []
    private var segment = 0
    private var fraction = 0.0

    mutating func update(path: [CLLocationCoordinate2D], fix: DeviceLocationFix?, now: Date = Date()) -> [CLLocationCoordinate2D] {
        if self.path.count != path.count || !zip(self.path, path).allSatisfy({
            $0.latitude == $1.latitude && $0.longitude == $1.longitude
        }) {
            self.path = path
            remaining = path
            segment = 0
            fraction = 0
        }
        guard path.count >= 2, let fix,
              fix.horizontalAccuracy > 0, fix.horizontalAccuracy <= 100,
              now.timeIntervalSince(fix.timestamp) <= 30, fix.timestamp.timeIntervalSince(now) <= 5,
              CLLocationCoordinate2DIsValid(.init(latitude: fix.latitude, longitude: fix.longitude)) else { return remaining }

        let latScale = 111_320.0
        let lonScale = latScale * cos(fix.latitude * .pi / 180)
        func longitudeDelta(_ value: Double, from origin: Double) -> Double {
            (value - origin + 540).truncatingRemainder(dividingBy: 360) - 180
        }
        var best: (index: Int, t: Double, distance: Double)?
        for index in segment..<(path.count - 1) {
            let a = path[index], b = path[index + 1]
            let ax = longitudeDelta(a.longitude, from: fix.longitude) * lonScale
            let ay = (a.latitude - fix.latitude) * latScale
            let dx = longitudeDelta(b.longitude, from: a.longitude) * lonScale
            let dy = (b.latitude - a.latitude) * latScale
            let t = min(max(-(ax * dx + ay * dy) / max(dx * dx + dy * dy, 0.000001), 0), 1)
            let distance = hypot(ax + t * dx, ay + t * dy)
            if distance < (best?.distance ?? .infinity) { best = (index, t, distance) }
        }
        guard let best, best.distance <= min(100, max(35, 2 * fix.horizontalAccuracy)),
              best.index > segment || best.t >= fraction else { return remaining }
        segment = best.index
        fraction = best.t
        let a = path[segment], b = path[segment + 1]
        let longitude = a.longitude + longitudeDelta(b.longitude, from: a.longitude) * fraction
        let point = CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * fraction,
            longitude: (longitude + 540).truncatingRemainder(dividingBy: 360) - 180)
        if segment == path.count - 2,
           CLLocation(latitude: point.latitude, longitude: point.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) < 2 {
            remaining = []
        } else {
            remaining = [point] + Array(path.dropFirst(segment + 1))
        }
        return remaining
    }
}
