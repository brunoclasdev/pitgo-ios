import Foundation

@main struct GuinchoInspectionCaptureRegression {
    static let appointmentID = UUID(), versionID = UUID(), photoID = UUID()
    static func document(_ revision: Int64, closed: Bool = false, version: UUID = versionID) throws -> GuinchoInspectionDocument {
        let values: [String: Any] = ["appointment_id": appointmentID.uuidString, "revision": revision, "is_provider": true,
            "closed": closed, "required_photos": [], "named_photos": [], "pending_photos": [],
            "summary": ["required": true, "state": "DRAFT", "current_version_id": version.uuidString,
                        "required_points_ready": 0, "photo_count": 0, "allowed_actions": ["CAPTURE"]]]
        return try JSONDecoder().decode(GuinchoInspectionDocument.self, from: JSONSerialization.data(withJSONObject: values))
    }
    static func photo(ready: Bool = false, abandoned: Bool = false, invalidPath: Bool = false) throws -> GuinchoInspectionPhoto {
        let path = "\(appointmentID.uuidString.lowercased())/\(photoID.uuidString.lowercased())"
        var values: [String: Any] = ["id": photoID.uuidString, "appointment_id": appointmentID.uuidString,
            "reserved_for_version_id": versionID.uuidString, "point": "FRONT", "captured_at": 0,
            "captured_by_name": "Guincheiro", "photo_order": 1, "byte_size": 200, "thumbnail_byte_size": 50,
            "object_path": invalidPath ? "wrong/photo.jpg" : path + ".jpg", "thumbnail_object_path": path + ".thumb.jpg",
            "state": ready ? "READY" : "RESERVED"]
        if ready { values["saved_at"] = 1 }
        if abandoned { values["abandoned_at"] = 1 }
        return try JSONDecoder().decode(GuinchoInspectionPhoto.self, from: JSONSerialization.data(withJSONObject: values))
    }
    static func main() async throws {
        var reads = 0, uploads = 0
        var reserves: [Int64] = [], confirms: [Int64] = []
        let reserved = try photo()
        let pipeline = GuinchoInspectionCapturePipeline(fetchDocument: {
            reads += 1
            return try document(Int64(reads))
        }, reserve: { doc in
            reserves.append(doc.revision)
            return .init(outcome: reserves.count == 1 ? "REVISION_CONFLICT" : "APPLIED", inspection: doc, photo: reserved)
        }, upload: { photo in
            precondition(photo.id == photoID); uploads += 1
        }, confirm: { doc, photo in
            confirms.append(doc.revision)
            precondition(photo.id == photoID)
            return .init(outcome: confirms.count == 1 ? "REVISION_CONFLICT" : "APPLIED", inspection: doc, photo: nil)
        })
        _ = try await pipeline.save(versionID: versionID)
        precondition(reserves == [1, 2] && confirms == [3, 4] && uploads == 1)

        var replayUploads = 0, replayConfirms = 0
        let ready = try photo(ready: true)
        let replay = GuinchoInspectionCapturePipeline(fetchDocument: { try document(5, closed: true) },
            reserve: { .init(outcome: "EXISTING", inspection: $0, photo: ready) },
            upload: { _ in replayUploads += 1 }, confirm: { doc, _ in replayConfirms += 1; return .init(outcome: "APPLIED", inspection: doc, photo: nil) })
        let recovered = try await replay.save(versionID: versionID)
        precondition(recovered.closed && replayUploads == 0 && replayConfirms == 0)

        for badPhoto in [try photo(abandoned: true), try photo(invalidPath: true)] {
            let bad = GuinchoInspectionCapturePipeline(fetchDocument: { try document(1) },
                reserve: { .init(outcome: "APPLIED", inspection: $0, photo: badPhoto) },
                upload: { _ in preconditionFailure("Invalid reservation uploaded") },
                confirm: { _, _ in preconditionFailure("Invalid reservation confirmed") })
            do { _ = try await bad.save(versionID: versionID); preconditionFailure("Invalid reservation accepted") }
            catch let error as GuinchoInspectionError { precondition([.context, .contract].contains(error)) }
        }
        let wrongVersion = GuinchoInspectionCapturePipeline(fetchDocument: { try document(1, version: UUID()) },
            reserve: { .init(outcome: "APPLIED", inspection: $0, photo: reserved) },
            upload: { _ in preconditionFailure("Closed version uploaded") },
            confirm: { _, _ in preconditionFailure("Closed version confirmed") })
        do { _ = try await wrongVersion.save(versionID: versionID); preconditionFailure("Version switch accepted") }
        catch GuinchoInspectionError.closed {}
        print("PASS: fresh revisions for reserve/confirm; READY replay skips upload even after closure; abandoned/path/version mismatches block upload")
    }
}
