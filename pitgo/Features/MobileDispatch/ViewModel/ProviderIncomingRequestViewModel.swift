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
import Foundation

@MainActor
final class ProviderIncomingRequestViewModel: ObservableObject {
    @Published private(set) var state: ProviderDispatchUiState = .noIncoming
    /// Referência local só para recalcular o texto do countdown a cada segundo — nunca decide uma
    /// transição de estado sozinha.
    @Published private(set) var localNow: Date = .init()

    private let repository: MobileDispatchRepository
    private let providerID: UUID
    private var acceptedRevision: Int64 = -1
    private var pendingAction: PendingDispatchAction?
    private var lastConfirmedSnapshot: MobileDispatchSnapshot?
    private var countdownTask: Task<Void, Never>?
    private var isStarted = false

    init(providerID: UUID, repository: MobileDispatchRepository) {
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
        countdownTask?.cancel()
        countdownTask = nil
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
            state = .noIncoming
            countdownTask?.cancel()
            countdownTask = nil
        case let .failure(reason):
            if reason == .sessionExpired {
                state = .sessionExpired
                repository.disconnectAll()
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
        case .accepted, .inProgress:
            state = .reserved(snapshot, pendingAction: pendingAction)
            countdownTask?.cancel()
            countdownTask = nil
        default:
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
