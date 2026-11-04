import Foundation

enum GuinchoInspectionPoint: String, Codable, CaseIterable, Identifiable {
    case front = "FRONT"
    case rear = "REAR"
    case left = "LEFT"
    case right = "RIGHT"
    case detail = "DETAIL"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .front: "Frente"
        case .rear: "Traseira"
        case .left: "Lateral esquerda"
        case .right: "Lateral direita"
        case .detail: "Detalhe / avaria"
        }
    }
    static let required: [Self] = [.front, .rear, .left, .right]
}

enum GuinchoInspectionDetailPoint: String, Codable, CaseIterable, Identifiable {
    case trunkInterior = "TRUNK_INTERIOR"
    case instrumentPanel = "INSTRUMENT_PANEL"
    case frontSeats = "FRONT_SEATS"
    case rearSeats = "REAR_SEATS"
    case fullDashboard = "FULL_DASHBOARD"
    case toolKit = "TOOL_KIT"
    case spareTire = "SPARE_TIRE"
    case frontLeftTire = "FRONT_LEFT_TIRE"
    case frontRightTire = "FRONT_RIGHT_TIRE"
    case rearRightTire = "REAR_RIGHT_TIRE"
    case rearLeftTire = "REAR_LEFT_TIRE"
    case engine = "ENGINE"
    case battery = "BATTERY"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .trunkInterior: "Interior do porta-malas"
        case .instrumentPanel: "Painel de instrumentos"
        case .frontSeats: "Bancos dianteiros"
        case .rearSeats: "Bancos traseiros"
        case .fullDashboard: "Painel completo"
        case .toolKit: "Kit de ferramentas"
        case .spareTire: "Estepe"
        case .frontLeftTire: "Pneu dianteiro esquerdo"
        case .frontRightTire: "Pneu dianteiro direito"
        case .rearRightTire: "Pneu traseiro direito"
        case .rearLeftTire: "Pneu traseiro esquerdo"
        case .engine: "Motor"
        case .battery: "Bateria"
        }
    }
}

enum GuinchoInspectionVersionState: String, Codable {
    case draft = "DRAFT"
    case submitted = "SUBMITTED"
    case correctionRequested = "CORRECTION_REQUESTED"
    case approved = "APPROVED"
}

enum GuinchoInspectionPhotoState: String, Codable { case reserved = "RESERVED", ready = "READY" }

struct GuinchoInspectionSummary: Decodable, Equatable {
    let required: Bool
    let state: GuinchoInspectionVersionState?
    let currentVersionID: UUID?
    let currentVersionNumber: Int?
    let requiredPointsReady: Int
    let photoCount: Int
    let approvedAt: Date?
    let correctionReason: String?
    let allowedActions: Set<String>

    enum CodingKeys: String, CodingKey {
        case required, state
        case currentVersionID = "current_version_id"
        case currentVersionNumber = "current_version_number"
        case requiredPointsReady = "required_points_ready"
        case photoCount = "photo_count"
        case approvedAt = "approved_at"
        case correctionReason = "correction_reason"
        case allowedActions = "allowed_actions"
    }
}

struct GuinchoInspectionVersion: Decodable, Identifiable, Equatable {
    let id: UUID
    let versionNumber: Int
    let state: GuinchoInspectionVersionState
    let createdAt: Date
    let createdByName: String?
    let submittedAt: Date?
    let decidedAt: Date?
    let decidedByName: String?
    let correctionReason: String?

    enum CodingKeys: String, CodingKey {
        case id, state
        case versionNumber = "version_number"
        case createdAt = "created_at"
        case createdByName = "created_by_name"
        case submittedAt = "submitted_at"
        case decidedAt = "decided_at"
        case decidedByName = "decided_by_name"
        case correctionReason = "correction_reason"
    }
}

struct GuinchoInspectionPhoto: Decodable, Identifiable, Equatable {
    let id: UUID
    let appointmentID: UUID
    let reservedVersionID: UUID
    let point: GuinchoInspectionPoint
    let detailPoint: String?
    let caption: String?
    let capturedAt: Date
    let capturedByName: String
    let savedAt: Date?
    let order: Int64
    let objectPath: String
    let byteSize: Int64
    let state: GuinchoInspectionPhotoState
    let thumbnailObjectPath: String?
    let thumbnailByteSize: Int64?
    let abandonedAt: Date?
    let reserveOperationID: UUID?

    var isValid: Bool {
        let prefix = "\(appointmentID.uuidString.lowercased())/\(id.uuidString.lowercased())"
        guard objectPath == prefix + ".jpg", (1...5_242_880).contains(byteSize),
              state != .ready || (savedAt != nil && abandonedAt == nil),
              detailPoint == nil || point == .detail else { return false }
        if thumbnailObjectPath == nil { return thumbnailByteSize == nil }
        return thumbnailObjectPath == prefix + ".thumb.jpg" && thumbnailByteSize.map { (1...262_144).contains($0) } == true
    }

    enum CodingKeys: String, CodingKey {
        case id, point, caption, state
        case appointmentID = "appointment_id"
        case reservedVersionID = "reserved_for_version_id"
        case detailPoint = "detail_point"
        case capturedAt = "captured_at"
        case capturedByName = "captured_by_name"
        case savedAt = "saved_at"
        case order = "photo_order"
        case objectPath = "object_path"
        case byteSize = "byte_size"
        case thumbnailObjectPath = "thumbnail_object_path"
        case thumbnailByteSize = "thumbnail_byte_size"
        case abandonedAt = "abandoned_at"
        case reserveOperationID = "reserve_operation_id"
    }

    var displayTitle: String {
        if let detail = detailPoint, let point = GuinchoInspectionDetailPoint(rawValue: detail) { return point.title }
        return point.title
    }
}

struct GuinchoInspectionVehicle: Decodable {
    let brand: String?
    let model: String?
    let plate: String?
    let color: String?

    var displayName: String {
        [brand, model, plate, color].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct GuinchoInspectionDocument: Decodable {
    let appointmentID: UUID
    let revision: Int64
    let summary: GuinchoInspectionSummary
    let currentVersion: GuinchoInspectionVersion?
    let vehicle: GuinchoInspectionVehicle?
    let isProvider: Bool
    let closed: Bool
    let requiredPhotos: [GuinchoInspectionPhoto]
    let namedPhotos: [GuinchoInspectionPhoto]
    let pendingPhotos: [GuinchoInspectionPhoto]

    enum CodingKeys: String, CodingKey {
        case revision, summary, vehicle, closed
        case appointmentID = "appointment_id"
        case currentVersion = "current_version"
        case isProvider = "is_provider"
        case requiredPhotos = "required_photos"
        case namedPhotos = "named_photos"
        case pendingPhotos = "pending_photos"
    }
}

struct GuinchoInspectionPhotoPage: Decodable {
    let items: [GuinchoInspectionPhoto]
    let hasMore: Bool
    let nextOrder: Int64?
    let nextID: UUID?
    enum CodingKeys: String, CodingKey {
        case items
        case hasMore = "has_more"
        case nextOrder = "next_order"
        case nextID = "next_id"
    }
}

struct GuinchoInspectionVersionPage: Decodable {
    let items: [GuinchoInspectionVersion]
    let hasMore: Bool
    let nextVersion: Int?
    enum CodingKeys: String, CodingKey {
        case items
        case hasMore = "has_more"
        case nextVersion = "next_version"
    }
}

struct GuinchoInspectionMutationResult: Decodable {
    let outcome: String
    let inspection: GuinchoInspectionDocument
    let photo: GuinchoInspectionPhoto?
}
