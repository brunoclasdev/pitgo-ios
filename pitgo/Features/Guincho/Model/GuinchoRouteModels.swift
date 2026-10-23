import CoreLocation
import Foundation

struct GuinchoRouteSnapshot: Decodable, Equatable {
    struct Point: Decodable, Equatable {
        let latitude: Double
        let longitude: Double
        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
        var isValid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
    }
    struct Geometry: Decodable, Equatable {
        let type: String
        let coordinates: [[Double]]
    }
    let status: String?
    let outcome: String?
    let appointmentID: UUID
    let routeVersion: Int64
    let providerLocationRevision: Int64
    let providerLocationPublishedAt: Date
    let origin: Origin
    let destination: Point
    let geometry: Geometry
    let distanceMeters: Int
    let generatedAt: Date
    let reused: Bool?

    struct Origin: Decodable, Equatable {
        let latitude: Double
        let longitude: Double
        let accuracyM: Double
        let capturedAt: Date
        let publishedAt: Date
        var point: Point { .init(latitude: latitude, longitude: longitude) }
    }

    enum CodingKeys: String, CodingKey {
        case status, outcome, geometry, origin, destination, reused
        case appointmentID = "appointment_id"
        case routeVersion = "route_version"
        case providerLocationRevision = "provider_location_revision"
        case providerLocationPublishedAt = "provider_location_published_at"
        case distanceMeters = "distance_meters"
        case generatedAt = "generated_at"
    }

    var coordinates: [CLLocationCoordinate2D] {
        geometry.coordinates.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
    }

    func isValid(for appointmentID: UUID, expectedDestination: Point?) -> Bool {
        guard self.appointmentID == appointmentID, routeVersion > 0, providerLocationRevision > 0,
              distanceMeters >= 0, distanceMeters <= 2_000_000, origin.point.isValid, destination.isValid,
              origin.accuracyM > 0, origin.accuracyM <= 100, geometry.type == "LineString",
              (2...10_000).contains(geometry.coordinates.count),
              geometry.coordinates.allSatisfy({ $0.count == 2 && $0.allSatisfy { $0.isFinite } && abs($0[0]) <= 180 && abs($0[1]) <= 90 }) else { return false }
        if let expectedDestination, (destination.latitude != expectedDestination.latitude || destination.longitude != expectedDestination.longitude) { return false }
        return true
    }
}

enum GuinchoRouteReason: String, Encodable { case initial = "INITIAL", resume = "RESUME", deviation = "DEVIATION", retry = "RETRY" }
struct GuinchoRouteRequest: Encodable {
    let appointmentID: UUID
    let reason: GuinchoRouteReason
    let knownRouteVersion: Int64
    enum CodingKeys: String, CodingKey {
        case appointmentID = "appointment_id"
        case reason
        case knownRouteVersion = "known_route_version"
    }
}

enum GuinchoRouteUIState {
    case loading(GuinchoRouteSnapshot?)
    case ready(GuinchoRouteSnapshot)
    case waiting(GuinchoRouteSnapshot?, String)
    case unavailable(GuinchoRouteSnapshot?, String)
    case closed
}
