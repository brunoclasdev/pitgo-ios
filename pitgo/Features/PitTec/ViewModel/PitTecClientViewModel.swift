//
//  PitTecClientViewModel.swift
//  pitgo
//
//  Sempre consulta `get_my_active_pittec_dispatch()` primeiro (idempotente e barato) antes de
//  mostrar a descoberta — cobre "abrir o card" e "retomar" com o mesmo caminho, mesma técnica de
//  `ClientMobileDispatchViewModel` (`013`).
//

import Foundation

@Observable
@MainActor
final class PitTecClientViewModel {
    private(set) var state: PitTecClientUiState = .restoring
    /// Duas posições correntes para a linha estimada (FR-022/FR-023) — `nil` antes do aceite ou
    /// enquanto a leitura ainda não chegou.
    private(set) var routeContext: PitTecRouteContext?
    /// `018` FR-015/FR-017 — ver nota equivalente em `ClientMobileDispatchViewModel`.
    private(set) var refundStatus: PaymentStatus?
    /// `020` FR-001/FR-002 — o mesmo fix já usado por `callPitTec`, exposto para a View centralizar
    /// o mapa na posição do cliente em qualquer estado de descoberta/busca, com ou sem PitTec.
    private(set) var lastFix: DeviceLocationFix?

    private let serviceID: UUID
    private let repository: PitTecRepository
    private let paymentRepository: PaymentRepository
    private let locationRepository: DeviceLocationRepository
    private var acceptedRevision: Int64 = -1
    private var pendingAction: PendingDispatchAction?
    private var lastConfirmedSnapshot: PitTecDispatchSnapshot?
    private var isStarted = false

    init(
        serviceID: UUID,
        repository: PitTecRepository,
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
            case let .snapshot(snapshot) where snapshot.serviceID == serviceID:
                applySnapshot(snapshot)
                await repository.subscribeToSearch(searchID: snapshot.searchID) { [weak self] in
                    Task { @MainActor in self?.refresh() }
                }
            default:
                await loadDiscovery()
            }
        }
    }

    func stop() {
        repository.disconnectAll()
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
                await repository.subscribeToSearch(searchID: snapshot.searchID) { [weak self] in
                    Task { @MainActor in self?.refresh() }
                }
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
            apply(result)
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
        pendingAction = PendingDispatchAction(kind: accept ? .confirm : .cancel(reason: "QUOTE_DECLINED"), expectedRevision: appointment.revision)
        state = .content(snapshot, pendingAction: pendingAction)
        Task { [weak self] in
            guard let self else { return }
            let result = await repository.respondToQuote(
                searchID: snapshot.searchID,
                appointmentID: appointment.appointmentID,
                quoteVersion: appointment.quoteVersion,
                accept: accept,
                expectedRevision: appointment.revision
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
            apply(await repository.getActiveDispatch())
        }
    }

    private func apply(_ result: PitTecOperationResult) {
        switch result {
        case let .snapshot(snapshot):
            applySnapshot(snapshot)
        case .noActiveFlow:
            state = .restoring
            isStarted = false
        case let .failure(reason):
            applyFailure(reason)
        }
    }

    private func applySnapshot(_ snapshot: PitTecDispatchSnapshot) {
        guard snapshot.revision >= acceptedRevision || snapshot.status.isTerminal else { return }
        acceptedRevision = snapshot.revision
        lastConfirmedSnapshot = snapshot
        if snapshot.status.isTerminal {
            state = .terminal(snapshot)
            routeContext = nil
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
