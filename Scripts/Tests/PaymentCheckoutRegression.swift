import Foundation

// Standalone harness: compile with the production checkout VM, PaymentModels and
// SavedCardModels. Repositories below replace network calls; no real charges.
enum PaymentCreationOutcome { case created(PaymentCreationResult), failure(PaymentFailureReason) }
enum PaymentStatusResult { case found(paymentID: UUID, status: PaymentStatus, method: PaymentMethodKind, details: PaymentStatusDetails = PaymentStatusDetails()), notFound, failure(PaymentFailureReason) }
enum SavedCardListResult { case success([SavedCard]) }
enum SavedCardContextResult { case success(SavedCardTokenizationContext), failure }
struct Listing { let serviceID: UUID; let minimumPrice: Decimal? }
enum CatalogResult { case content([Listing]) }
@MainActor final class ServiceCatalogRepository {
    var listings: [Listing] = []
    func fetchHomeServices() async -> CatalogResult { .content(listings) }
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
    var simulated = false
    var recovery: PaymentStatusResult = .notFound
    func recoverable() async -> PaymentStatusResult { recovery }
    var cancellation: PaymentRefundOutcome = .resolved(.cancelled)
    var cancellationCount = 0
    var unpaidCancellation = true
    var unpaidCancellationCount = 0
    func cancel(paymentID: UUID) async -> PaymentRefundOutcome {
        cancellationCount += 1
        return cancellation
    }
    func cancelUnpaidGuincho(requestID: UUID) async -> Bool {
        unpaidCancellationCount += 1
        return unpaidCancellation
    }
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

typealias PaymentGateway = PaymentRepository
@MainActor protocol SimulatablePaymentGateway {
    func simulate(requestID: UUID, status: PaymentStatus) async -> PaymentStatusResult
}
enum PaymentRefundOutcome { case resolved(PaymentStatus), failure(PaymentFailureReason) }
struct GuinchoPaymentContext {
    let searchID: UUID; let appointmentID: UUID; let quoteVersion: Int64; let amount: Decimal
}
enum EnvironmentID { case dev, homol }
struct EnvironmentConfig {
    static let current = EnvironmentConfig()
    let id = EnvironmentID.dev
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
        let cancelRepo = PaymentRepository()
        let cancelVM = make(cancelRepo)
        cancelVM.start()
        try await waitFor(cancelVM, .selectingMethod(amount: 1, savedCards: cards.cards))
        cancelRepo.statuses = [.found(paymentID: UUID(), status: .pending, method: .pix)]
        let cancelled = await cancelVM.cancelCheckout()
        precondition(cancelled && cancelRepo.cancellationCount == 1)

        let failureRepo = PaymentRepository()
        let failureVM = make(failureRepo)
        failureVM.start()
        try await waitFor(failureVM, .selectingMethod(amount: 1, savedCards: cards.cards))
        failureRepo.statuses = [.failure(.offline)]
        let failed = await failureVM.cancelCheckout()
        precondition(!failed && failureVM.state == .failure && failureRepo.cancellationCount == 0)

        let cancellingRepo = PaymentRepository()
        cancellingRepo.statuses = [.found(paymentID: UUID(), status: .approved, method: .pix,
                                         details: PaymentStatusDetails(cancelRequested: true))]
        let cancellingVM = make(cancellingRepo)
        cancellingVM.start()
        try await waitFor(cancellingVM, .cancelled)
        cancellingVM.stop()

        let resumeRepo = PaymentRepository()
        let qr = PaymentPixDetails(qrCode: "pix-pendente", qrCodeBase64: "AA==", expiresAt: nil)
        resumeRepo.statuses = [.found(paymentID: UUID(), status: .pending, method: .pix, details: PaymentStatusDetails(pix: qr))]
        let resumeVM = make(resumeRepo)
        resumeVM.start()
        try await waitFor(resumeVM, .awaitingPix(qr))
        resumeVM.stop()

        let directRepo = PaymentRepository()
        let directVM = PaymentCheckoutViewModel(serviceID: UUID(), dispatchKind: .guinchoDirect,
            catalogRepository: ServiceCatalogRepository(), paymentRepository: directRepo, savedCardRepository: cards,
            guinchoContext: GuinchoPaymentContext(searchID: UUID(), appointmentID: UUID(), quoteVersion: 1, amount: 1))
        directVM.start()
        try await waitFor(directVM, .selectingMethod(amount: 1, savedCards: cards.cards))
        directRepo.unpaidCancellation = false
        let directFailed = await directVM.cancelCheckout()
        precondition(!directFailed && directRepo.unpaidCancellationCount == 1)
        directRepo.unpaidCancellation = true
        let directCancelled = await directVM.cancelCheckout()
        precondition(directCancelled && directRepo.unpaidCancellationCount == 2)
        let syncingRepo = PaymentRepository()
        syncingRepo.statuses = [.found(paymentID: UUID(), status: .approved, method: .pix,
                                       details: PaymentStatusDetails(syncState: "RECONCILING"))]
        let syncingVM = make(syncingRepo)
        syncingVM.start()
        try await waitFor(syncingVM, .awaitingCardConfirmation)
        syncingVM.stop()
        print("PASS: approval waits for authoritative payment reconciliation")

        let recoveredRequestID = UUID()
        let recoveredServiceID = UUID()
        let recoveryRepo = PaymentRepository()
        let recoveryCatalog = ServiceCatalogRepository()
        recoveryCatalog.listings = [Listing(serviceID: recoveredServiceID, minimumPrice: 10)]
        recoveryRepo.recovery = .found(paymentID: UUID(), status: .pending, method: .pix,
            details: PaymentStatusDetails(requestID: recoveredRequestID, serviceID: recoveredServiceID, dispatchKind: .mobileSequential))
        recoveryRepo.statuses = [.found(paymentID: UUID(), status: .pending, method: .pix, details: PaymentStatusDetails(pix: qr))]
        let recoveryVM = PaymentCheckoutViewModel(serviceID: recoveredServiceID, dispatchKind: .mobileSequential,
            catalogRepository: recoveryCatalog, paymentRepository: recoveryRepo, savedCardRepository: cards)
        recoveryVM.start()
        try await waitFor(recoveryVM, .awaitingPix(qr))
        precondition(recoveryVM.requestID == recoveredRequestID && recoveryRepo.creationCount == 0)
        recoveryVM.stop()
        print("PASS: reopened mobile checkout reuses pending payment request ID without creating a charge")
        print("PASS: cancellation requires server acknowledgement; unpaid guincho releases reservation; resumed Pix restores QR; cancellation never approves dispatch")
        print("PASS: restored rejection retains cards; CARD_REJECTED shows decline; restored pending exits loading; expired Pix can retry")
    }
}
