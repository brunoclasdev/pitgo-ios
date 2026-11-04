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
            )), decoder: GuinchoRouteResponseDecoder.make())
        } catch let error as FunctionsError {
            if case let .httpError(status, data) = error {
                let body = try? JSONDecoder().decode(RouteErrorBody.self, from: data)
                let fallback: String
                switch status {
                case 401: fallback = "AUTH_REQUIRED"
                case 403: fallback = "NOT_PARTICIPANT"
                case 400: fallback = "INVALID_REQUEST"
                case 409: fallback = "APPOINTMENT_NOT_TRACKABLE"
                case 429: fallback = "RATE_LIMITED"
                case 504: fallback = "ROUTER_TIMEOUT"
                default: fallback = "SERVICE_UNAVAILABLE"
                }
                throw GuinchoRouteFailure(status: status, code: body?.code ?? fallback,
                                          retryable: body?.retryable ?? true, retryAfterMs: body?.retryAfterMs)
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
