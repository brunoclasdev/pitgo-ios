import Combine
import Foundation

@MainActor
final class ProviderRatingsViewModel: ObservableObject {
    @Published private(set) var summary: ProviderRatingSummary?
    @Published private(set) var ratings: [ServiceRating] = []
    @Published private(set) var isLoadingSummary = false
    @Published private(set) var isLoadingRatings = false
    @Published private(set) var summaryFailed = false
    @Published private(set) var ratingsFailed = false
    @Published private(set) var hasMore = false

    private let providerID: UUID
    private let repository: ServiceRatingRepository
    private var didLoadRatings = false

    init(providerID: UUID, repository: ServiceRatingRepository) {
        self.providerID = providerID
        self.repository = repository
    }

    func loadSummary() {
        guard !isLoadingSummary else { return }
        isLoadingSummary = true
        summaryFailed = false
        Task {
            do { summary = try await repository.summary(providerID: providerID) }
            catch { summaryFailed = true }
            isLoadingSummary = false
        }
    }

    func loadRatings(reset: Bool = false) {
        guard !isLoadingRatings else { return }
        if !reset && didLoadRatings && !hasMore { return }
        isLoadingRatings = true
        ratingsFailed = false
        let cursor = reset ? nil : ratings.last
        Task {
            do {
                let page = try await repository.received(before: cursor)
                ratings = reset ? page : ratings + page.filter { item in !ratings.contains(where: { $0.id == item.id }) }
                hasMore = page.count == 20
                didLoadRatings = true
            } catch {
                ratingsFailed = true
            }
            isLoadingRatings = false
        }
    }
}
