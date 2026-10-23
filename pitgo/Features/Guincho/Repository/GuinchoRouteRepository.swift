import Foundation
import Supabase

private struct RouteSnapshotParams: Encodable { let p_appointment_id: UUID }

final class GuinchoRouteRepository {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }

    func snapshot(appointmentID: UUID) async throws -> GuinchoRoutePayload {
        try await client.rpc("get_guincho_route_snapshot", params: RouteSnapshotParams(p_appointment_id: appointmentID)).execute().value
    }

    func refresh(appointmentID: UUID, reason: GuinchoRouteReason, knownVersion: Int64) async throws -> GuinchoRoutePayload {
        do {
            return try await client.functions.invoke("guincho-route", options: FunctionInvokeOptions(body: GuinchoRouteRequest(
                appointmentID: appointmentID, reason: reason, knownRouteVersion: knownVersion
            )))
        } catch let error as FunctionsError {
            if case let .httpError(status, data) = error {
                let body = try? JSONDecoder().decode(RouteErrorBody.self, from: data)
                throw GuinchoRouteFailure(status: status, code: body?.code ?? "SERVICE_UNAVAILABLE",
                                          retryable: body?.retryable ?? (status >= 500), retryAfterMs: body?.retryAfterMs)
            }
            throw error
        }
    }
}

private struct RouteErrorBody: Decodable {
    let code: String?
    let retryable: Bool?
    let retryAfterMs: Int?
    enum CodingKeys: String, CodingKey { case code, retryable; case retryAfterMs = "retry_after_ms" }
}

struct GuinchoRouteFailure: Error {
    let status: Int
    let code: String
    let retryable: Bool
    let retryAfterMs: Int?
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
        guard let appointmentID, let routeVersion, let providerLocationRevision,
              let providerLocationPublishedAt, let origin, let destination, let geometry,
              let distanceMeters, let generatedAt else { return nil }
        return GuinchoRouteSnapshot(status: status, outcome: outcome, appointmentID: appointmentID,
                                    routeVersion: routeVersion, providerLocationRevision: providerLocationRevision,
                                    providerLocationPublishedAt: providerLocationPublishedAt, origin: origin,
                                    destination: destination, geometry: geometry, distanceMeters: distanceMeters,
                                    generatedAt: generatedAt, reused: reused)
    }
}
