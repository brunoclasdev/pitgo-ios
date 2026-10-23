//
//  PitTecClientViewModel.swift
//  pitgo
//
//  Sempre consulta `get_my_active_pittec_dispatch()` primeiro (idempotente e barato) antes de
//  mostrar a descoberta — cobre "abrir o card" e "retomar" com o mesmo caminho, mesma técnica de
//  `ClientMobileDispatchViewModel` (`013`).
//

import Combine
import Foundation

@MainActor
final class PitTecClientViewModel: ObservableObject {
    @Published private(set) var state: PitTecClientUiState = .restoring
    /// Duas posições correntes para a linha estimada (FR-022/FR-023) — `nil` antes do aceite ou
    /// enquanto a leitura ainda não chegou.
    @Published private(set) var routeContext: PitTecRouteContext?
    /// `018` FR-015/FR-017 — ver nota equivalente em `ClientMobileDispatchViewModel`.
    @Published private(set) var refundStatus: PaymentStatus?
    /// `020` FR-001/FR-002 — o mesmo fix já usado por `callPitTec`, exposto para a View centralizar
    /// o mapa na posição do cliente em qualquer estado de descoberta/busca, com ou sem PitTec.
    @Published private(set) var lastFix: DeviceLocationFix?

    private let serviceID: UUID
    private let repository: PitTecRepository
    private let paymentRepository: PaymentGateway
    private let locationRepository: DeviceLocationRepository
    private var acceptedRevision: Int64 = -1
    private var pendingAction: PendingDispatchAction?
    private var lastConfirmedSnapshot: PitTecDispatchSnapshot?
    private var isStarted = false
    /// Reproduzido em device físico real: o cliente ficou preso em "Procurando PitTec" depois de o
    /// provider aceitar — o broadcast do canal Realtime não chegou (ou chegou e foi perdido) e não
    /// havia nenhum fallback, ao contrário do checkout de pagamento (`observeApproval`). Sem isso, a
    /// confirmação do orçamento expira sozinha em 2 minutos (regra do backend) sem o cliente nunca
    /// ter visto o card. Mesmo padrão de poll de segurança já usado em `PaymentCheckoutViewModel`.
    private var pollTask: Task<Void, Never>?
    private let pollInterval: TimeInterval = 5

    init(
        serviceID: UUID,
        repository: PitTecRepository,
        paymentRepository: PaymentGateway,
        locationRepository: DeviceLocationRepository
    ) {
        self.serviceID = serviceID
        self.repository = repository
        self.paymentRepository = paymentRepository
        self.locationRepository = locationRepository
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        Task { [weak self] in
            guard let self else { return }
            switch await repository.getActiveDispatch() {
            case let .snapshot(snapshot) where snapshot.serviceID == serviceID:
                applySnapshot(snapshot)
                startPolling()
                subscribeToSearchInBackground(searchID: snapshot.searchID)
            default:
                await loadDiscovery()
            }
        }
    }

