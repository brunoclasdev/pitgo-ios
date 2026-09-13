//
//  ProviderDashboardViewModel.swift
//  pitgo
//

import Foundation

@Observable
@MainActor
final class ProviderDashboardViewModel {
    private(set) var state: ProviderDashboardUiState
    private(set) var settingsFailure: ProviderSettingsFailureReason?
    private(set) var sessionExpired = false
    /// Solicitação pendente detectada para este provider — a View navega automaticamente ao
    /// `ProviderIncomingRequestView` quando este campo deixa de ser `nil` (`013`).
    private(set) var incomingAppointmentID: UUID?
    /// Atendimento já reservado (`ACCEPTED`/`IN_PROGRESS`) detectado ao (re)abrir o dashboard — cobre
    /// a retomada do lado provider (contracts/mobile-dispatch-ui-navigation.md "Retomada",
    /// `.providerTracking`), já que o app pode ter sido encerrado enquanto o atendimento seguia.
    private(set) var resumedTrackingAppointmentID: UUID?
    /// Chamada PitTec (pendente OU já reservada) detectada para este provider — `015`. Uma única
    /// rota (`PitTecIncomingRequestView`) trata os dois casos internamente, então basta um sinal.
    private(set) var pitTecAppointmentToOpen: UUID?

    let discoveryTracker: ProviderDiscoveryTracker

    private let repository: ProviderDashboardRepository
    private let dispatchRepository: MobileDispatchRepository
    private let pitTecRepository: PitTecRepository
    private let accountID: UUID
    private var settingsTask: Task<Void, Never>?
    private var isObservingIncoming = false
    // Uma vez que a pessoa sai manualmente de uma dessas telas (voltar), o mesmo evento/appointment
    // não deve reabri-la sozinho — só uma solicitação/atendimento GENUINAMENTE novo o faz (`014`
    // FR-018, achado real desta sessão: sem esta guarda, qualquer Broadcast subsequente no mesmo
    // canal — inclusive um não relacionado — reaplicava o mesmo ID e a View reabria a rota).
    private var dismissedIncomingID: UUID?
    private var dismissedResumedTrackingID: UUID?
    private var dismissedPitTecID: UUID?

    init(
        repository: ProviderDashboardRepository,
        snapshot: ProviderSnapshot,
        dispatchRepository: MobileDispatchRepository,
        pitTecRepository: PitTecRepository,
        locationRepository: DeviceLocationRepository
    ) {
        self.repository = repository
        self.dispatchRepository = dispatchRepository
        self.pitTecRepository = pitTecRepository
        accountID = snapshot.accountID
        state = .content(snapshot)
        discoveryTracker = ProviderDiscoveryTracker(locationRepository: locationRepository, dispatchRepository: dispatchRepository)
    }

    /// Chamado uma vez em `.task` — sincroniza o tracker com a disponibilidade atual e passa a
    /// observar solicitações pendentes destinadas a este provider.
    func onAppear() {
        syncTracker()
        guard !isObservingIncoming else { return }
        isObservingIncoming = true
        Task { [weak self] in
            guard let self else { return }
            await checkIncoming()
            await checkPitTecIncoming()
            let providerID = accountIDForTopic
            await dispatchRepository.subscribeToProvider(providerID: providerID) { [weak self] in
                Task { @MainActor in await self?.checkIncoming() }
            }
            await pitTecRepository.subscribeToProvider(providerID: providerID) { [weak self] in
                Task { @MainActor in await self?.checkPitTecIncoming() }
            }
        }
    }

    /// Chamado quando a `View` raiz do dashboard sai de cena (troca/fim de sessão) — nunca ao
    /// apenas empurrar `ProviderIncomingRequestView` na mesma `NavigationStack`.
    func tearDown() {
        discoveryTracker.stop()
        dispatchRepository.disconnectAll()
        pitTecRepository.disconnectAll()
        isObservingIncoming = false
    }

    /// Limpa a solicitação já tratada (aberta pela View) para não reabrir a mesma tela ao voltar.
    func acknowledgeIncoming() {
        dismissedIncomingID = incomingAppointmentID
        incomingAppointmentID = nil
    }

    /// Limpa a retomada já tratada (aberta pela View) para não reempurrar a mesma rota ao voltar.
    func acknowledgeResumedTracking() {
        dismissedResumedTrackingID = resumedTrackingAppointmentID
        resumedTrackingAppointmentID = nil
    }

