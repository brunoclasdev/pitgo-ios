import Foundation
import Supabase

private struct ListInspectionAlertsParams: Encodable {
    let p_environment_id: String
    let p_after_created_at: String?
    let p_after_id: UUID?
    let p_limit: Int
}
private struct ResolveInspectionAlertParams: Encodable { let p_alert_id: UUID; let p_environment_id: String }

final class GuinchoInspectionAlertRepository {
    private let client: SupabaseClient
    init(client: SupabaseClient) { self.client = client }

    func list(environmentID: String, after: GuinchoInspectionAlertPage.Cursor? = nil) async throws -> GuinchoInspectionAlertPage {
        try await client.rpc("list_my_pending_guincho_inspection_approvals", params: ListInspectionAlertsParams(
            p_environment_id: environmentID, p_after_created_at: after.map { Self.timestamp($0.createdAt) },
            p_after_id: after?.id, p_limit: 100
        )).execute().value
    }

    func resolve(alertID: UUID, environmentID: String) async throws -> GuinchoInspectionAlertResolution {
        try await client.rpc("get_my_guincho_inspection_alert", params: ResolveInspectionAlertParams(
            p_alert_id: alertID, p_environment_id: environmentID
        )).execute().value
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
