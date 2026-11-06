import CoreLocation
import Foundation

enum GuinchoProviderMapPresentation {
    /// The live truck position is rendered by the map's user-location layer only.
    static func annotations(pickup: CLLocationCoordinate2D, destination: CLLocationCoordinate2D,
                            transporting: Bool) -> [PitGoMapAnnotationItem] {
        var items: [PitGoMapAnnotationItem] = []
        if !transporting {
            items.append(.init(id: "pickup", coordinate: pickup, title: "Local de retirada", symbolName: "mappin.circle.fill"))
        }
        items.append(.init(id: "destination", coordinate: destination, title: "Destino contratado", symbolName: "flag.fill"))
        return items
    }

    /// Camera bounds may use a recent fix, but a saved route origin is never a live position.
    static func currentCoordinate(fixes: [DeviceLocationFix?], now: Date = Date()) -> CLLocationCoordinate2D? {
        fixes.compactMap { $0 }.filter {
            CLLocationCoordinate2DIsValid(.init(latitude: $0.latitude, longitude: $0.longitude))
                && $0.horizontalAccuracy > 0 && $0.horizontalAccuracy <= 100
                && now.timeIntervalSince($0.timestamp) <= 30 && $0.timestamp.timeIntervalSince(now) <= 5
        }.max { $0.timestamp < $1.timestamp }.map {
            .init(latitude: $0.latitude, longitude: $0.longitude)
        }
    }
}
