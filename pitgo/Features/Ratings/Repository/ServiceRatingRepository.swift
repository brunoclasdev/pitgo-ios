import Foundation
import Supabase

private struct RatingAppointmentParams: Encodable { let p_appointment_id: UUID }
private struct ProviderRatingParams: Encodable { let p_provider_id: UUID }
private struct SubmitServiceRatingParams: Encodable {
    let p_appointment_id: UUID
    let p_rating: Int
    let p_comment: String?
}
private struct ListProviderRatingsParams: Encodable {
    let p_before: Date?
    let p_before_id: UUID?
    let p_limit: Int
}

final class ServiceRatingRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) { self.client = client }

    func get(appointmentID: UUID) async throws -> ServiceRatingContext {
        let result: ServiceRatingContext = try await client
            .rpc("get_service_rating", params: RatingAppointmentParams(p_appointment_id: appointmentID))
            .execute().value
        guard result.appointmentID == appointmentID,
              result.rating.map({ (1...5).contains($0.rating) }) ?? true else {
            throw ServiceRatingRepositoryError.invalidResponse
        }
        return result
    }

    func submit(appointmentID: UUID, rating: Int, comment: String) async throws -> ServiceRatingContext {
        guard (1...5).contains(rating), comment.unicodeScalars.count <= 500 else {
            throw ServiceRatingRepositoryError.invalidInput
        }
        let result: ServiceRatingSubmission = try await client
            .rpc("submit_service_rating", params: SubmitServiceRatingParams(
                p_appointment_id: appointmentID,
                p_rating: rating,
                p_comment: comment.isEmpty ? nil : comment
            ))
            .execute().value
        guard result.context.appointmentID == appointmentID,
              result.context.rating.map({ (1...5).contains($0.rating) }) == true,
              result.outcome == "submitted" || result.outcome == "already_submitted" else {
            throw ServiceRatingRepositoryError.invalidResponse
        }
        return result.context
    }

    func summary(providerID: UUID) async throws -> ProviderRatingSummary {
        let result: ProviderRatingSummary = try await client
            .rpc("get_provider_rating_summary", params: ProviderRatingParams(p_provider_id: providerID))
            .execute().value
        guard result.isValid else { throw ServiceRatingRepositoryError.invalidResponse }
        return result
    }

    func received(before: ServiceRating? = nil) async throws -> [ServiceRating] {
        let result: [ServiceRating] = try await client
            .rpc("list_my_provider_ratings", params: ListProviderRatingsParams(
                p_before: before?.createdAt,
                p_before_id: before?.id,
                p_limit: 20
            ))
            .execute().value
        guard result.allSatisfy({ (1...5).contains($0.rating) }) else {
            throw ServiceRatingRepositoryError.invalidResponse
        }
        return result
    }
}

enum ServiceRatingRepositoryError: Error {
    case invalidInput
    case invalidResponse
}
