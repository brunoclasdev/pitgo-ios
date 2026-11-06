import CoreLocation
import Foundation

struct PitGoMapAnnotationItem {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let symbolName: String?
}

@main struct GuinchoProviderMapRegression {
    static func main() {
        let pickup = CLLocationCoordinate2D(latitude: -23.5, longitude: -46.6)
        let destination = CLLocationCoordinate2D(latitude: -23.6, longitude: -46.7)
        let approaching = GuinchoProviderMapPresentation.annotations(pickup: pickup, destination: destination, transporting: false)
        precondition(approaching.map(\.id) == ["pickup", "destination"])
        let transporting = GuinchoProviderMapPresentation.annotations(pickup: pickup, destination: destination, transporting: true)
        precondition(transporting.map(\.id) == ["destination"])
        precondition(transporting.allSatisfy { $0.symbolName != "truck.box.fill" })

        let now = Date()
        func fix(_ latitude: Double, age: TimeInterval = 0, accuracy: Double = 10) -> DeviceLocationFix {
            .init(latitude: latitude, longitude: -46.6, horizontalAccuracy: accuracy, timestamp: now.addingTimeInterval(-age))
        }
        let old = fix(-23.5, age: 20), live = fix(-23.6), stale = fix(-23.7, age: 60)
        precondition(GuinchoProviderMapPresentation.currentCoordinate(fixes: [old, live], now: now)?.latitude == live.latitude)
        precondition(GuinchoProviderMapPresentation.currentCoordinate(fixes: [stale, live], now: now)?.latitude == live.latitude)
        precondition(GuinchoProviderMapPresentation.currentCoordinate(fixes: [fix(100), stale, fix(-23.8, accuracy: 150)], now: now) == nil)
        precondition(GuinchoProviderMapPresentation.currentCoordinate(fixes: [fix(-23.5, age: -60)], now: now) == nil)
        print("PASS: no duplicate truck marker; pickup hidden during transport; camera uses newest valid GPS and rejects stale/invalid fixes")
    }
}
