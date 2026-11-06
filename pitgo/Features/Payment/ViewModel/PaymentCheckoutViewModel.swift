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
    case cancelled
    case cancelling
    case creatingPayment
    case loadingPixDetails
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
    private(set) var requestID: UUID

    private let serviceID: UUID
    let dispatchKind: PaymentDispatchKind
    private let catalogRepository: ServiceCatalogRepository
    private let paymentRepository: PaymentGateway
    private let savedCardRepository: SavedCardRepository
    /// `021` — presente só para `PITTEC_AUTO_SEQUENTIAL`; carrega o valor já conhecido do
    /// orçamento, pulando o cálculo de `amount` que `loadAmountAndCards()` faz para os demais casos.
    private let pittecContext: PitTecPaymentContext?
    /// `028` — mesmo papel de `pittecContext`, para `GUINCHO_DIRECT`: o valor já é o total final
    /// mostrado no mini card/"Contratar" (FR-007), nunca recalculado aqui nem vindo do catálogo.
    private let guinchoContext: GuinchoPaymentContext?

    private var amount: Decimal = 0
    private var savedCards: [SavedCard] = []
    private var activeMethod: PaymentMethodKind?
    private var isStarted = false
    private var approvalPollTask: Task<Void, Never>?

    /// `027`: liga os botões de simulação em `PaymentCheckoutView` (Dev) — `false` para
    /// `PaymentRepository` real.
    var simulated: Bool { paymentRepository.simulated }

    init(
        serviceID: UUID,
        dispatchKind: PaymentDispatchKind,
        catalogRepository: ServiceCatalogRepository,
        paymentRepository: PaymentGateway,
        savedCardRepository: SavedCardRepository,
        pittecContext: PitTecPaymentContext? = nil,
        guinchoContext: GuinchoPaymentContext? = nil
    ) {
        self.serviceID = serviceID
        self.dispatchKind = dispatchKind
        self.catalogRepository = catalogRepository
        self.paymentRepository = paymentRepository
        self.savedCardRepository = savedCardRepository
        self.pittecContext = pittecContext
        self.guinchoContext = guinchoContext
        self.requestID = pittecContext?.searchID ?? guinchoContext?.searchID ?? UUID()
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
            guard let pittecContext, pittecContext.amount > 0, pittecContext.quoteVersion > 0 else {
                state = .invalidService
                return
            }
            amount = pittecContext.amount
        case .guinchoDirect:
            // `028`: total final já calculado em `GuinchoMapViewModel.contract()`/exibido no mini
            // card — nunca recalculado aqui.
            guard let guinchoContext, guinchoContext.amount > 0, guinchoContext.quoteVersion > 0 else {
                state = .invalidService
                return
            }
            amount = guinchoContext.amount
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

        if EnvironmentConfig.current.id == .homol {
            // Mesmo contrato do Android: valor estável nesta instância, em centavos (R$1–R$2).
            amount = Decimal(Int.random(in: 100...200)) / 100
        }

        // Mantém os cartões disponíveis também ao restaurar uma tentativa recusada.
        if case let .success(cards) = await savedCardRepository.list() {
            savedCards = cards
        }

        // A Mobile checkout has no appointment yet. Recover its original request ID after
        // reopening the app instead of creating a second charge for the same pending service.
        if dispatchKind == .mobileSequential,
           case let .found(_, _, _, details) = await paymentRepository.recoverable(),
           details.dispatchKind == .mobileSequential, details.serviceID == serviceID,
           let recoveredRequestID = details.requestID {
            requestID = recoveredRequestID
        }

        // Igual ao Android: antes de exibir a seleção de método, recupera uma tentativa já
        // criada para este requestID. Isso é essencial no PitTec, onde o sheet pode ser recriado
        // enquanto o backend já marcou o pagamento como REJECTED/APPROVED.
        switch await paymentRepository.status(requestID: requestID) {
        case let .found(_, status, method, details):
            applyStatus(status, details: details, method: method)
            if isAwaitingConfirmation { observeApproval() }
        case let .failure(reason):
            applyFailure(reason)
        case .notFound:
            state = .selectingMethod(amount: amount, savedCards: savedCards)
        }
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

    /// `027` US2: só chamado pelos botões de simulação (Dev) — `simulated` guarda a visibilidade na
    /// View; aqui só confirmamos que o gateway realmente suporta `simulate` antes de chamar.
    func simulate(_ status: PaymentStatus) {
        guard let simulatable = paymentRepository as? SimulatablePaymentGateway else { return }
        Task { [weak self] in
            guard let self else { return }
            let result = await simulatable.simulate(requestID: self.requestID, status: status)
            if case let .found(_, status, method, details) = result {
                self.applyStatus(status, details: details, method: method)
            }
        }
    }

    /// Botão "Simular falha" — atalho só de UI (não chama o gateway) para testar a tela genérica de
    /// falha sem depender de um status real de pagamento (mesmo `simulateFailure` do Android).
    func simulateFailure() {
        state = .failure
    }

    func chooseAnotherMethod() {
        approvalPollTask?.cancel()
        approvalPollTask = nil
        paymentRepository.disconnect()
        state = .selectingMethod(amount: amount, savedCards: savedCards)
    }

    func cancelCheckout() async -> Bool {
        switch state {
        case .creatingPayment, .loadingCardContext, .loadingAmount, .cancelling, .approved: return false
        default: break
        }
        state = .cancelling
        approvalPollTask?.cancel()
        approvalPollTask = nil
        paymentRepository.disconnect()
        switch await paymentRepository.status(requestID: requestID) {
        case .notFound:
            if dispatchKind == .guinchoDirect,
               !(await paymentRepository.cancelUnpaidGuincho(requestID: requestID)) {
                state = .failure
                return false
            }
            return true
        case let .found(paymentID, _, _, _):
            switch await paymentRepository.cancel(paymentID: paymentID) {
            case .resolved: return true
            case let .failure(reason): applyFailure(reason); return false
            }
        case let .failure(reason):
            applyFailure(reason)
            return false
        }
    }

    private func createPayment(method: PaymentMethodKind, savedCardID: UUID?, cardSecurityCodeToken: String? = nil) {
        guard case .selectingMethod = state, amount > 0 else { return }
        activeMethod = method
        state = .creatingPayment
        Task { [weak self] in
            guard let self else { return }
            switch await self.paymentRepository.createPayment(
                requestID: self.requestID,
                dispatchKind: self.dispatchKind,
                serviceID: self.serviceID,
                amount: self.amount,
                method: method,
                savedCardID: savedCardID,
                cardSecurityCodeToken: cardSecurityCodeToken,
                appointmentID: self.pittecContext?.appointmentID ?? self.guinchoContext?.appointmentID,
                quoteVersion: self.pittecContext?.quoteVersion ?? self.guinchoContext?.quoteVersion
            ) {
            case let .created(result):
                self.apply(result)
            case let .failure(reason):
                self.applyFailure(reason)
            }
        }
    }

    private func apply(_ result: PaymentCreationResult) {
        if result.cancelRequested {
            state = .cancelled
            return
        }
        if result.syncState != "CURRENT" {
            if result.status == .pending, activeMethod == .pix {
                showPendingPix(result.pix)
            } else {
                state = .awaitingCardConfirmation
            }
            observeApproval()
            return
        }
        switch result.status {
        case .approved:
            state = .approved
        case .rejected:
            state = .declined
        case .expired:
            state = .expired
        case .pending:
            if activeMethod == .pix || result.pix != nil {
                showPendingPix(result.pix)
            } else {
                state = .awaitingCardConfirmation
            }
            observeApproval()
        case .cancelled, .refundPending, .refunded, .refundFailed:
            // Nenhum destes é um resultado possível logo após a criação — tratado como falha
            // genérica em vez de inventar uma transição não coberta pela máquina de estados real.
            state = .failure
        }
    }

    /// Realtime acelera a atualização; o status também é consultado a cada 10 segundos.
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
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    /// Recheck immediately when the client returns from the banking app.
    func refreshWhenActive() {
        guard isAwaitingConfirmation else { return }
        Task { [weak self] in await self?.refreshStatus() }
    }

    private var isAwaitingConfirmation: Bool {
        switch state {
        case .loadingPixDetails, .awaitingPix, .awaitingCardConfirmation: true
        default: false
        }
    }

    private func refreshStatus() async {
        guard isAwaitingConfirmation else { return }
        if case let .found(_, status, method, details) = await paymentRepository.status(requestID: requestID) {
            // Uma consulta anterior não pode sobrescrever uma nova seleção/tentativa.
            guard !Task.isCancelled, isAwaitingConfirmation else { return }
            applyStatus(status, details: details, method: method)
        }
    }

    private func applyStatus(_ status: PaymentStatus, details: PaymentStatusDetails = PaymentStatusDetails(), method: PaymentMethodKind? = nil) {
        if details.pix != nil { activeMethod = .pix }
        else if let method { activeMethod = method }
        if details.cancelRequested || status == .cancelled || status.isRefundOutcome {
            state = .cancelled
            paymentRepository.disconnect()
            return
        }
        if details.syncState != "CURRENT" {
            if status == .pending, activeMethod == .pix {
                showPendingPix(details.pix)
            } else {
                state = .awaitingCardConfirmation
            }
            return
        }
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
            if activeMethod == .pix {
                showPendingPix(details.pix)
            } else if !isAwaitingConfirmation {
                state = .awaitingCardConfirmation
            }
        case .cancelled, .refundPending, .refunded, .refundFailed:
            state = .failure
            paymentRepository.disconnect()
        }
    }

    private func showPendingPix(_ pix: PaymentPixDetails?) {
        if let pix {
            state = .awaitingPix(pix)
        } else if case .awaitingPix = state {
            // A partial status snapshot must not discard an already displayed QR code.
        } else {
            state = .loadingPixDetails
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
