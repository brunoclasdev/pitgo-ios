import Foundation

struct GuinchoInspectionApprovalAlert: Decodable, Identifiable, Equatable {
    let alertID: UUID
    let appointmentID: UUID
    let versionID: UUID
    let versionNumber: Int
    let submittedAt: Date
    let createdAt: Date
    let revision: Int64
    let environmentID: String
    var id: UUID { alertID }
    enum CodingKeys: String, CodingKey {
        case revision
        case alertID = "alert_id"
        case appointmentID = "appointment_id"
        case versionID = "version_id"
        case versionNumber = "version_number"
        case submittedAt = "submitted_at"
        case createdAt = "created_at"
        case environmentID = "environment_id"
    }
}

struct GuinchoInspectionAlertPage: Decodable {
    struct Cursor: Decodable {
        let createdAt: Date
        let id: UUID
        enum CodingKeys: String, CodingKey { case id; case createdAt = "created_at" }
    }
    let items: [GuinchoInspectionApprovalAlert]
    let nextCursor: Cursor?
    enum CodingKeys: String, CodingKey { case items; case nextCursor = "next_cursor" }
}

struct GuinchoInspectionAlertResolution: Decodable {
    let outcome: String
    let alert: GuinchoInspectionApprovalAlert?
}
