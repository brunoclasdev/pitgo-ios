import CryptoKit
import Foundation
import Supabase

private struct AppointmentIDParams: Encodable { let p_appointment_id: UUID }
private struct InspectionPageParams: Encodable {
    let p_appointment_id: UUID
    let p_version_id: UUID?
    let p_after_order: Int64?
    let p_after_id: UUID?
    let p_limit: Int
}
private struct InspectionVersionsParams: Encodable {
    let p_appointment_id: UUID
    let p_before_version: Int?
    let p_limit: Int
}
private struct PrepareInspectionPhotoParams: Encodable {
    let p_appointment_id: UUID
    let p_expected_revision: Int64
    let p_operation_id: UUID
    let p_version_id: UUID
    let p_point: String
    let p_captured_at: Date
    let p_byte_size: Int64
    let p_thumbnail_byte_size: Int64
    let p_caption: String?
    let p_replaces_photo_id: UUID?
    let p_detail_point: String?
}
private struct InspectionPhotoCommandParams: Encodable {
    let p_appointment_id: UUID
    let p_expected_revision: Int64
    let p_operation_id: UUID
    let p_photo_id: UUID
}
private struct SubmitInspectionParams: Encodable {
    let p_appointment_id: UUID
    let p_expected_revision: Int64
    let p_operation_id: UUID
    let p_version_id: UUID
}
private struct DecideInspectionParams: Encodable {
    let p_appointment_id: UUID
    let p_expected_revision: Int64
    let p_operation_id: UUID
    let p_version_id: UUID
    let p_decision: String
    let p_reason: String?
}
private struct BeginCorrectionParams: Encodable {
    let p_appointment_id: UUID
    let p_expected_revision: Int64
    let p_parent_version_id: UUID
}

final class GuinchoInspectionRepository {
    private let client: SupabaseClient
    private let bucket = "guincho-inspections"

    init(client: SupabaseClient) { self.client = client }

    func currentAccountID() async throws -> UUID { try await client.auth.session.user.id }

    func document(appointmentID: UUID) async throws -> GuinchoInspectionDocument {
        try await client.rpc("get_guincho_inspection_v2", params: AppointmentIDParams(p_appointment_id: appointmentID))
            .execute().value
    }

    func photos(appointmentID: UUID, versionID: UUID? = nil, afterOrder: Int64? = nil, afterID: UUID? = nil) async throws -> GuinchoInspectionPhotoPage {
        try await client.rpc("list_guincho_inspection_photos_v2", params: InspectionPageParams(
            p_appointment_id: appointmentID, p_version_id: versionID, p_after_order: afterOrder, p_after_id: afterID, p_limit: 20
        )).execute().value
    }

    func versions(appointmentID: UUID, before: Int? = nil) async throws -> GuinchoInspectionVersionPage {
        try await client.rpc("list_guincho_inspection_versions", params: InspectionVersionsParams(
            p_appointment_id: appointmentID, p_before_version: before, p_limit: 10
        )).execute().value
    }

    func download(_ photo: GuinchoInspectionPhoto) async throws -> Data {
        try await client.storage.from(bucket).download(path: photo.objectPath)
    }

    func downloadThumbnail(_ photo: GuinchoInspectionPhoto) async throws -> Data {
        try await client.storage.from(bucket).download(path: photo.thumbnailObjectPath ?? photo.objectPath)
    }

