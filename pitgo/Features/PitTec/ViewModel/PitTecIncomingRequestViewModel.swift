//
//  PitTecIncomingRequestViewModel.swift
//  pitgo
//
//  Lado provider do PitTec (`015`) — mesmo `get_my_active_pittec_dispatch()` do cliente, mas o
//  snapshot retorna `offer` (distância aproximada + região, nunca nome/posição exata do cliente
//  antes do aceite) em vez de `candidate`.
//

import Combine
import CoreLocation
import Foundation

@MainActor
final class PitTecIncomingRequestViewModel: ObservableObject {
    @Published private(set) var state: ProviderDispatchUiStatePitTec = .noIncoming
    @Published private(set) var routeContext: PitTecRouteContext?
    /// Tick de 1s só para recompor o countdown (`014` FR-001) — nunca decide uma transição sozinho.
    @Published private(set) var localNow: Date = .init()

    private let providerID: UUID
    private let repository: PitTecRepository
    private var acceptedRevision: Int64 = -1
    private var pendingAction: PendingDispatchAction?
    private var isStarted = false
    private var countdownTask: Task<Void, Never>?
    /// Mesmo fallback de segurança de `PitTecClientViewModel` (reproduzido em device físico real: o
    /// cliente ficou preso esperando um broadcast que nunca chegou) — o lado provider depende só de
    /// `subscribeToProvider` sem nenhum poll de segurança.
    private var pollTask: Task<Void, Never>?
    private let pollInterval: TimeInterval = 5

    init(providerID: UUID, repository: PitTecRepository) {
        self.providerID = providerID
        self.repository = repository
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        Task { [weak self] in
            guard let self else { return }
            apply(await repository.getActiveDispatch())
            startPolling()
            subscribeToProviderInBackground()
        }
    }