    func acknowledgePitTecAppointment() {
        dismissedPitTecID = pitTecAppointmentToOpen
        pitTecAppointmentToOpen = nil
    }

    private var accountIDForTopic: UUID {
        // O tópico privado usa o `providers.id`, não a conta Auth — mas `ProviderSnapshot` só
        // expõe o `Provider` completo dentro do `state`; resolvido abaixo com segurança.
        currentSnapshot?.provider.id ?? accountID
    }

    private func checkIncoming() async {
        switch await dispatchRepository.getActiveDispatch() {
        case let .snapshot(snapshot):
            guard let appointment = snapshot.appointment else { return }
            switch appointment.status {
            case .pending where appointment.appointmentID != dismissedIncomingID:
                incomingAppointmentID = appointment.appointmentID
            case .accepted, .inProgress:
                if appointment.appointmentID != dismissedResumedTrackingID {
                    resumedTrackingAppointmentID = appointment.appointmentID
                }
            default:
                break
            }
        case .noActiveFlow, .failure:
            break
        }
    }

    private func checkPitTecIncoming() async {
        if case let .snapshot(snapshot) = await pitTecRepository.getActiveDispatch(),
           let appointment = snapshot.appointment, appointment.appointmentID != dismissedPitTecID {
            pitTecAppointmentToOpen = appointment.appointmentID
        }
    }

    private func syncTracker() {
        guard let provider = currentSnapshot?.provider else { return }
        // `ProviderDiscoveryTracker` (`013`) já publica via `publish_mobile_provider_location`, que
        // aceita `location_mode in ('MOBILE','PITTEC')` no servidor (confirmado nesta sessão) — o
        // mesmo tracker serve as duas modalidades sem nenhuma mudança.
        let shouldPublish = provider.active && provider.available
            && (provider.locationMode == .mobile || provider.locationMode == .pittec)
        if shouldPublish {
            discoveryTracker.start()
        } else {
            discoveryTracker.stop()
        }
    }

    func retry() {
        guard let snapshot = currentSnapshot else { return }
        state = .refreshing(snapshot)
        Task { [weak self] in
            guard let self else { return }
            switch await repository.fetchProvider(accountID: accountID) {
            case let .success(provider):
                state = .content(makeSnapshot(replacing: provider))
                syncTracker()
            case .notFound:
                state = .failure(.unknown)
            case .offline:
                state = .failure(.offline)
            }
        }
    }

    func setMode(_ mode: ProviderLocationMode) {
        guard let snapshot = currentSnapshot, snapshot.provider.locationMode != mode else { return }
        settingsFailure = nil
        settingsTask?.cancel()
        settingsTask = Task { [weak self] in
            guard let self else { return }
            let result = await repository.setMode(mode)
            if Task.isCancelled { return }
            apply(result)
        }
    }

    func setAvailability(_ available: Bool) {
        guard let snapshot = currentSnapshot, snapshot.provider.available != available else { return }
        settingsFailure = nil
        settingsTask?.cancel()
        settingsTask = Task { [weak self] in
            guard let self else { return }
            let result = await repository.setAvailability(available)
            if Task.isCancelled { return }
            apply(result)
        }
    }

    private func apply(_ result: ProviderSettingsResult) {
        switch result {
        case let .success(provider):
            state = .content(makeSnapshot(replacing: provider))
            syncTracker()
        case .sessionExpired:
            sessionExpired = true
            tearDown()
        case .offline:
            settingsFailure = .offline
        case .service:
            settingsFailure = .service
        case .unknown:
            settingsFailure = .unknown
        }
    }

    private var currentSnapshot: ProviderSnapshot? {
        switch state {
        case let .content(snapshot), let .refreshing(snapshot): snapshot
        case .failure: nil
        }
    }

    private func makeSnapshot(replacing provider: Provider) -> ProviderSnapshot {
        guard let current = currentSnapshot else {
            return ProviderSnapshot(accountID: accountID, authEmail: "", provider: provider, legacyMigrationAvailable: false)
        }
        return ProviderSnapshot(
            accountID: current.accountID,
            authEmail: current.authEmail,
            provider: provider,
            legacyMigrationAvailable: current.legacyMigrationAvailable
        )
    }
}