    func stop() {
        stopPolling()
        repository.disconnectAll()
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                // Aguarda a leitura aqui para impedir duas RPCs concorrentes. Uma resposta
                // antiga que chegasse depois da nova podia re-renderizar um status obsoleto.
                let result = await self.repository.getActiveDispatch()
                guard !Task.isCancelled else { return }
                self.applyIfChanged(result)
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func retry() {
        isStarted = false
        state = .restoring
        start()
    }

    private func loadDiscovery() async {
        switch locationRepository.authorizationStatus {
        case .denied, .restricted:
            state = .locationRequired(reason: .permissionDenied)
            return
        case .notDetermined:
            locationRepository.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            break
        }
        guard DeviceLocationServiceStatus.isEnabled else {
            state = .locationRequired(reason: .serviceDisabled)
            return
        }

        switch await locationRepository.requestOneShotFix(timeout: 15) {
        case let .success(fix):
            lastFix = fix
            switch await repository.listNearby(serviceID: serviceID, fix: fix) {
            case let .success(markers):
                state = .discovering(markers)
            case .failure:
                state = .failure(lastConfirmed: nil)
            }
        case .permissionDenied:
            state = .locationRequired(reason: .permissionDenied)
        case .serviceDisabled:
            state = .locationRequired(reason: .serviceDisabled)
        case .timeout:
            state = .locationRequired(reason: .timeout)
        case .failure:
            state = .locationRequired(reason: .unknown)
        }
    }

    /// `021`/migration `20260913010000` — busca começa sem nenhuma cobrança prévia (o pagamento só
    /// acontece depois do cliente confirmar o orçamento, em `AWAITING_PAYMENT`); usa a mesma posição
    /// já obtida para a descoberta, sem pedir um novo fix.
    func callPitTec() {
        guard case .discovering = state, let fix = lastFix else { return }
        Task { [weak self] in
            guard let self else { return }
            let result = await repository.startDispatch(requestID: UUID(), serviceID: serviceID, fix: fix)
            apply(result)
            if case let .snapshot(snapshot) = result {
                startPolling()
                subscribeToSearchInBackground(searchID: snapshot.searchID)
            }
        }
    }

    /// Reproduzido em device físico real: `subscribeWithError()` chegou a levar ~70s pra resolver
    /// neste projeto — como `startPolling()` rodava só depois do `await` dessa chamada, o fallback
    /// inteiro (criado justamente pra cobrir demora do Realtime) ficava inútil nesses mesmos ~70s.
    /// Inscrição roda à parte, sem bloquear o poll nem o resto do fluxo — é só um atalho de latência,
    /// nunca a única fonte de verdade.
    private func subscribeToSearchInBackground(searchID: UUID) {
        Task { [weak self] in
            await self?.repository.subscribeToSearch(searchID: searchID) { [weak self] in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    /// Antes do aceite, cancela a busca sem motivo (`cancelSearch`). A partir de `ACCEPTED`, exige
    /// `reason` e cancela o atendimento (`cancelAppointment`) — a View decide qual sheet mostrar via
    /// `requiresCancellationReason`.
    var requiresCancellationReason: Bool {
        guard let appointment = currentSnapshot?.appointment else { return false }
        return appointment.status == .accepted || appointment.status == .inProgress
    }

    func cancel(reason: String? = nil) {
        guard let snapshot = currentSnapshot, pendingAction == nil, snapshot.allowedActions.contains(.cancel) else { return }
        pendingAction = PendingDispatchAction(kind: .cancel(reason: reason ?? ""), expectedRevision: snapshot.revision)
        state = .content(snapshot, pendingAction: pendingAction)
        Task { [weak self] in
            guard let self else { return }
            let result: PitTecOperationResult
            if let appointment = snapshot.appointment, appointment.status == .accepted || appointment.status == .inProgress, let reason, !reason.isEmpty {
                result = await repository.cancelAppointment(appointmentID: appointment.appointmentID, reason: reason, expectedRevision: appointment.revision)
            } else {
                result = await repository.cancelSearch(searchID: snapshot.searchID, expectedRevision: snapshot.revision)
            }
            pendingAction = nil
            switch result {
            case .noActiveFlow:
                returnToDiscovery()
            case let .snapshot(snapshot) where snapshot.status.isTerminal:
                returnToDiscovery()
            default:
                apply(result)
            }
        }
    }

    private func returnToDiscovery() {
        pendingAction = nil
        acceptedRevision = -1
        lastConfirmedSnapshot = nil
        routeContext = nil
        stopPolling()
        repository.disconnectAll()
        Task { [weak self] in
            await self?.loadDiscovery()
        }
    }

    /// `021`/migration `20260913010000` — confirma o orçamento ofertado (`AWAITING_CLIENT_
    /// CONFIRMATION` → `AWAITING_PAYMENT`); o pagamento em si acontece à parte, quando a View abre
    /// `PaymentCheckoutView` para o status `AWAITING_PAYMENT`.
    func confirmQuote() {
        respondToQuote(accept: true)
    }

    /// Recusar cancela o atendimento com o motivo `QUOTE_DECLINED` já tratado pelo próprio backend
    /// — não reaproveita `cancel(reason:)`/`cancelAppointment`, que exigiria digitar um motivo.
    func declineQuote() {
        respondToQuote(accept: false)
    }

    private func respondToQuote(accept: Bool) {
        guard let snapshot = currentSnapshot,
              let appointment = snapshot.appointment,
              appointment.status == .awaitingClientConfirmation,
              pendingAction == nil else { return }
        // `respond_to_pittec_quote` compara `p_expected_revision` com a revisão da BUSCA
        // (`search_row.revision`), não com a do agendamento — confirmado lendo a RPC no banco depois
        // de reproduzir em device físico real um "Confirmar" que sempre voltava 200 OK sem nunca
        // aplicar nada (`client_confirmed_at` permanecia `null`). Antes mandava `appointment.revision`
        // aqui, que é um contador à parte e nunca bate com o da busca — todo toque virava
        // `REVISION_CONFLICT` silencioso (a RPC devolve o snapshot atual, indistinguível de um no-op
        // pra quem está olhando a tela).
        pendingAction = PendingDispatchAction(kind: accept ? .confirm : .cancel(reason: "QUOTE_DECLINED"), expectedRevision: snapshot.revision)
        state = .content(snapshot, pendingAction: pendingAction)
        Task { [weak self] in
            guard let self else { return }
            let result = await repository.respondToQuote(
                searchID: snapshot.searchID,
                appointmentID: appointment.appointmentID,
                quoteVersion: appointment.quoteVersion,
                accept: accept,
                expectedRevision: snapshot.revision
            )
            pendingAction = nil
            apply(result)
        }
    }

    /// `021` — chamado pela View quando o checkout de pagamento fecha aprovado. O trigger no backend
    /// já avança o atendimento para `ACCEPTED` sozinho (`reconcile_pittec_payment_change`); isto só
    /// garante que o snapshot mais recente chegue mesmo se o broadcast do canal ainda não tiver
    /// propagado no instante em que o sheet fecha.
    func refreshAfterPayment() {
        refresh()
    }

    private func refresh() {
        Task { [weak self] in
            guard let self else { return }
            applyIfChanged(await repository.getActiveDispatch())
        }
    }

    /// O backend pode atualizar appointment e busca no mesmo fluxo sem que todas as versões
    /// intermediárias sejam observadas pelo Realtime. O snapshot completo, e não apenas a revisão
    /// da busca, é a fonte de comparação do cliente.
    private func applyIfChanged(_ result: PitTecOperationResult) {
        switch result {
        case let .snapshot(snapshot):
            if snapshot != lastConfirmedSnapshot {
                applySnapshot(snapshot)
            } else {
                // A localização de acompanhamento muda sem alterar a revisão do dispatch.
                // Atualizar o contexto aqui evita manter uma distância antiga (inclusive 0 m).
                refreshRouteContextIfNeeded(snapshot)
            }
        case .noActiveFlow, .failure:
            apply(result)
        }
    }

    private func apply(_ result: PitTecOperationResult) {
        switch result {
        case let .snapshot(snapshot):
            applySnapshot(snapshot)
        case .noActiveFlow:
            // Reproduzido em device físico real: um poll (ou o retorno do próprio `respondToQuote`)
            // podia chegar depois de o atendimento já ter saído de "ativo" no servidor sem nunca ter
            // entregado um snapshot terminal antes disso — o código antigo só zerava pra `.restoring`
            // e desligava tudo (`isStarted = false`, poll parado), sem nenhuma ação de recuperação: a
            // tela ficava presa em "Carregando…" pra sempre, sem nem um jeito de voltar sozinha à
            // descoberta. Em vez de um beco sem saída, volta pra descoberta como se fosse uma entrada
            // nova na tela.
            stopPolling()
            repository.disconnectAll()
            Task { [weak self] in
                await self?.loadDiscovery()
            }
        case let .failure(reason):
            applyFailure(reason)
        }
    }

    private func applySnapshot(_ snapshot: PitTecDispatchSnapshot) {
        guard snapshot.revision >= acceptedRevision || snapshot.status.isTerminal || snapshot != lastConfirmedSnapshot else { return }
        acceptedRevision = snapshot.revision
        lastConfirmedSnapshot = snapshot
        if snapshot.status.isTerminal {
            state = .terminal(snapshot)
            routeContext = nil
            stopPolling()
            repository.disconnectAll()
            if snapshot.status == .cancelled || snapshot.status == .exhausted {
                checkRefund(searchID: snapshot.searchID)
            }
        } else {
            state = .content(snapshot, pendingAction: pendingAction)
            refreshRouteContextIfNeeded(snapshot)
        }
    }

    private func refreshRouteContextIfNeeded(_ snapshot: PitTecDispatchSnapshot) {
        guard let appointment = snapshot.appointment, appointment.status == .accepted || appointment.status == .inProgress else {
            routeContext = nil
            return
        }
        Task { [weak self] in
            guard let self else { return }
            if case let .ready(context) = await repository.routeContext(appointmentID: appointment.appointmentID) {
                routeContext = context
            }
        }
    }

    private func applyFailure(_ reason: PitTecFailureReason) {
        if reason == .sessionExpired {
            state = .sessionExpired
            stopPolling()
            repository.disconnectAll()
            return
        }
        state = .failure(lastConfirmed: lastConfirmedSnapshot)
    }

    private var currentSnapshot: PitTecDispatchSnapshot? {
        if case let .content(snapshot, _) = state { return snapshot }
        return nil
    }

    /// `018` FR-015/FR-017 — ver nota equivalente em `ClientMobileDispatchViewModel`.
    private func checkRefund(searchID: UUID) {
        Task { [weak self] in
            guard let self else { return }
            guard case let .found(paymentID, status, _) = await self.paymentRepository.status(requestID: searchID) else { return }
            switch status {
            case .refundPending:
                if case let .resolved(finalStatus) = await self.paymentRepository.refund(paymentID: paymentID) {
                    self.refundStatus = finalStatus
                }
            case .refunded, .refundFailed:
                self.refundStatus = status
            default:
                break
            }
        }
    }
}