    /// Mesmo bug/fix de `PitTecClientViewModel.subscribeToSearchInBackground` — `subscribeWithError()`
    /// chegou a levar ~70s pra resolver em device físico real; rodar depois dele fazia o próprio
    /// fallback de poll (criado pra cobrir essa demora) ficar inútil durante esses ~70s.
    private func subscribeToProviderInBackground() {
        Task { [weak self] in
            guard let self else { return }
            await self.repository.subscribeToProvider(providerID: self.providerID) { [weak self] in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    func stop() {
        stopCountdown()
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
                self.refresh()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func retry() {
        isStarted = false
        state = .noIncoming
        start()
    }

    /// FR-012: o navegador externo só está autorizado antes da chegada e usa a posição atual do
    /// cliente retornada por uma leitura autenticada nova.
    func externalNavigationDestination() async -> CLLocationCoordinate2D? {
        guard pendingAction == nil,
              case let .reserved(current, _) = state,
              let currentID = current.appointment?.appointmentID,
              current.appointment?.status == .accepted,
              !current.hasArrived else { return nil }

        guard case let .snapshot(latest) = await repository.getActiveDispatch(),
              latest.revision >= acceptedRevision,
              latest.appointment?.appointmentID == currentID,
              latest.appointment?.status == .accepted,
              !latest.hasArrived else { return nil }
        apply(.snapshot(latest))

        guard case let .ready(context) = await repository.routeContext(appointmentID: currentID),
              case let .reserved(currentSnapshot, _) = state,
              currentSnapshot.appointment?.appointmentID == currentID,
              currentSnapshot.appointment?.status == .accepted,
              !currentSnapshot.hasArrived else { return nil }
        let destination = CLLocationCoordinate2D(latitude: context.clientLatitude, longitude: context.clientLongitude)
        return ExternalNavigator.isValid(destination) ? destination : nil
    }

    private func refresh() {
        Task { [weak self] in
            guard let self else { return }
            apply(await repository.getActiveDispatch())
        }
    }

    func accept() { respond(accept: true) }
    func decline() { respond(accept: false) }

    private func respond(accept: Bool) {
        guard let appointment = currentPendingAppointment, pendingAction == nil else { return }
        run(accept ? .accept : .decline, expectedRevision: appointment.revision) { [repository] in
            await repository.respondPitTec(appointmentID: appointment.appointmentID, accept: accept, expectedRevision: appointment.revision)
        }
    }

    func arrive() {
        guard let (_, appointment) = currentReservedAppointment, pendingAction == nil else { return }
        run(.start, expectedRevision: appointment.revision) { [repository] in
            // Android envia um UUID da operação. O searchID identifica a busca e não
            // deve ser reutilizado como request_id da transição.
            // Reconsulta antes de enviar: a aprovação do pagamento também altera a
            // revisão do agendamento e o snapshot exibido pode ter ficado defasado.
            let latestAppointment: PitTecAppointment
            switch await repository.getActiveDispatch() {
            case let .snapshot(snapshot) where snapshot.appointment?.appointmentID == appointment.appointmentID:
                guard let refreshed = snapshot.appointment else { return .failure(.notFound) }
                latestAppointment = refreshed
            case let .failure(reason):
                return .failure(reason)
            default:
                return .failure(.notFound)
            }

            return await repository.arrive(
                requestID: UUID(),
                appointmentID: latestAppointment.appointmentID,
                expectedRevision: latestAppointment.revision
            )
        }
    }

    func startAppointment() {
        guard case let .reserved(snapshot, nil) = state,
              snapshot.hasArrived, snapshot.allowedActions.contains(.start),
              let appointment = snapshot.appointment, pendingAction == nil else { return }
        run(.start, expectedRevision: appointment.revision) { [repository] in
            await repository.startAppointment(appointmentID: appointment.appointmentID, expectedRevision: appointment.revision)
        }
    }

    func complete() {
        guard let (_, appointment) = currentReservedAppointment, pendingAction == nil else { return }
        run(.complete, expectedRevision: appointment.revision) { [repository] in
            await repository.completePitTec(appointmentID: appointment.appointmentID, expectedRevision: appointment.revision)
        }
    }

    func cancel(reason: String) {
        guard let (_, appointment) = currentReservedAppointment, pendingAction == nil else { return }
        run(.cancel(reason: reason), expectedRevision: appointment.revision) { [repository] in
            await repository.cancelAppointment(appointmentID: appointment.appointmentID, reason: reason, expectedRevision: appointment.revision)
        }
    }

    private func run(_ kind: DispatchActionKind, expectedRevision: Int64, _ operation: @escaping () async -> PitTecOperationResult) {
        pendingAction = PendingDispatchAction(kind: kind, expectedRevision: expectedRevision)
        reapplyPendingAction()
        Task { [weak self] in
            guard let self else { return }
            let result = await operation()
            pendingAction = nil
            apply(result)
        }
    }

    private func reapplyPendingAction() {
        switch state {
        case let .incoming(snapshot, _): state = .incoming(snapshot, pendingAction: pendingAction)
        case let .reserved(snapshot, _): state = .reserved(snapshot, pendingAction: pendingAction)
        default: break
        }
    }

    private func apply(_ result: PitTecOperationResult) {
        switch result {
        case let .snapshot(snapshot):
            applySnapshot(snapshot)
        case .noActiveFlow:
            state = .noIncoming
        case let .failure(reason):
            if reason == .sessionExpired {
                state = .sessionExpired
                stopPolling()
                repository.disconnectAll()
            } else {
                state = .failure(reason)
            }
        }
    }

    private func applySnapshot(_ snapshot: PitTecDispatchSnapshot) {
        guard snapshot.revision >= acceptedRevision else { return }
        acceptedRevision = snapshot.revision
        guard let appointment = snapshot.appointment else {
            state = .noIncoming
            routeContext = nil
            return
        }
        switch appointment.status {
        case .pending:
            state = .incoming(snapshot, pendingAction: pendingAction)
            routeContext = nil
            if appointment.responseDeadline != nil { startCountdownIfNeeded() } else { stopCountdown() }
        case .awaitingClientConfirmation, .awaitingPayment:
            // `021`/migration `20260913010000`: aceito, mas o cliente ainda não confirmou o
            // orçamento (ou já confirmou e falta só pagar) — sem posição exata ainda
            // (`client_current_locations` só existe a partir de `ACCEPTED`, quando o pagamento é
            // aprovado), então nenhum `routeContext` é buscado aqui.
            state = .reserved(snapshot, pendingAction: pendingAction)
            routeContext = nil
            stopCountdown()
        case .accepted, .inProgress:
            state = .reserved(snapshot, pendingAction: pendingAction)
            refreshRouteContext(appointmentID: appointment.appointmentID)
            stopCountdown()
        default:
            state = .noIncoming
            routeContext = nil
            stopCountdown()
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

    private func refreshRouteContext(appointmentID: UUID) {
        Task { [weak self] in
            guard let self else { return }
            if case let .ready(context) = await repository.routeContext(appointmentID: appointmentID) {
                routeContext = context
            }
        }
    }

    private var currentPendingAppointment: PitTecAppointment? {
        guard case let .incoming(snapshot, nil) = state else { return nil }
        return snapshot.appointment
    }

    private var currentReservedAppointment: (searchID: UUID, appointment: PitTecAppointment)? {
        guard case let .reserved(snapshot, nil) = state, let appointment = snapshot.appointment else { return nil }
        return (snapshot.searchID, appointment)
    }
}

enum ProviderDispatchUiStatePitTec: Equatable {
    case noIncoming
    case incoming(PitTecDispatchSnapshot, pendingAction: PendingDispatchAction?)
    case reserved(PitTecDispatchSnapshot, pendingAction: PendingDispatchAction?)
    case sessionExpired
    case failure(PitTecFailureReason)
}
