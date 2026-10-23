import Combine
import Foundation

@MainActor
final class ServiceRatingViewModel: ObservableObject {
    @Published private(set) var phase: ServiceRatingPhase = .loading
    @Published private(set) var providerName = ""
    @Published private(set) var selectedRating: Int?
    @Published private(set) var comment = ""

    private let appointmentID: UUID
    private let repository: ServiceRatingRepository

    init(appointmentID: UUID, repository: ServiceRatingRepository) {
        self.appointmentID = appointmentID
        self.repository = repository
    }

    func load() {
        guard phase != .submitting else { return }
        phase = .loading
        Task {
            do { apply(try await repository.get(appointmentID: appointmentID)) }
            catch { phase = .loadFailure }
        }
    }

    func select(_ rating: Int) {
        guard (phase == .ready || phase == .submitFailure), (1...5).contains(rating) else { return }
        selectedRating = rating
    }

    func setComment(_ value: String) {
        guard phase == .ready || phase == .submitFailure else { return }
        comment = String(value.unicodeScalars.prefix(500))
    }

    func submit() {
        guard (phase == .ready || phase == .submitFailure), let rating = selectedRating else { return }
        let previousComment = comment
        phase = .submitting
        Task {
            do {
                apply(try await repository.submit(appointmentID: appointmentID, rating: rating, comment: previousComment))
            } catch {
                // Uma resposta perdida pode esconder sucesso no servidor. Releia antes de oferecer
                // nova tentativa para distinguir gravação confirmada de uma falha recuperável.
                do { apply(try await repository.get(appointmentID: appointmentID)) }
                catch { phase = .submitFailure }
            }
        }
    }

    private func apply(_ context: ServiceRatingContext) {
        providerName = context.providerName
        if let saved = context.rating {
            selectedRating = saved.rating
            comment = saved.comment ?? ""
            phase = .saved(saved)
        } else if context.canRate && !context.submitted {
            phase = .ready
        } else {
            phase = .ineligible
        }
    }
}
