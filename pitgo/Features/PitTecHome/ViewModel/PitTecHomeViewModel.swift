//
//  PitTecHomeViewModel.swift
//  pitgo
//
//  Home dedicada da modalidade PitTec (`022`) — mapa + disponibilidade (aba Mapa), atendimento
//  ativo (aba Dados da corrida) e preço (aba Valores). Reaproveita as mesmas dependências e o mesmo
//  desenho de `ProviderDashboardViewModel` (tracker de descoberta, detecção de solicitação nova via
//  `PitTecRepository`), só com uma apresentação em abas em vez de um `ScrollView` único.
//

import Foundation

@Observable
@MainActor
final class PitTecHomeViewModel {
    private(set) var state: PitTecHomeUiState
    private(set) var selectedTab: PitTecHomeTab = .map
    private(set) var settingsFailure: ProviderSettingsFailureReason?
    private(set) var sessionExpired = false
    private(set) var pricingState: PitTecPricingLoadState = .loading
    /// Atendimento PitTec já aceito (ou aguardando confirmação/pagamento do cliente) — `nil` quando
    /// não há nenhum em andamento. Uma solicitação `PENDING` nova não passa por aqui, ver
    /// `pitTecAppointmentToOpen`.
    private(set) var activeAppointment: PitTecAppointment?
    /// Solicitação PitTec nova detectada para este provider — a View empurra
    /// `PitTecIncomingRequestView` quando este campo deixa de ser `nil`, independentemente da aba
    /// selecionada no momento (FR-010/SC-004).
    private(set) var pitTecAppointmentToOpen: UUID?

    let discoveryTracker: ProviderDiscoveryTracker

    private let repository: ProviderDashboardRepository
    private let pitTecRepository: PitTecRepository
    private let pricingRepository: PitTecPricingRepository
    private let accountID: UUID
    private var settingsTask: Task<Void, Never>?
    private var isObservingIncoming = false
    // Mesma guarda de `ProviderDashboardViewModel` (`014` FR-018): uma solicitação já dispensada
    // manualmente não deve reabrir sozinha por causa de um broadcast subsequente não relacionado.
    private var dismissedPitTecID: UUID?

    init(
        repository: ProviderDashboardRepository,
        snapshot: ProviderSnapshot,
        pitTecRepository: PitTecRepository,
        pricingRepository: PitTecPricingRepository,
        dispatchRepository: MobileDispatchRepository,
        locationRepository: DeviceLocationRepository
    ) {
        self.repository = repository
        self.pitTecRepository = pitTecRepository
        self.pricingRepository = pricingRepository
        accountID = snapshot.accountID
        state = .content(snapshot)
        discoveryTracker = ProviderDiscoveryTracker(locationRepository: locationRepository, dispatchRepository: dispatchRepository)
    }

    func selectTab(_ tab: PitTecHomeTab) {
        selectedTab = tab
    }

    /// Chamado uma vez em `.task` — mesma responsabilidade de `ProviderDashboardViewModel.onAppear`.
    func onAppear() {
        syncTracker()
        loadPricing()
        guard !isObservingIncoming else { return }
        isObservingIncoming = true
        Task { [weak self] in
            guard let self else { return }
            await refreshActiveDispatch()
            await pitTecRepository.subscribeToProvider(providerID: providerID) { [weak self] in
                Task { @MainActor in await self?.refreshActiveDispatch() }
            }
        }
    }

    func tearDown() {
        discoveryTracker.stop()
        pitTecRepository.disconnectAll()
        isObservingIncoming = false
    }

    /// Limpa a solicitação já tratada (aberta pela View) para não reabrir a mesma tela ao voltar.
    func acknowledgePitTecAppointment() {
        dismissedPitTecID = pitTecAppointmentToOpen
        pitTecAppointmentToOpen = nil
    }

    private var providerID: UUID {
        currentSnapshot?.provider.id ?? accountID
    }

    private func refreshActiveDispatch() async {
        switch await pitTecRepository.getActiveDispatch() {
        case let .snapshot(snapshot):
            guard let appointment = snapshot.appointment else {
                activeAppointment = nil
                return
            }
            switch appointment.status {
            case .pending:
                activeAppointment = nil
                if appointment.appointmentID != dismissedPitTecID {
                    pitTecAppointmentToOpen = appointment.appointmentID
                }
            case .awaitingClientConfirmation, .awaitingPayment, .accepted, .inProgress:
                activeAppointment = appointment
            default:
                activeAppointment = nil
            }
        case .noActiveFlow, .failure:
            activeAppointment = nil
        }
    }

    private func loadPricing() {
        pricingState = .loading
        Task { [weak self] in
            guard let self else { return }
            switch await pricingRepository.fetchPitTecPrice(providerID: providerID) {
            case let .success(info):
                pricingState = .loaded(info)
            case .notFound, .offline:
                pricingState = .failure
            }
        }
    }

    private func syncTracker() {
        guard let provider = currentSnapshot?.provider else { return }
        let shouldPublish = provider.active && provider.available
        if shouldPublish {
            discoveryTracker.start()
        } else {
            discoveryTracker.stop()
        }
    }

    func retry() {
        loadPricing()
        Task { [weak self] in await self?.refreshActiveDispatch() }
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

    var currentSnapshot: ProviderSnapshot? {
        switch state {
        case let .content(snapshot): snapshot
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
