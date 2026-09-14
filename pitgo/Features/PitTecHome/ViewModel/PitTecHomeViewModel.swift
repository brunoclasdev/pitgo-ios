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
    /// `022` fix: o tracker de publicação (`discoveryTracker`) só roda enquanto "Disponível" está
    /// ligado (`syncTracker`) — com o provider indisponível, `lastFix` nunca era preenchido e a aba
    /// Mapa ficava presa para sempre em "Obtendo localização…". Fix único pedido sob demanda (mesmo
    /// padrão de `PitTecClientViewModel.lastFix`) só para centralizar o mapa nesse caso, sem iniciar
    /// um segundo stream contínuo nem publicar nada.
    private(set) var mapFix: DeviceLocationFix?
    private(set) var mapFixFailure: LocationRequiredReason?

    let discoveryTracker: ProviderDiscoveryTracker

    private let repository: ProviderDashboardRepository
    private let pitTecRepository: PitTecRepository
    private let pricingRepository: PitTecPricingRepository
    private let locationRepository: DeviceLocationRepository
    private let accountID: UUID
    private var settingsTask: Task<Void, Never>?
    private var isObservingIncoming = false
    // Mesma guarda de `ProviderDashboardViewModel` (`014` FR-018): uma solicitação já dispensada
    // manualmente não deve reabrir sozinha por causa de um broadcast subsequente não relacionado.
    private var dismissedPitTecID: UUID?
    /// Reproduzido em device físico real: uma solicitação nova só aparecia depois de fechar e
    /// reabrir o app — o broadcast de `provider-dispatch:<providerID>` não chegava (mesma classe de
    /// falha já documentada em `PitTecClientViewModel`/`PaymentCheckoutViewModel`: `subscribeWithError()`
    /// pode levar dezenas de segundos, ou o evento simplesmente se perde) e não havia nenhum
    /// fallback aqui do lado provider. Poll de segurança abaixo, nunca a única fonte de verdade.
    private var pollTask: Task<Void, Never>?
    private let pollInterval: TimeInterval = 5

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
        self.locationRepository = locationRepository
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
        loadMapFixIfNeeded()
        loadPricing()
        guard !isObservingIncoming else { return }
        isObservingIncoming = true
        Task { [weak self] in
            guard let self else { return }
            await refreshActiveDispatch()
            subscribeToProviderInBackground()
            startPolling()
        }
    }

    func tearDown() {
        stopPolling()
        discoveryTracker.stop()
        pitTecRepository.disconnectAll()
        isObservingIncoming = false
    }

    /// Roda à parte do resto de `onAppear` — mesmo achado de `PitTecClientViewModel.
    /// subscribeToSearchInBackground`: se essa chamada bloqueasse `onAppear`, o poll de segurança
    /// (que existe justamente para cobrir a demora/perda dela) ficaria inútil enquanto ela não
    /// resolve.
    private func subscribeToProviderInBackground() {
        Task { [weak self] in
            guard let self else { return }
            await pitTecRepository.subscribeToProvider(providerID: providerID) { [weak self] in
                Task { @MainActor in await self?.refreshActiveDispatch() }
            }
        }
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self.refreshActiveDispatch()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
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

    /// `022` fix — ver nota em `mapFix`. Só pede um fix quando nem o tracker de publicação nem um
    /// fix anterior já deram uma posição; assim não compete com `discoveryTracker` (que, uma vez
    /// "Disponível" ligado, passa a alimentar `lastFix` sozinho e este fix pontual deixa de ser
    /// consultado pela View).
    private func loadMapFixIfNeeded() {
        guard mapFix == nil, discoveryTracker.lastFix == nil else { return }
        Task { [weak self] in
            guard let self else { return }
            switch locationRepository.authorizationStatus {
            case .denied, .restricted:
                mapFixFailure = .permissionDenied
                return
            case .notDetermined:
                locationRepository.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                break
            }
            guard DeviceLocationServiceStatus.isEnabled else {
                mapFixFailure = .serviceDisabled
                return
            }
            switch await locationRepository.requestOneShotFix() {
            case let .success(fix):
                mapFixFailure = nil
                mapFix = fix
            case .permissionDenied:
                mapFixFailure = .permissionDenied
            case .serviceDisabled:
                mapFixFailure = .serviceDisabled
            case .timeout:
                mapFixFailure = .timeout
            case .failure:
                mapFixFailure = .unknown
            }
        }
    }

    /// Chamado pelo botão "Tentar novamente" da aba Mapa quando `mapFixFailure` está presente.
    func retryMapFix() {
        mapFixFailure = nil
        loadMapFixIfNeeded()
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
