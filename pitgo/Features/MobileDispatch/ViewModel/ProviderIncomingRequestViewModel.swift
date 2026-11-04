//
//  ProviderIncomingRequestViewModel.swift
//  pitgo
//
//  Lado provider do mesmo `MobileDispatchSnapshot` — `get_my_active_mobile_dispatch()` também serve
//  o provider (retorna a solicitação `PENDING` ou o atendimento reservado). O countdown é derivado
//  de `responseDeadline`/`serverNow`; um `Task.sleep` de 1s só reflete a UI local — a transição real
//  (expiração) é sempre do servidor (contracts/mobile-dispatch-realtime.md "Snapshot versus
//  countdown").
//

import Combine
import CoreLocation
import Foundation

@MainActor
final class ProviderIncomingRequestViewModel: ObservableObject {
    @Published private(set) var state: ProviderDispatchUiState = .noIncoming
    /// Referência local só para recalcular o texto do countdown a cada segundo — nunca decide uma
    /// transição de estado sozinha.
    @Published private(set) var localNow: Date = .init()
    /// Sinaliza somente o encerramento de um fluxo Guincho que esta instância chegou a apresentar.
    @Published private(set) var didFinishGuincho = false

    private let repository: MobileDispatchRepository
    private let providerID: UUID
    private var acceptedRevision: Int64 = -1
    private var pendingAction: PendingDispatchAction?
    private var lastConfirmedSnapshot: MobileDispatchSnapshot?
    private var countdownTask: Task<Void, Never>?
    private var isStarted = false
    private var pollTask: Task<Void, Never>?
    private var subscriptionTask: Task<Void, Never>?
    private var isRefreshing = false
    private var generation = UUID()

