//
//  PitTecIncomingRequestViewModel.swift
//  pitgo
//
//  Lado provider do PitTec (`015`) — mesmo `get_my_active_pittec_dispatch()` do cliente, mas o
//  snapshot retorna `offer` (distância aproximada + região, nunca nome/posição exata do cliente
//  antes do aceite) em vez de `candidate`.
//

import Foundation

@Observable
@MainActor
final class PitTecIncomingRequestViewModel {
    private(set) var state: ProviderDispatchUiStatePitTec = .noIncoming
    private(set) var routeContext: PitTecRouteContext?
    /// Tick de 1s só para recompor o countdown (`014` FR-001) — nunca decide uma transição sozinho.
    private(set) var localNow: Date = .init()

    private let providerID: UUID
    private let repository: PitTecRepository
    private var acceptedRevision: Int64 = -1
    private var pendingAction: PendingDispatchAction?
    private var isStarted = false
    private var countdownTask: Task<Void, Never>?

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
            await repository.subscribeToProvider(providerID: providerID) { [weak self] in
                Task { @MainActor in self?.refresh() }
            }
        }
    }

    func stop() {
        stopCountdown()
        repository.disconnectAll()
    }

    func retry() {
        isStarted = false
        state = .noIncoming
        start()
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
        guard let (searchID, appointment) = currentReservedAppointment, pendingAction == nil else { return }
        run(.start, expectedRevision: appointment.revision) { [repository] in
            await repository.arrive(requestID: searchID, appointmentID: appointment.appointmentID, expectedRevision: appointment.revision)
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
                repository.disconnectAll()
            } else {
                state = .failure
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
    case failure
}
