//
//  PaymentCheckoutViewModel.swift
//  pitgo
//
//  Checkout compartilhado pelos fluxos MOBILE_SEQUENTIAL (`013`) e PITTEC_AUTO_SEQUENTIAL (`015`).
//  Gera o próprio `requestID` — o mesmo `search_id`/`p_request_id` que o chamador reaproveita para
//  `start_mobile_dispatch`/`start_pittec_dispatch` assim que o pagamento chega a `.approved`
//  (`research.md §9-10`, ponto de gate verificado contra o backend real — ver nota em
//  `PaymentModels.swift`). Nunca chama a RPC de despacho ele mesmo: apenas informa aprovação por
//  callback, mantendo o `ClientMobileDispatchViewModel`/`PitTecClientViewModel` como donos exclusivos
//  de suas próprias RPCs de despacho.
//

import Foundation

enum PaymentCheckoutUiState: Equatable {
    case loadingAmount
    /// Catálogo sem preço mínimo válido para este serviço — nunca cobra um valor inventado.
    case invalidService
    case selectingMethod(amount: Decimal, savedCards: [SavedCard])
    case creatingPayment
    case awaitingPix(PaymentPixDetails)
    case awaitingCardConfirmation
    case approved
    case declined
    /// `mp-create-payment` → `422 PAYER_DOCUMENT_REQUIRED` — Pix exige CPF, ainda não cadastrado.
    case payerDocumentRequired
    case expired
    case sessionExpired
    case failure
}

@Observable
@MainActor
final class PaymentCheckoutViewModel {
    private(set) var state: PaymentCheckoutUiState = .loadingAmount

    /// Reaproveitado pelo chamador como `search_id`/`p_request_id` da RPC de despacho após `.approved`.
    let requestID = UUID()

    private let serviceID: UUID
    let dispatchKind: PaymentDispatchKind
    private let catalogRepository: ServiceCatalogRepository
    private let paymentRepository: PaymentRepository
    private let savedCardRepository: SavedCardRepository

    private var amount: Decimal = 0
    private var savedCards: [SavedCard] = []
    private var isStarted = false

    init(
        serviceID: UUID,
        dispatchKind: PaymentDispatchKind,
        catalogRepository: ServiceCatalogRepository,
        paymentRepository: PaymentRepository,
        savedCardRepository: SavedCardRepository
    ) {
        self.serviceID = serviceID
        self.dispatchKind = dispatchKind
        self.catalogRepository = catalogRepository
        self.paymentRepository = paymentRepository
        self.savedCardRepository = savedCardRepository
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        Task { [weak self] in
            guard let self else { return }
            await self.loadAmountAndCards()
        }
    }

    func stop() {
        paymentRepository.disconnect()
    }

    private func loadAmountAndCards() async {
        switch dispatchKind {
        case .pittecAutoSequential:
            // Tarifa fixa de plataforma — nunca vem do catálogo (sempre 0 para PitTec, ver nota em
            // `PaymentModels.swift`).
            amount = PaymentPricing.pittecPlatformFee
        case .mobileSequential:
            guard
                case let .content(listings) = await catalogRepository.fetchHomeServices(),
                let listing = listings.first(where: { $0.serviceID == serviceID }),
                let minimumPrice = listing.minimumPrice,
                minimumPrice > 0
            else {
                state = .invalidService
                return
            }
            amount = minimumPrice
        }

        if case let .success(cards) = await savedCardRepository.list() {
            savedCards = cards
        }
        state = .selectingMethod(amount: amount, savedCards: savedCards)
    }

    func payWithPix() {
        createPayment(method: .pix, savedCardID: nil)
    }

    func payWithSavedCard(_ card: SavedCard) {
        createPayment(method: .savedCard, savedCardID: card.id)
    }

    /// Pix expirado ou falha — gera uma nova cobrança com o MESMO `requestID` (idempotência,
    /// `research.md §6`: o backend reconhece que a tentativa anterior não está mais "viva" e cria
    /// uma nova cobrança, sem duplicar `payments`).
    func retryPix() {
        createPayment(method: .pix, savedCardID: nil)
    }

    func chooseAnotherMethod() {
        paymentRepository.disconnect()
        state = .selectingMethod(amount: amount, savedCards: savedCards)
    }

    private func createPayment(method: PaymentMethodKind, savedCardID: UUID?) {
        guard case .selectingMethod = state, amount > 0 else { return }
        state = .creatingPayment
        Task { [weak self] in
            guard let self else { return }
            switch await self.paymentRepository.createPayment(
                requestID: self.requestID,
                dispatchKind: self.dispatchKind,
                amount: self.amount,
                method: method,
                savedCardID: savedCardID
            ) {
            case let .created(result):
                self.apply(result)
            case let .failure(reason):
                self.applyFailure(reason)
            }
        }
    }

    private func apply(_ result: PaymentCreationResult) {
        switch result.status {
        case .approved:
            state = .approved
        case .rejected:
            state = .declined
        case .expired:
            state = .expired
        case .pending:
            state = result.pix.map(PaymentCheckoutUiState.awaitingPix) ?? .awaitingCardConfirmation
            observeApproval()
        case .cancelled, .refundPending, .refunded, .refundFailed:
            // Nenhum destes é um resultado possível logo após a criação — tratado como falha
            // genérica em vez de inventar uma transição não coberta pela máquina de estados real.
            state = .failure
        }
    }

    /// Canal Realtime como sinal primário; `10s` sem confirmação cai no fallback por RPC
    /// (`contracts/payment-realtime-ui.md`).
    private func observeApproval() {
        Task { [weak self] in
            guard let self else { return }
            await self.paymentRepository.subscribe(requestID: self.requestID) { [weak self] in
                Task { @MainActor in self?.refreshStatus() }
            }
        }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self, self.isAwaitingConfirmation else { return }
            self.refreshStatus()
        }
    }

    private var isAwaitingConfirmation: Bool {
        switch state {
        case .awaitingPix, .awaitingCardConfirmation: true
        default: false
        }
    }

    private func refreshStatus() {
        Task { [weak self] in
            guard let self else { return }
            if case let .found(_, status, _) = await self.paymentRepository.status(requestID: self.requestID) {
                self.applyStatus(status)
            }
        }
    }

    private func applyStatus(_ status: PaymentStatus) {
        guard isAwaitingConfirmation else { return }
        switch status {
        case .approved:
            state = .approved
            paymentRepository.disconnect()
        case .rejected:
            state = .declined
            paymentRepository.disconnect()
        case .expired:
            state = .expired
            paymentRepository.disconnect()
        case .pending:
            break
        case .cancelled, .refundPending, .refunded, .refundFailed:
            state = .failure
            paymentRepository.disconnect()
        }
    }

    private func applyFailure(_ reason: PaymentFailureReason) {
        switch reason {
        case .sessionExpired:
            state = .sessionExpired
        case .payerDocumentRequired:
            state = .payerDocumentRequired
        default:
            state = .failure
        }
    }
}