    func capture(
        jpegData: Data, thumbnailData: Data, point: GuinchoInspectionPoint, detailPoint: String? = nil, caption: String? = nil,
        versionID: UUID, replaces: UUID? = nil, capturedAt: Date, reserveOperationID: UUID, confirmOperationID: UUID,
        document: GuinchoInspectionDocument
    ) async throws -> GuinchoInspectionDocument {
        guard !document.closed else { throw GuinchoInspectionError.closed }
        guard (1...5_242_880).contains(jpegData.count), (1...262_144).contains(thumbnailData.count) else {
            throw GuinchoInspectionError.invalidImage
        }
        let reservation: GuinchoInspectionMutationResult = try await mutate("prepare_guincho_inspection_photo_v2", PrepareInspectionPhotoParams(
            p_appointment_id: document.appointmentID, p_expected_revision: document.revision, p_operation_id: reserveOperationID,
            p_version_id: versionID, p_point: point.rawValue, p_captured_at: capturedAt,
            p_byte_size: Int64(jpegData.count), p_thumbnail_byte_size: Int64(thumbnailData.count), p_caption: caption, p_replaces_photo_id: replaces,
            p_detail_point: detailPoint
        ))
        guard let photo = reservation.photo else { throw GuinchoInspectionError.contract }
        do {
            try await client.storage.from(bucket).upload(photo.objectPath, data: jpegData, options: FileOptions(contentType: "image/jpeg", upsert: false))
        } catch let error as StorageError {
            let duplicate = error.statusCode == "409" || error.error?.localizedCaseInsensitiveContains("duplicate") == true
            guard duplicate else { throw error }
            try await ensureRemoteFile(path: photo.objectPath, bytes: jpegData)
        }
        guard let thumbPath = photo.thumbnailObjectPath else { throw GuinchoInspectionError.contract }
        do {
            try await client.storage.from(bucket).upload(thumbPath, data: thumbnailData, options: FileOptions(contentType: "image/jpeg", upsert: false))
        } catch let error as StorageError {
            let duplicate = error.statusCode == "409" || error.error?.localizedCaseInsensitiveContains("duplicate") == true
            guard duplicate else { throw error }
            try await ensureRemoteFile(path: thumbPath, bytes: thumbnailData)
        }
        let latest = reservation.inspection
        let confirmed: GuinchoInspectionMutationResult = try await mutate("confirm_guincho_inspection_photo_v2", InspectionPhotoCommandParams(
            p_appointment_id: latest.appointmentID, p_expected_revision: latest.revision, p_operation_id: confirmOperationID,
            p_photo_id: photo.id
        ))
        return confirmed.inspection
    }

    func submit(_ document: GuinchoInspectionDocument, operationID: UUID, versionID: UUID) async throws -> GuinchoInspectionMutationResult {
        let result: GuinchoInspectionMutationResult = try await client.rpc("submit_guincho_inspection", params: SubmitInspectionParams(
            p_appointment_id: document.appointmentID, p_expected_revision: document.revision, p_operation_id: operationID,
            p_version_id: versionID
        )).execute().value
        guard ["APPLIED", "EXISTING", "REVISION_CONFLICT"].contains(result.outcome) else { throw GuinchoInspectionError.contract }
        return result
    }

    func decide(_ document: GuinchoInspectionDocument, approve: Bool, reason: String = "") async throws -> GuinchoInspectionDocument {
        guard let versionID = document.summary.currentVersionID else { throw GuinchoInspectionError.contract }
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard approve || !trimmed.isEmpty else { throw GuinchoInspectionError.reasonRequired }
        return try await mutate("decide_guincho_inspection", DecideInspectionParams(
            p_appointment_id: document.appointmentID, p_expected_revision: document.revision, p_operation_id: UUID(),
            p_version_id: versionID, p_decision: approve ? "APPROVE" : "REQUEST_CORRECTION",
            p_reason: approve ? nil : trimmed
        )).inspection
    }

    func discardPendingPhoto(_ document: GuinchoInspectionDocument, photoID: UUID, operationID: UUID) async throws -> GuinchoInspectionDocument {
        guard !document.closed, document.summary.state == .draft,
              document.pendingPhotos.contains(where: { $0.id == photoID }) else {
            throw GuinchoInspectionError.closed
        }
        return try await mutate("discard_guincho_inspection_photo", InspectionPhotoCommandParams(
            p_appointment_id: document.appointmentID,
            p_expected_revision: document.revision,
            p_operation_id: operationID,
            p_photo_id: photoID
        )).inspection
    }

    func beginCorrection(_ document: GuinchoInspectionDocument) async throws -> GuinchoInspectionDocument {
        guard let versionID = document.summary.currentVersionID else { throw GuinchoInspectionError.contract }
        return try await mutate("begin_guincho_inspection_correction", BeginCorrectionParams(
            p_appointment_id: document.appointmentID, p_expected_revision: document.revision, p_parent_version_id: versionID
        )).inspection
    }

    private func mutate<Params: Encodable>(_ rpc: String, _ params: Params) async throws -> GuinchoInspectionMutationResult {
        let result: GuinchoInspectionMutationResult = try await client.rpc(rpc, params: params).execute().value
        guard result.outcome == "APPLIED" || result.outcome == "EXISTING" else {
            throw GuinchoInspectionError.revisionConflict
        }
        return result
    }

    private func ensureRemoteFile(path: String, bytes: Data) async throws {
        let remote = try await client.storage.from(bucket).download(path: path)
        guard SHA256.hash(data: remote).description == SHA256.hash(data: bytes).description else {
            throw GuinchoInspectionError.invalidImage
        }
    }
}

enum GuinchoInspectionError: Error {
    case closed, invalidImage, reasonRequired, revisionConflict, contract
}
