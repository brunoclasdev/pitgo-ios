//
//  ClientMobileDispatchViewModel.swift
//  pitgo
//
//  Sempre consulta `get_my_active_mobile_dispatch()` primeiro (idempotente e barato) antes de
//  iniciar uma busca nova — isso cobre "nova busca" e "retomada" com o mesmo caminho de código,
//  exatamente como o contrato descreve para `start_mobile_dispatch` (mesma busca ativa é retornada
//  mesmo com outra chave de idempotência).
//
//  NOTA (`013`, achado desta sessão): não existe RPC para cancelar uma busca ANTES de existir um
//  `appointment` (estados `SEARCHING`/`OPTION_FOUND`) — apenas `cancel_mobile_appointment`, que
//  exige `p_appointment_id`. `dispatch_snapshot` inclui `CANCEL` em `allowed_actions` mesmo nesses
//  estados, mas isso só pode significar "sair da tela", não uma mutação de servidor. `cancel(reason:)`
//  reflete essa distinção real: com `appointment` presente, cancela via RPC (motivo obrigatório);
//  sem `appointment`, apenas para de observar e devolve controle à View (a busca permanece ativa no
//  servidor e é retomada normalmente se a mesma tela for reaberta).
//

import Foundation

@Observable
@MainActor
final class ClientMobileDispatchViewModel {
    private(set) var state: ClientMobileDispatchUiState = .restoring
    /// Tick de 1s só para recompor o countdown (`014` FR-001) — nunca decide uma transição sozinho.
    private(set) var localNow: Date = .init()
    /// `018` FR-015/FR-017 — preenchido depois de um cancelamento/exaustão com pagamento aprovado
    /// associado; `nil` quando não havia nada a estornar. Não há trigger/cron server-side que chame
    /// `mp-refund-payment` sozinho (confirmado nesta sessão) — o app dispara ao ver `REFUND_PENDING`.
    private(set) var refundStatus: PaymentStatus?

    private let repository: MobileDispatchRepository
    private let paymentRepository: PaymentRepository
    private let locationRepository: DeviceLocationRepository
    /// `nil` numa retomada (`PitGoRoute.mobileDispatchSearch`) — `get_my_active_mobile_dispatch()`
    /// não recebe `serviceID`, então a sessão já basta; sem ele, uma busca nova nunca é iniciada
    /// (não haveria como saber qual serviço buscar).
    private let serviceID: UUID?
    private var acceptedRevision: Int64 = -1
    private var pendingAction: PendingDispatchAction?
    private var lastConfirmedSnapshot: MobileDispatchSnapshot?
    private var isStarted = false
    private var countdownTask: Task<Void, Never>?
    /// `018`: guardado assim que o checkout aprova, para que um "Tentar novamente" após falha de
    /// localização (`.locationRequired`) reuse a mesma cobrança em vez de pedir pagamento de novo.
    private var reservedPaidSearchID: UUID?

