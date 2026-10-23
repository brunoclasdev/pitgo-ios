import Combine
import Foundation

@MainActor
final class GuinchoHistoryViewModel: ObservableObject {
    @Published private(set) var rows: [MobileDispatchSnapshot] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasFailed = false
    @Published private(set) var hasMore = false

    private let repository: GuinchoHistoryRepository

    init(repository: GuinchoHistoryRepository) { self.repository = repository }

    func loadMore(reset: Bool = false) {
        guard !isLoading else { return }
        if reset { rows = [] }
        isLoading = true
        hasFailed = false
        let cursor = reset ? nil : rows.last
        Task {
            do {
                let page = try await repository.list(
                    before: cursor?.createdAt,
                    beforeID: cursor?.appointment?.appointmentID
                )
                rows = (reset ? [] : rows) + page
                var seen = Set<UUID>()
                rows = rows.filter { row in
                    guard let id = row.appointment?.appointmentID else { return false }
                    return seen.insert(id).inserted
                }
                hasMore = page.count == 20
            } catch {
                hasFailed = true
            }
            isLoading = false
        }
    }
}
