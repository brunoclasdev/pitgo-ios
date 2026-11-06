import Foundation
import Supabase

final class RegistrationVerificationRepository {
    let client: SupabaseClient
    private let documentSession: URLSession
    init(client: SupabaseClient) {
        self.client = client
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        documentSession = URLSession(configuration: configuration)
    }
    deinit { documentSession.invalidateAndCancel() }

    private func documentStorage() async throws -> SupabaseStorageClient {
        let session = try await client.auth.session
        guard let base = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              let url = URL(string: base),
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_KEY") as? String else { throw URLError(.badURL) }
        return SupabaseStorageClient(configuration: StorageClientConfiguration(
            url: url.appendingPathComponent("storage/v1"),
            headers: ["Authorization": "Bearer \(session.accessToken)", "apikey": key],
            session: StorageHTTPSession(session: documentSession)
        ))
    }

    func current(_ mode: AccountType) async throws -> RegistrationCase {
        try await client.rpc("get_my_registration", params: ["p_account_type": mode.rawValue]).execute().value
    }

    func start(_ mode: AccountType, operation: UUID) async throws -> RegistrationCase {
        try await client.rpc("start_my_registration_mode", params: ["p_account_type": mode.rawValue, "p_operation_id": operation.uuidString]).execute().value
    }

    func sync(_ mode: AccountType) async throws {
        try await client.rpc("sync_my_registration_complement", params: ["p_account_type": mode.rawValue]).execute()
    }

    func command(_ name: String, registration: RegistrationCase, operation: UUID, extra: [String: AnyJSON] = [:]) async throws -> RegistrationCase {
        var params = extra
        params["p_operation_id"] = .string(operation.uuidString)
        params["p_expected_revision"] = .integer(registration.revision)
        return try await client.rpc(name, params: params).execute().value
    }

    func reserve(_ registration: RegistrationCase, kind: RegistrationDocumentKind, vehicle: UUID?, size: Int, operation: UUID) async throws -> RegistrationEvidenceReservation {
        let params: [String: AnyJSON] = [
            "p_submission_id": .string(registration.submission_id!.uuidString),
            "p_kind": .string(kind.rawValue), "p_vehicle_reference_id": vehicle.map { .string($0.uuidString) } ?? .null,
            "p_mime_type": .string("image/jpeg"), "p_byte_size": .integer(size),
            "p_operation_id": .string(operation.uuidString), "p_expected_revision": .integer(registration.revision)
        ]
        return try await client.rpc("reserve_my_registration_evidence", params: params).execute().value
    }

    func upload(_ reservation: RegistrationEvidenceReservation, bytes: Data) async throws {
        do {
            let storage = try await documentStorage()
            try await storage.from("registration-documents").upload(reservation.object_path, data: bytes, options: FileOptions(contentType: "image/jpeg", upsert: false))
        } catch let error as StorageError where error.statusCode == "409" || error.error == "Duplicate" {
            // An immutable object may already exist after a lost response. Confirmation checks its bytes.
        }
    }

    func confirm(_ reservation: RegistrationEvidenceReservation, operation: UUID) async throws {
        let body: [String: AnyJSON] = ["evidence_id": .string(reservation.evidence_id.uuidString), "operation_id": .string(operation.uuidString), "expected_revision": .integer(reservation.revision)]
        try await client.functions.invoke("registration-evidence-confirm", options: FunctionInvokeOptions(body: body))
    }

    func photo(_ path: String) async throws -> Data {
        let storage = try await documentStorage()
        return try await storage.from("registration-documents").download(path: path)
    }
}
