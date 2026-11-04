import Foundation

struct TransportCatalog: Decodable {
    let sizes: [GuinchoSize]
    let vehicle_categories: [TransportCategory]
}

struct TransportCategory: Decodable, Identifiable, Hashable {
    let id: UUID
    let code: String
    let name: String
}

struct GuinchoSize: Decodable, Identifiable, Hashable {
    let id: UUID
    let code: String
    let name: String
    let revision: Int64
    let vehicle_category_ids: [UUID]
}
