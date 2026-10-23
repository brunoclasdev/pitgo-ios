import Foundation

// Standalone harness: compile with the production checkout VM, PaymentModels and
// SavedCardModels. Repositories below replace network calls; no real charges.
enum PaymentCreationOutcome { case created(PaymentCreationResult), failure(PaymentFailureReason) }
enum PaymentStatusResult { case found(paymentID: UUID, status: PaymentStatus, method: PaymentMethodKind), notFound }
enum SavedCardListResult { case success([SavedCard]) }
enum SavedCardContextResult { case success(SavedCardTokenizationContext), failure }
struct Listing { let serviceID: UUID; let minimumPrice: Decimal? }
enum CatalogResult { case content([Listing]) }
@MainActor final class ServiceCatalogRepository {
    func fetchHomeServices() async -> CatalogResult { .content([]) }
}
@MainActor final class SavedCardRepository {
    let cards = [SavedCard(id: UUID(), brand: "visa", lastFourDigits: "1234", createdAt: Date())]
    func list() async -> SavedCardListResult { .success(cards) }
    func tokenizationContext(savedCardID: UUID) async -> SavedCardContextResult { .failure }
}
@MainActor final class PaymentRepository {
    var statuses: [PaymentStatusResult] = [.notFound]
    var creation: PaymentCreationOutcome = .failure(.cardRejected)
    var creationCount = 0
    func status(requestID: UUID) async -> PaymentStatusResult {
        if statuses.count > 1 { return statuses.removeFirst() }
        return statuses[0]
    }
    func createPayment(requestID: UUID, dispatchKind: PaymentDispatchKind, serviceID: UUID, amount: Decimal,
                       method: PaymentMethodKind, savedCardID: UUID?, cardSecurityCodeToken: String?,
                       appointmentID: UUID?, quoteVersion: Int64?) async -> PaymentCreationOutcome {
        creationCount += 1
        return creation
    }
    func disconnect() {}
    func subscribe(requestID: UUID, onChanged: @escaping @Sendable () -> Void) async {}
}

@main struct PaymentCheckoutRegression {
    @MainActor static func waitFor(_ vm: PaymentCheckoutViewModel, _ expected: PaymentCheckoutUiState) async throws {
        for _ in 0..<100 {
            if vm.state == expected { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        preconditionFailure("Expected \(expected), got \(vm.state)")
    }
    @MainActor static func main() async throws {
        let cards = SavedCardRepository()
        func make(_ repository: PaymentRepository) -> PaymentCheckoutViewModel {
            PaymentCheckoutViewModel(serviceID: UUID(), dispatchKind: .pittecAutoSequential,
                catalogRepository: ServiceCatalogRepository(), paymentRepository: repository,
                savedCardRepository: cards,
                pittecContext: PitTecPaymentContext(searchID: UUID(), appointmentID: UUID(), quoteVersion: 1, amount: 1))
        }
        let declinedRepo = PaymentRepository()
        declinedRepo.statuses = [.found(paymentID: UUID(), status: .rejected, method: .savedCard)]
        let restored = make(declinedRepo)
        restored.start()
        try await waitFor(restored, .declined)
        restored.chooseAnotherMethod()
        precondition(restored.state == .selectingMethod(amount: 1, savedCards: cards.cards))
        restored.payWithPix() // Fake transport returns CARD_REJECTED.
        try await waitFor(restored, .declined)
        restored.stop()

        let pendingRepo = PaymentRepository()
        pendingRepo.statuses = [.found(paymentID: UUID(), status: .pending, method: .savedCard),
                                .found(paymentID: UUID(), status: .rejected, method: .savedCard)]
        let pending = make(pendingRepo)
        pending.start()
        try await waitFor(pending, .declined)
        pending.stop()

        let pixRepo = PaymentRepository()
        pixRepo.statuses = [.found(paymentID: UUID(), status: .expired, method: .pix)]
        let pix = make(pixRepo)
        pix.start()
        try await waitFor(pix, .expired)
        pix.retryPix()
        try await waitFor(pix, .declined)
        precondition(pixRepo.creationCount == 1)
        pix.stop()
        print("PASS: restored rejection retains cards; CARD_REJECTED shows decline; restored pending exits loading; expired Pix can retry")
    }
}
