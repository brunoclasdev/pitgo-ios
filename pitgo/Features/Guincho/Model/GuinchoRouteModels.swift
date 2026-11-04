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
        enum CodingKeys: String, CodingKey {
            case latitude, longitude
            case accuracyM = "accuracy_m"
            case capturedAt = "captured_at"
            case publishedAt = "published_at"
        }
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
        geometry.coordinates.compactMap {
            guard $0.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])
        }
    }

    func isValid(for appointmentID: UUID, expectedDestination: Point?) -> Bool {
        guard self.appointmentID == appointmentID, routeVersion > 0, providerLocationRevision > 0,
              distanceMeters >= 0, distanceMeters <= 2_000_000, origin.point.isValid, destination.isValid,
              origin.accuracyM > 0, origin.accuracyM <= 100, origin.capturedAt.timeIntervalSince1970 > 0,
              origin.publishedAt == providerLocationPublishedAt, generatedAt.timeIntervalSince1970 > 0,
              geometry.type == "LineString",
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

struct GuinchoRouteFailure: Error {
    let status: Int
    let code: String
    let retryable: Bool
    let retryAfterMs: Int?

    var accessDenied: Bool { ["AUTH_REQUIRED", "NOT_PARTICIPANT", "APPOINTMENT_NOT_TRACKABLE"].contains(code) }
    var shouldRetry: Bool { retryable && !accessDenied && code != "INVALID_REQUEST" && code != "CONTRACT" }
    var message: String {
        switch code {
        case "LOCATION_NOT_READY", "LOCATION_UNCERTAIN": return "Aguardando uma localização precisa para traçar o percurso."
        case "AUTH_REQUIRED": return "Sua sessão expirou. Entre novamente para carregar o percurso."
        case "NOT_PARTICIPANT", "APPOINTMENT_NOT_TRACKABLE": return "O atendimento não permite consultar este percurso. Atualize a solicitação."
        case "CONTRACT", "INVALID_REQUEST": return "Não foi possível interpretar o percurso. Tente novamente."
        default: return "O trajeto foi iniciado. Não foi possível atualizar o percurso agora; tentaremos novamente."
        }
    }
}

struct GuinchoRoutePayload: Decodable {
    let status: String?
    let outcome: String?
    let code: String?
    let retryAfterMs: Int?
    let retryable: Bool?
    let appointmentID: UUID?
    let routeVersion: Int64?
    let providerLocationRevision: Int64?
    let providerLocationPublishedAt: Date?
    let origin: GuinchoRouteSnapshot.Origin?
    let destination: GuinchoRouteSnapshot.Point?
    let geometry: GuinchoRouteSnapshot.Geometry?
    let distanceMeters: Int?
    let generatedAt: Date?
    let reused: Bool?
    enum CodingKeys: String, CodingKey {
        case status, outcome, code, origin, destination, geometry, retryable, reused
        case appointmentID = "appointment_id"
        case routeVersion = "route_version"
        case providerLocationRevision = "provider_location_revision"
        case providerLocationPublishedAt = "provider_location_published_at"
        case distanceMeters = "distance_meters"
        case generatedAt = "generated_at"
        case retryAfterMs = "retry_after_ms"
    }

    func snapshot() -> GuinchoRouteSnapshot? {
        guard status == "ROUTE" || (status == nil && outcome == "FOUND"),
              let appointmentID, let routeVersion, let providerLocationRevision,
              let providerLocationPublishedAt, let origin, let destination, let geometry,
              let distanceMeters, let generatedAt else { return nil }
        return GuinchoRouteSnapshot(status: status, outcome: outcome, appointmentID: appointmentID,
                                    routeVersion: routeVersion, providerLocationRevision: providerLocationRevision,
                                    providerLocationPublishedAt: providerLocationPublishedAt, origin: origin,
                                    destination: destination, geometry: geometry, distanceMeters: distanceMeters,
                                    generatedAt: generatedAt, reused: reused)
    }
}

/// Edge Functions use ISO8601 strings, while their SDK default decoder expects numeric dates.
enum GuinchoRouteResponseDecoder {
    static func make() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid route timestamp")
        }
        return decoder
    }
}
