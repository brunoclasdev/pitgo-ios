import Foundation

struct ProviderRatingSummary: Decodable, Equatable {
    let count: Int
    let average: Double?

    var isValid: Bool {
        count >= 0 && (count == 0 ? average == nil : average.map { $0.isFinite && (1...5).contains($0) } == true)
    }
}

struct ServiceRatingState: Decodable, Equatable {
    let submitted: Bool
    let canRate: Bool

    enum CodingKeys: String, CodingKey {
        case submitted
        case canRate = "can_rate"
    }
}

struct ServiceRating: Decodable, Equatable, Identifiable {
    let id: UUID
    let rating: Int
    let comment: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, rating, comment
        case createdAt = "created_at"
    }
}

struct ServiceRatingContext: Decodable, Equatable {
    let appointmentID: UUID
    let providerName: String
    let canRate: Bool
    let submitted: Bool
    let rating: ServiceRating?

    enum CodingKeys: String, CodingKey {
        case appointmentID = "appointment_id"
        case providerName = "provider_name"
        case canRate = "can_rate"
        case submitted
        case rating
    }
}

struct ServiceRatingSubmission: Decodable {
    let outcome: String
    let context: ServiceRatingContext
}

enum ServiceRatingPhase: Equatable {
    case loading
    case ready
    case submitting
    case saved(ServiceRating)
    case ineligible
    case loadFailure
    case submitFailure
}
