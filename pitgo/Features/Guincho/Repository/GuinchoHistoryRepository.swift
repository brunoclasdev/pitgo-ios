import Foundation
import Supabase

private struct ListServiceAppointmentsParams: Encodable {
    let p_before: Date?
    let p_before_id: UUID?
    let p_limit: Int
}

final class GuinchoHistoryRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) { self.client = client }

    func list(before: Date?, beforeID: UUID?) async throws -> [MobileDispatchSnapshot] {
        try await client
            .rpc("list_my_service_appointments", params: ListServiceAppointmentsParams(
                p_before: before, p_before_id: beforeID, p_limit: 20
            ))
            .execute()
            .value
    }
}