    init(
        serviceID: UUID?,
        repository: MobileDispatchRepository,
        paymentRepository: PaymentRepository,
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
            case let .snapshot(snapshot) where serviceID == nil || snapshot.serviceID == serviceID:
                applySnapshot(snapshot)
                await repository.subscribeToSearch(searchID: snapshot.searchID) { [weak self] in
                    Task { @MainActor in self?.refresh() }
                }
            default:
                if let serviceID {
                    if let reservedPaidSearchID {
                        // Já pago nesta instância (ex.: retomada após falha de localização) — não
                        // pede pagamento de novo para o mesmo `searchID`.
                        await beginNewSearch(paidSearchID: reservedPaidSearchID)
                    } else {
                        // `018`: `start_mobile_dispatch` exige pagamento aprovado prévio — a View
                        // apresenta o checkout antes de gerar qualquer `searchID`.
                        state = .paymentRequired(serviceID: serviceID)
                    }
                } else {
                    // Retomada sem busca ativa correspondente — nada a reabrir.
                    state = .failure(.notFound, lastConfirmed: nil)
                }
            }
        }
    }

    func stop() {
        stopCountdown()
        repository.disconnectAll()
    }

    func retry() {
        isStarted = false
        state = .restoring
        start()
    }

    /// Chamado pela View depois que `PaymentCheckoutView` chega a `.approved` — `searchID` É o
    /// `requestID` que o checkout usou para pagar (`payments.request_id = p_search_id`, verificado
    /// contra `start_mobile_dispatch` real nesta sessão).
    func beginPaidSearch(searchID: UUID) {
        reservedPaidSearchID = searchID
        Task { [weak self] in
            await self?.beginNewSearch(paidSearchID: searchID)
        }
    }

    private func beginNewSearch(paidSearchID: UUID) async {
        guard let serviceID else { return }
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
            let result = await repository.startSearch(
                searchID: paidSearchID,
                serviceID: serviceID,
                latitude: fix.latitude,
                longitude: fix.longitude,
                accuracyMeters: fix.horizontalAccuracy
            )
            apply(result)
            if case let .snapshot(snapshot) = result {
                await repository.subscribeToSearch(searchID: snapshot.searchID) { [weak self] in
                    Task { @MainActor in self?.refresh() }
                }
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

    private func refresh() {
        Task { [weak self] in
            guard let self else { return }
            apply(await repository.getActiveDispatch())
        }
    }

    // MARK: - Ações

    func requestNext() {
        guard let snapshot = currentSnapshot, pendingAction == nil, snapshot.allowedActions.contains(.next) else { return }
        run(.next, expectedRevision: snapshot.revision) { [repository] in
            await repository.nextCandidate(searchID: snapshot.searchID, expectedRevision: snapshot.revision)
        }
    }

    func requestCandidate() {
        guard let snapshot = currentSnapshot, pendingAction == nil, snapshot.allowedActions.contains(.request) else { return }
        run(.request, expectedRevision: snapshot.revision) { [repository] in
            await repository.requestCandidate(searchID: snapshot.searchID, expectedRevision: snapshot.revision)
        }
    }

    /// `true` quando cancelar exige o `.sheet` de motivo (já existe um `appointment`); `false`
    /// quando é apenas sair da tela sem afetar o servidor (ver nota acima).
    var cancelRequiresReason: Bool {
        currentSnapshot?.appointment != nil
    }

    func cancel(reason: String) {
        guard let snapshot = currentSnapshot, pendingAction == nil, snapshot.allowedActions.contains(.cancel),
              let appointment = snapshot.appointment else { return }
        run(.cancel(reason: reason), expectedRevision: appointment.revision) { [repository] in
            await repository.cancelAppointment(appointmentID: appointment.appointmentID, reason: reason, expectedRevision: appointment.revision)
        }
    }

    private func run(_ kind: DispatchActionKind, expectedRevision: Int64, _ operation: @escaping () async -> MobileDispatchOperationResult) {
        guard case let .content(snapshot, nil) = state else { return }
        pendingAction = PendingDispatchAction(kind: kind, expectedRevision: expectedRevision)
        state = .content(snapshot, pendingAction: pendingAction)
        Task { [weak self] in
            guard let self else { return }
            let result = await operation()
            pendingAction = nil
            apply(result)
        }
    }

    // MARK: - Aplicação

    private func apply(_ result: MobileDispatchOperationResult) {
        switch result {
        case let .snapshot(snapshot):
            applySnapshot(snapshot)
        case .noActiveFlow:
            // Sem fluxo ativo (ex.: expirou/foi concluído noutra sessão) — nada a preservar.
            state = .restoring
            isStarted = false
        case let .failure(reason):
            applyFailure(reason)
        }
    }

    private func applySnapshot(_ snapshot: MobileDispatchSnapshot) {
        // Uma resposta antiga não pode reviver um estado já superado — mesma proteção de revisão
        // de `009`/`010`. Estados terminais sempre são aceitos (encerram a tela de qualquer forma).
        guard snapshot.revision >= acceptedRevision || snapshot.status.isTerminal else { return }
        acceptedRevision = snapshot.revision
        lastConfirmedSnapshot = snapshot

        if snapshot.status.isTerminal {
            state = .terminal(snapshot)
            repository.disconnectAll()
            stopCountdown()
            if snapshot.status == .cancelled || snapshot.status == .exhausted {
                checkRefund(searchID: snapshot.searchID)
            }
        } else {
            state = .content(snapshot, pendingAction: pendingAction)
            if snapshot.status == .awaitingProvider, snapshot.appointment?.responseDeadline != nil {
                startCountdownIfNeeded()
            } else {
                stopCountdown()
            }
        }
    }

    private func startCountdownIfNeeded() {
        guard countdownTask == nil else { return }
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                localNow = Date()
            }
        }
    }

    private func stopCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    private func applyFailure(_ reason: MobileDispatchFailureReason) {
        if reason == .sessionExpired {
            state = .sessionExpired
            repository.disconnectAll()
            return
        }
        state = .failure(mapFailure(reason), lastConfirmed: lastConfirmedSnapshot)
    }

    private func mapFailure(_ reason: MobileDispatchFailureReason) -> ClientMobileDispatchFailureReason {
        switch reason {
        case .offline: .offline
        case .timeout: .timeout
        case .sessionExpired: .sessionExpired
        case .paymentRequired: .paymentRequired
        case .notFound: .notFound
        case .serviceUnavailable: .serviceUnavailable
        case .contract: .contract
        case .unknown: .unknown
        }
    }

    private var currentSnapshot: MobileDispatchSnapshot? {
        if case let .content(snapshot, _) = state { return snapshot }
        return nil
    }

    /// `018` FR-015/FR-017 — `searchID` é o mesmo `request_id` usado por `mp-create-payment`. Sem
    /// pagamento aprovado associado (`.notFound`, ou qualquer status que não seja de estorno), não
    /// há nada a fazer aqui.
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
