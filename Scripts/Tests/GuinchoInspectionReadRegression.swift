import Foundation

@main struct GuinchoInspectionReadRegression {
    static func main() throws {
        let appointmentID = UUID().uuidString, versionID = UUID().uuidString
        // get_guincho_inspection_v2 embeds table rows; only the paginated endpoint adds `sent`.
        let photo: [String: Any] = [
            "id": UUID().uuidString, "appointment_id": appointmentID, "reserved_for_version_id": versionID,
            "point": "FRONT", "captured_at": "2026-10-23T15:00:00Z", "captured_by_name": "Guincheiro",
            "saved_at": "2026-10-23T15:00:01Z", "photo_order": 1, "object_path": "appointment/photo.jpg",
            "byte_size": 1000, "state": "READY"
        ]
        let document: [String: Any] = [
            "appointment_id": appointmentID, "revision": 7, "is_provider": false, "closed": false,
            "summary": ["required": true, "state": "SUBMITTED", "current_version_id": versionID,
                        "current_version_number": 1, "required_points_ready": 4, "photo_count": 4,
                        "allowed_actions": ["OPEN_INSPECTION", "APPROVE", "REQUEST_CORRECTION"]],
            "current_version": ["id": versionID, "version_number": 1, "state": "SUBMITTED",
                                "created_at": "2026-10-23T15:00:00Z", "submitted_at": "2026-10-23T15:01:00Z"],
            "required_photos": [photo], "named_photos": [photo], "pending_photos": []
        ]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GuinchoInspectionDocument.self, from: JSONSerialization.data(withJSONObject: document))
        precondition(decoded.requiredPhotos.count == 1 && decoded.namedPhotos.count == 1)
        precondition(decoded.summary.allowedActions.contains("APPROVE"))
        var paginatedPhoto = photo
        paginatedPhoto["sent"] = true
        let page = try decoder.decode(GuinchoInspectionPhotoPage.self, from: JSONSerialization.data(withJSONObject: [
            "items": [paginatedPhoto], "has_more": false
        ]))
        precondition(page.items.first?.id == decoded.requiredPhotos.first?.id)
        print("PASS: submitted inspection opens with embedded raw photos and paginated photo metadata")
    }
}
