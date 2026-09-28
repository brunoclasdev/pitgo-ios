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

import Combine
import Foundation

enum PaymentCheckoutUiState: Equatable {
    case loadingAmount
    /// Catálogo sem preço mínimo válido para este serviço — nunca cobra um valor inventado.
    case invalidService
    case selectingMethod(amount: Decimal, savedCards: [SavedCard])
    case loadingCardContext
    case confirmingCard(SavedCardTokenizationContext)
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

@MainActor
final class PaymentCheckoutViewModel: ObservableObject {
    @Published private(set) var state: PaymentCheckoutUiState = .loadingAmount

    /// Reaproveitado pelo chamador como `search_id`/`p_request_id` da RPC de despacho após
    /// `.approved` — auto-gerado para `MOBILE_SEQUENTIAL` (pagamento antes da busca, inalterado);
    /// para `PITTEC_AUTO_SEQUENTIAL` (`021`) é o `search_id` já existente do atendimento aceito,
    /// vindo de `pittecContext`.
    let requestID: UUID

    private let serviceID: UUID
    let dispatchKind: PaymentDispatchKind
    private let catalogRepository: ServiceCatalogRepository
    private let paymentRepository: PaymentRepository
    private let savedCardRepository: SavedCardRepository
    /// `021` — presente só para `PITTEC_AUTO_SEQUENTIAL`; carrega o valor já conhecido do
    /// orçamento, pulando o cálculo de `amount` que `loadAmountAndCards()` faz para os demais casos.
    private let pittecContext: PitTecPaymentContext?

    private var amount: Decimal = 0
    private var savedCards: [SavedCard] = []
    private var isStarted = false
    private var approvalPollTask: Task<Void, Never>?

    init(
        serviceID: UUID,
        dispatchKind: PaymentDispatchKind,
        catalogRepository: ServiceCatalogRepository,
        paymentRepository: PaymentRepository,
        savedCardRepository: SavedCardRepository,
        pittecContext: PitTecPaymentContext? = nil
    ) {
        self.serviceID = serviceID
        self.dispatchKind = dispatchKind
        self.catalogRepository = catalogRepository
        self.paymentRepository = paymentRepository
        self.savedCardRepository = savedCardRepository
        self.pittecContext = pittecContext
        self.requestID = pittecContext?.searchID ?? UUID()
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
        approvalPollTask?.cancel()
        approvalPollTask = nil
        paymentRepository.disconnect()
    }

    private func loadAmountAndCards() async {
        switch dispatchKind {
        case .pittecAutoSequential:
            // `021`: valor já conhecido do orçamento confirmado — nunca mais uma tarifa fixa nem
            // vindo do catálogo (sempre 0 para PitTec, ver nota em `PaymentModels.swift`).
            guard let pittecContext else {
                state = .invalidService
                return
            }
            amount = pittecContext.amount
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

        // Mantém os cartões disponíveis também ao restaurar uma tentativa recusada.
        if case let .success(cards) = await savedCardRepository.list() {
            savedCards = cards
        }

        // Igual ao Android: antes de exibir a seleção de método, recupera uma tentativa já
        // criada para este requestID. Isso é essencial no PitTec, onde o sheet pode ser recriado
        // enquanto o backend já marcou o pagamento como REJECTED/APPROVED.
        if case let .found(_, status, _) = await paymentRepository.status(requestID: requestID) {
            applyStatus(status)
            if isAwaitingConfirmation {
                observeApproval()
            }
            return
        }

        state = .selectingMethod(amount: amount, savedCards: savedCards)
    }

    func payWithPix() {
        createPayment(method: .pix, savedCardID: nil)
    }

    func payWithSavedCard(_ card: SavedCard) {
        guard case .selectingMethod = state else { return }
        state = .loadingCardContext
        Task { [weak self] in
            guard let self else { return }
            switch await savedCardRepository.tokenizationContext(savedCardID: card.id) {
            case let .success(context): state = .confirmingCard(context)
            case .failure: state = .failure
            }
        }
    }

    func confirmSavedCard(token: String, context: SavedCardTokenizationContext) {
        guard case .confirmingCard = state else { return }
        state = .selectingMethod(amount: amount, savedCards: savedCards)
        createPayment(method: .savedCard, savedCardID: context.savedCardID, cardSecurityCodeToken: token)
    }

    /// Pix expirado ou falha — gera uma nova cobrança com o MESMO `requestID` (idempotência,
    /// `research.md §6`: o backend reconhece que a tentativa anterior não está mais "viva" e cria
    /// uma nova cobrança, sem duplicar `payments`).
    func retryPix() {
        guard case .expired = state else { return }
        chooseAnotherMethod()
        createPayment(method: .pix, savedCardID: nil)
    }

    func chooseAnotherMethod() {
        approvalPollTask?.cancel()
        approvalPollTask = nil
        paymentRepository.disconnect()
        state = .selectingMethod(amount: amount, savedCards: savedCards)
    }

    private func createPayment(method: PaymentMethodKind, savedCardID: UUID?, cardSecurityCodeToken: String? = nil) {
        guard case .selectingMethod = state, amount > 0 else { return }
        state = .creatingPayment
        Task { [weak self] in
            guard let self else { return }
            switch await self.paymentRepository.createPayment(
                requestID: self.requestID,
                dispatchKind: self.dispatchKind,
                amount: self.amount,
                method: method,
                savedCardID: savedCardID,
                cardSecurityCodeToken: cardSecurityCodeToken,
                appointmentID: self.pittecContext?.appointmentID,
                quoteVersion: self.pittecContext?.quoteVersion
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
        approvalPollTask?.cancel()
        // O Realtime é opcional: ele só acelera a atualização e não pode bloquear o polling.
        Task { [weak self] in
            guard let self else { return }
            await self.paymentRepository.subscribe(requestID: self.requestID) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    await self.refreshStatus()
                }
            }
        }
        approvalPollTask = Task { [weak self] in
            guard let self else { return }
            // Consulta imediatamente e depois continua até um estado terminal. O pagamento
            // pode mudar para REJECTED/APPROVED sem qualquer evento Realtime no device.
            while !Task.isCancelled, self.isAwaitingConfirmation {
                await self.refreshStatus()
                guard !Task.isCancelled, self.isAwaitingConfirmation else { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private var isAwaitingConfirmation: Bool {
        switch state {
        case .awaitingPix, .awaitingCardConfirmation: true
        default: false
        }
    }

    private func refreshStatus() async {
        guard isAwaitingConfirmation else { return }
        if case let .found(_, status, _) = await paymentRepository.status(requestID: requestID) {
            // Uma consulta anterior não pode sobrescrever uma nova seleção/tentativa.
            guard !Task.isCancelled, isAwaitingConfirmation else { return }
            applyStatus(status)
        }
    }

    private func applyStatus(_ status: PaymentStatus) {
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
            if !isAwaitingConfirmation {
                state = .awaitingCardConfirmation
            }
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
        case .cardRejected:
            state = .declined
        default:
            state = .failure
        }
    }
}