    init(providerID: UUID, repository: MobileDispatchRepository) {
        self.providerID = providerID
        self.repository = repository
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        let generation = UUID()
        self.generation = generation
        // Poll independently of Realtime. Inspection approval need not emit a provider event.
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.generation == generation, isStarted {
                await refreshSnapshot()
                do { try await Task.sleep(nanoseconds: 3_000_000_000) }
                catch { return }
            }
        }
        subscriptionTask = Task { [weak self] in
            guard let self, self.generation == generation, isStarted else { return }
            await repository.subscribeToProvider(providerID: providerID) { [weak self] in
                Task { @MainActor in
                    guard let self, self.generation == generation, self.isStarted else { return }
                    await self.refreshSnapshot()
                }
            }
        }
    }

    func stop() {
        isStarted = false
        generation = UUID()
        pollTask?.cancel()
        pollTask = nil
        subscriptionTask?.cancel()
        subscriptionTask = nil
        countdownTask?.cancel()
        countdownTask = nil
        repository.disconnectAll()
    }

    func retry() {
        stop()
        state = .noIncoming
        start()
    }

    private func refresh() {
        Task { [weak self] in await self?.refreshSnapshot() }
    }

    private func refreshSnapshot() async {
        guard isStarted, !isRefreshing, pendingAction == nil else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let generation = generation
        let result: MobileDispatchOperationResult
        if let known = lastConfirmedSnapshot, known.dispatchKind == .guinchoDirect,
           let appointmentID = known.appointment?.appointmentID {
            result = await repository.getGuinchoSnapshot(appointmentID: appointmentID)
        } else {
            result = await repository.getActiveDispatch()
        }
        guard !Task.isCancelled, self.generation == generation, isStarted, pendingAction == nil else { return }
        switch result {
        case .failure(.sessionExpired): apply(result)
        case .failure where lastConfirmedSnapshot != nil: break // Keep the last valid card during a network interruption.
        default: apply(result)
        }
    }

    func refreshNow() { refresh() }

    /// Revalida autorização, estado e destino no snapshot mais recente antes de abrir um navegador.
    func externalNavigationDestination() async -> CLLocationCoordinate2D? {
        guard pendingAction == nil,
              case let .reserved(current, _) = state,
              current.dispatchKind == .guinchoDirect,
              let currentID = current.appointment?.appointmentID else { return nil }

        guard case let .snapshot(latest) = await repository.getActiveDispatch(),
              latest.revision >= acceptedRevision else { return nil }
        apply(.snapshot(latest))
        guard case let .reserved(confirmed, nil) = state,
              confirmed.revision >= latest.revision,
              confirmed.dispatchKind == .guinchoDirect,
              confirmed.trackingAuthorized,
              confirmed.appointment?.appointmentID == currentID,
              let appointment = confirmed.appointment,
              appointment.status == .accepted || appointment.status == .inProgress,
              let trip = confirmed.guinchoTrip else { return nil }

        let destination = appointment.status == .accepted ? trip.pickup : trip.destination
        return ExternalNavigator.isValid(destination) ? destination : nil
    }

    // MARK: - Ações

    func accept() {
        respond(accept: true)
    }

    func decline() {
        respond(accept: false)
    }

    private func respond(accept: Bool) {
        guard let (snapshot, appointment) = currentPending, pendingAction == nil else { return }
        run(accept ? .accept : .decline, expectedRevision: appointment.revision) { [repository] in
            await repository.respond(appointmentID: appointment.appointmentID, accept: accept, expectedRevision: appointment.revision)
        }
        _ = snapshot
    }

    func startAppointment() {
        guard let (_, appointment) = currentReserved, pendingAction == nil else { return }
        run(.start, expectedRevision: appointment.revision) { [repository] in
            await repository.startAppointment(appointmentID: appointment.appointmentID, expectedRevision: appointment.revision)
        }
    }

    func complete() {
        guard let (_, appointment) = currentReserved, pendingAction == nil else { return }
        run(.complete, expectedRevision: appointment.revision) { [repository] in
            await repository.completeAppointment(appointmentID: appointment.appointmentID, expectedRevision: appointment.revision)
        }
    }

    /// `028` — guincheiro registra a chegada à retirada (`ACCEPTED`, `arrivedAt == nil`).
    func arrive() {
        guard let (_, appointment) = currentReserved, pendingAction == nil else { return }
        run(.arrive, expectedRevision: appointment.revision) { [repository] in
            await repository.arriveGuincho(appointmentID: appointment.appointmentID, expectedRevision: appointment.revision)
        }
    }

    /// `028` — guincheiro inicia o transporte após a chegada (`ACCEPTED`, `arrivedAt != nil`).
    func startTransport() {
        guard let (snapshot, appointment) = currentReserved, pendingAction == nil else { return }
        guard snapshot.canStartGuinchoTransport else { refresh(); return }
        run(.start, expectedRevision: appointment.revision) { [repository] in
            await repository.startGuinchoTransport(appointmentID: appointment.appointmentID, expectedRevision: appointment.revision)
        }
    }

    func cancel(reason: String) {
        guard let (_, appointment) = currentReserved, pendingAction == nil else { return }
        run(.cancel(reason: reason), expectedRevision: appointment.revision) { [repository] in
            await repository.cancelAppointment(appointmentID: appointment.appointmentID, reason: reason, expectedRevision: appointment.revision)
        }
    }

    private func run(_ kind: DispatchActionKind, expectedRevision: Int64, _ operation: @escaping () async -> MobileDispatchOperationResult) {
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

    // MARK: - Aplicação

    private func apply(_ result: MobileDispatchOperationResult) {
        switch result {
        case let .snapshot(snapshot):
            applySnapshot(snapshot)
        case .noActiveFlow:
            if lastConfirmedSnapshot?.dispatchKind == .guinchoDirect {
                didFinishGuincho = true
                stop()
            }
            state = .noIncoming
            countdownTask?.cancel()
            countdownTask = nil
        case let .failure(reason):
            if reason == .sessionExpired {
                state = .sessionExpired
                stop()
            } else {
                state = .failure(lastConfirmed: lastConfirmedSnapshot)
            }
        }
    }

    private func applySnapshot(_ snapshot: MobileDispatchSnapshot) {
        guard snapshot.revision >= acceptedRevision else { return }
        acceptedRevision = snapshot.revision
        lastConfirmedSnapshot = snapshot

        guard let appointment = snapshot.appointment else {
            state = .noIncoming
            countdownTask?.cancel()
            countdownTask = nil
            return
        }

        switch appointment.status {
        case .pending:
            state = .incoming(snapshot, pendingAction: pendingAction)
            startCountdownIfNeeded()
        case .awaitingPayment, .awaitingClientConfirmation, .accepted, .inProgress, .awaitingClientCompletionConfirmation, .disputed:
            // `028`: aguardando confirmação do cliente ou em contestação continuam "reservados" do
            // ponto de vista do prestador — cada estado decide suas próprias ações na View.
            state = .reserved(snapshot, pendingAction: pendingAction)
            countdownTask?.cancel()
            countdownTask = nil
        default:
            if snapshot.dispatchKind == .guinchoDirect {
                didFinishGuincho = true
                stop()
            }
            state = .noIncoming
            countdownTask?.cancel()
            countdownTask = nil
        }
    }

    private func startCountdownIfNeeded() {
        guard countdownTask == nil else { return }
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                localNow = Date()
                // Ao chegar em zero, pede um snapshot novo — só o servidor decide EXPIRED.
                if let deadline = self.currentDeadline, deadline <= self.localNow {
                    self.refresh()
                }
            }
        }
    }

    private var currentDeadline: Date? {
        if case let .incoming(snapshot, _) = state { return snapshot.appointment?.responseDeadline }
        return nil
    }

    private var currentPending: (MobileDispatchSnapshot, DispatchAppointment)? {
        guard case let .incoming(snapshot, nil) = state, let appointment = snapshot.appointment else { return nil }
        return (snapshot, appointment)
    }

    private var currentReserved: (MobileDispatchSnapshot, DispatchAppointment)? {
        guard case let .reserved(snapshot, nil) = state, let appointment = snapshot.appointment else { return nil }
        return (snapshot, appointment)
    }
}
