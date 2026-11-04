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
        guard photo.isValid else { throw GuinchoInspectionError.invalidImage }
        let data = try await client.storage.from(bucket).download(path: photo.objectPath)
        guard Int64(data.count) == photo.byteSize else { throw GuinchoInspectionError.invalidImage }
        return data
    }

    func downloadThumbnail(_ photo: GuinchoInspectionPhoto) async throws -> Data {
        guard photo.isValid else { throw GuinchoInspectionError.invalidImage }
        let data = try await client.storage.from(bucket).download(path: photo.thumbnailObjectPath ?? photo.objectPath)
        guard Int64(data.count) == (photo.thumbnailByteSize ?? photo.byteSize) else { throw GuinchoInspectionError.invalidImage }
        return data
    }

    func capture(
        jpegData: Data, thumbnailData: Data, point: GuinchoInspectionPoint, detailPoint: String? = nil, caption: String? = nil,
        versionID: UUID, replaces: UUID? = nil, capturedAt: Date, reserveOperationID: UUID, confirmOperationID: UUID,
        document: GuinchoInspectionDocument
    ) async throws -> GuinchoInspectionDocument {
        guard (1...GuinchoInspectionImageEncoder.originalByteLimit).contains(jpegData.count),
              (1...GuinchoInspectionImageEncoder.thumbnailByteLimit).contains(thumbnailData.count) else {
            throw GuinchoInspectionError.invalidImage
        }
        let accountID = try await currentAccountID()
        let pipeline = GuinchoInspectionCapturePipeline(
            fetchDocument: {
                try await self.ensureAccount(accountID)
                return try await self.document(appointmentID: document.appointmentID)
            },
            reserve: { latest in
                // Older iOS manifests stored whole seconds. The same operation's server row
                // is authoritative when recovering a reservation created before this fix.
                let knownPhoto = (latest.pendingPhotos + latest.requiredPhotos + latest.namedPhotos)
                    .first { $0.reserveOperationID == reserveOperationID }
                let reservationCapturedAt = knownPhoto?.capturedAt ?? capturedAt
                let result = try await self.mutate("prepare_guincho_inspection_photo_v2", PrepareInspectionPhotoParams(
                    p_appointment_id: latest.appointmentID, p_expected_revision: latest.revision, p_operation_id: reserveOperationID,
                    p_version_id: versionID, p_point: point.rawValue, p_captured_at: reservationCapturedAt,
                    p_byte_size: Int64(jpegData.count), p_thumbnail_byte_size: Int64(thumbnailData.count),
                    p_caption: caption?.trimmingCharacters(in: .whitespacesAndNewlines), p_replaces_photo_id: replaces,
                    p_detail_point: detailPoint
                ))
                guard let photo = result.photo, photo.appointmentID == document.appointmentID,
                      photo.reservedVersionID == versionID, photo.point == point, photo.detailPoint == detailPoint,
                      photo.reserveOperationID == nil || photo.reserveOperationID == reserveOperationID,
                      photo.byteSize == Int64(jpegData.count), photo.thumbnailByteSize == Int64(thumbnailData.count) else {
                    throw GuinchoInspectionError.context
                }
                return result
            },
            upload: { photo in
                try await self.ensureAccount(accountID)
                try await self.upload(path: photo.objectPath, bytes: jpegData)
                guard let path = photo.thumbnailObjectPath else { throw GuinchoInspectionError.contract }
                try await self.ensureAccount(accountID)
                try await self.upload(path: path, bytes: thumbnailData)
            },
            confirm: { latest, photo in
                try await self.mutate("confirm_guincho_inspection_photo_v2", InspectionPhotoCommandParams(
                    p_appointment_id: latest.appointmentID, p_expected_revision: latest.revision,
                    p_operation_id: confirmOperationID, p_photo_id: photo.id
                ))
            }
        )
        let result = try await pipeline.save(versionID: versionID)
        try await ensureAccount(accountID)
        return result
    }

    private func ensureAccount(_ accountID: UUID) async throws {
        guard try await currentAccountID() == accountID else { throw GuinchoInspectionError.sessionExpired }
        try Task.checkCancellation()
    }

    private func upload(path: String, bytes: Data) async throws {
        do {
            try await client.storage.from(bucket).upload(path, data: bytes,
                options: FileOptions(contentType: "image/jpeg", upsert: false))
        } catch let error as StorageError {
            let duplicateCodes = ["duplicate", "resourcealreadyexists", "keyalreadyexists"]
            guard error.statusCode == "409" || duplicateCodes.contains(error.error?.lowercased() ?? "") else { throw error }
            try await ensureRemoteFile(path: path, bytes: bytes)
        }
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
            if result.outcome == "REVISION_CONFLICT" { throw GuinchoInspectionError.revisionConflict }
            throw GuinchoInspectionError.contract
        }
        return result
    }

    private func ensureRemoteFile(path: String, bytes: Data) async throws {
        let remote = try await client.storage.from(bucket).download(path: path)
        guard SHA256.hash(data: remote) == SHA256.hash(data: bytes) else {
            throw GuinchoInspectionError.invalidImage
        }
    }
}
