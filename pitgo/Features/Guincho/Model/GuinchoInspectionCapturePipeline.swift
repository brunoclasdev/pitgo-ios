import Foundation

enum GuinchoInspectionError: Error, Equatable {
    case closed, invalidImage, reasonRequired, revisionConflict, contract
    case context, sessionExpired, forbidden, incomplete, serviceUnavailable
}

/// Replays the same operation before checking editability, just like Android's pending pipeline.
struct GuinchoInspectionCapturePipeline {
    let fetchDocument: () async throws -> GuinchoInspectionDocument
    let reserve: (GuinchoInspectionDocument) async throws -> GuinchoInspectionMutationResult
    let upload: (GuinchoInspectionPhoto) async throws -> Void
    let confirm: (GuinchoInspectionDocument, GuinchoInspectionPhoto) async throws -> GuinchoInspectionMutationResult

    func save(versionID: UUID) async throws -> GuinchoInspectionDocument {
        let reservation = try await withFreshRevision(reserve)
        guard let photo = reservation.photo, photo.isValid else { throw GuinchoInspectionError.contract }
        // A previous confirmation may have succeeded even when its response was lost.
        if photo.state == .ready { return reservation.inspection }
        guard photo.abandonedAt == nil else { throw GuinchoInspectionError.context }
        guard !reservation.inspection.closed, reservation.inspection.isProvider,
              reservation.inspection.summary.currentVersionID == versionID,
              reservation.inspection.summary.allowedActions.contains("CAPTURE") else { throw GuinchoInspectionError.closed }
        try await upload(photo)
        // Upload can outlive another mutation. Confirm against a freshly read revision.
        return try await withFreshRevision { document in try await confirm(document, photo) }.inspection
    }

    private func withFreshRevision(
        _ operation: (GuinchoInspectionDocument) async throws -> GuinchoInspectionMutationResult
    ) async throws -> GuinchoInspectionMutationResult {
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let document = try await fetchDocument()
            do {
                let response = try await operation(document)
                switch response.outcome {
                case "APPLIED", "EXISTING": return response
                case "REVISION_CONFLICT": throw GuinchoInspectionError.revisionConflict
                default: throw GuinchoInspectionError.contract
                }
            } catch GuinchoInspectionError.revisionConflict {
                if attempt == 2 { throw GuinchoInspectionError.revisionConflict }
            }
        }
        throw GuinchoInspectionError.revisionConflict
    }
}
