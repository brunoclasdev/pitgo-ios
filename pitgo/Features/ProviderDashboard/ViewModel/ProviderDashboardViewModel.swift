//
//  ProviderDashboardViewModel.swift
//  pitgo
//

import Combine
import Foundation

@MainActor
final class ProviderDashboardViewModel: ObservableObject {
    @Published private(set) var state: ProviderDashboardUiState
    @Published private(set) var settingsFailure: ProviderSettingsFailureReason?
    @Published private(set) var sessionExpired = false
    /// Solicitação pendente detectada para este provider — a View navega automaticamente ao
    /// `ProviderIncomingRequestView` quando este campo deixa de ser `nil` (`013`).
    @Published private(set) var incomingAppointmentID: UUID?
    /// Atendimento já reservado (`ACCEPTED`/`IN_PROGRESS`) detectado ao (re)abrir o dashboard — cobre
    /// a retomada do lado provider (contracts/mobile-dispatch-ui-navigation.md "Retomada",
    /// `.providerTracking`), já que o app pode ter sido encerrado enquanto o atendimento seguia.
    @Published private(set) var resumedTrackingAppointmentID: UUID?
    /// Chamada PitTec (pendente OU já reservada) detectada para este provider — `015`. Uma única
    /// rota (`PitTecIncomingRequestView`) trata os dois casos internamente, então basta um sinal.
    @Published private(set) var pitTecAppointmentToOpen: UUID?
    /// `029`: pedido Guincho pago apresentado sobre a tela atual, sem trocar a rota.
    @Published private(set) var guinchoIncomingSnapshot: MobileDispatchSnapshot?
    @Published private(set) var isRespondingToGuincho = false
    @Published private(set) var guinchoResponseFailure: String?
    @Published private(set) var homeLocationFix: DeviceLocationFix?
    @Published private(set) var isLocatingHome = false
    @Published private(set) var homeLocationUnavailable = false
    @Published private(set) var locationFailureState: HomeLocationFailureState?

    let discoveryTracker: ProviderDiscoveryTracker

    private let repository: ProviderDashboardRepository
    private let dispatchRepository: MobileDispatchRepository
    private let pitTecRepository: PitTecRepository
    private let locationRepository: DeviceLocationRepository
    private let guinchoAlertNotifier = GuinchoIncomingAlertNotifier()
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
    /// Mesmo achado/fix de `PitTecHomeViewModel` (reproduzido em device físico real): uma
    /// solicitação nova só aparecia depois de fechar e reabrir o app — o Broadcast de
    /// `provider-dispatch:<providerID>` não chegava e não havia nenhum fallback aqui. Poll de
    /// segurança, nunca a única fonte de verdade.
    private var pollTask: Task<Void, Never>?
    private let pollInterval: TimeInterval = 5
    /// Repassa as mudanças de `discoveryTracker` — a View lê `discoveryTracker.state` diretamente, e
    /// sem isto `objectWillChange` nunca dispararia só por causa dele.
    private var cancellables = Set<AnyCancellable>()

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
        self.locationRepository = locationRepository
        accountID = snapshot.accountID
        state = .content(snapshot)
        discoveryTracker = ProviderDiscoveryTracker(locationRepository: locationRepository, dispatchRepository: dispatchRepository)
        discoveryTracker.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        discoveryTracker.$lastFix
            .dropFirst()
            .sink { [weak self] fix in
                guard fix != nil else { return }
                Task { @MainActor in await self?.checkIncoming() }
            }
            .store(in: &cancellables)
    }

    /// Chamado uma vez em `.task` — sincroniza o tracker com a disponibilidade atual e passa a
    /// observar solicitações pendentes destinadas a este provider.
    func onAppear() {
        syncTracker()
        if currentSnapshot?.provider.locationMode == .mobile {
            locateHomeIfNeeded()
        }
        guard !isObservingIncoming else { return }
        isObservingIncoming = true
        Task { [weak self] in
            guard let self else { return }
            await checkIncoming()
            await checkPitTecIncoming()
            subscribeToIncomingInBackground()
            startPolling()
        }
    }

    func locateHomeIfNeeded() {
        guard !isLocatingHome, homeLocationFix == nil, discoveryTracker.lastFix == nil else { return }
        locateHome()
    }

    func locateHome() {
        guard !isLocatingHome else { return }
        switch locationRepository.authorizationStatus {
        case .denied, .restricted:
            locationFailureState = .permissionDenied
            homeLocationUnavailable = true
            return
        case .notDetermined:
            locationRepository.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            break
        }
        guard DeviceLocationServiceStatus.isEnabled else {
            locationFailureState = .locationServicesDisabled
            homeLocationUnavailable = true
            return
        }
        isLocatingHome = true
        Task { [weak self] in
            guard let self else { return }
            switch await locationRepository.requestOneShotFix(timeout: 10) {
            case let .success(fix):
                homeLocationFix = fix
                homeLocationUnavailable = false
                locationFailureState = nil
            case .permissionDenied:
                locationFailureState = .permissionDenied
                homeLocationUnavailable = true
            case .serviceDisabled:
                locationFailureState = .locationServicesDisabled
                homeLocationUnavailable = true
            case .timeout, .failure:
                locationFailureState = .unavailable
                homeLocationUnavailable = true
            }
            isLocatingHome = false
        }
    }

    var currentHomeFix: DeviceLocationFix? {
        [discoveryTracker.lastFix, homeLocationFix]
            .compactMap { $0 }
            .max { $0.timestamp < $1.timestamp }
    }

    /// Roda à parte do resto de `onAppear` — mesmo achado de `PitTecClientViewModel.
    /// subscribeToSearchInBackground`: se essa chamada bloqueasse `onAppear`, o poll de segurança
    /// (que existe justamente para cobrir a demora/perda dela) ficaria inútil enquanto ela não
    /// resolve.
    private func subscribeToIncomingInBackground() {
        let providerID = accountIDForTopic
        Task { [weak self] in
            guard let self else { return }
            await dispatchRepository.subscribeToProvider(providerID: providerID) { [weak self] in
                Task { @MainActor in await self?.checkIncoming() }
            }
        }
        Task { [weak self] in
            guard let self else { return }
            await pitTecRepository.subscribeToProvider(providerID: providerID) { [weak self] in
                Task { @MainActor in await self?.checkPitTecIncoming() }
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
                await self.checkIncoming()
                await self.checkPitTecIncoming()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Chamado quando a `View` raiz do dashboard sai de cena (troca/fim de sessão) — nunca ao
    /// apenas empurrar `ProviderIncomingRequestView` na mesma `NavigationStack`.
    func tearDown() {
        stopPolling()
        discoveryTracker.stop()
        Task { await guinchoAlertNotifier.removeVisibleNotifications(providerID: accountIDForTopic) }
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
            // `028`: Guincho fica inteiramente em `ProviderIncomingRequestView` (ver
            // `guinchoReservedState`) — nunca em `ProviderTrackingView` (publicação de localização
            // do guincho móvel clássico, fora do escopo deste porte).
            if snapshot.dispatchKind == .guinchoDirect {
                switch appointment.status {
                case .pending where appointment.appointmentID != dismissedIncomingID:
                    // `get_my_active_mobile_dispatch` só retorna a oferta operacional após o
                    // pagamento. Mantemos a tela atual e mostramos um único card global.
                    guinchoIncomingSnapshot = snapshot
                    incomingAppointmentID = nil
                    await guinchoAlertNotifier.notifyIfNeeded(
                        providerID: accountIDForTopic,
                        appointmentID: appointment.appointmentID,
                        deadline: appointment.responseDeadline
                    )
                case .accepted where appointment.appointmentID != dismissedIncomingID,
                     .inProgress where appointment.appointmentID != dismissedIncomingID,
                     .awaitingClientCompletionConfirmation where appointment.appointmentID != dismissedIncomingID,
                     .disputed where appointment.appointmentID != dismissedIncomingID:
                    guinchoIncomingSnapshot = nil
                    await guinchoAlertNotifier.clear(providerID: accountIDForTopic, appointmentID: appointment.appointmentID)
                    incomingAppointmentID = appointment.appointmentID
                default:
                    guinchoIncomingSnapshot = nil
                    await guinchoAlertNotifier.clear(providerID: accountIDForTopic, appointmentID: appointment.appointmentID)
                    break
                }
                return
            }
            guinchoIncomingSnapshot = nil
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
        case .noActiveFlow:
            guinchoIncomingSnapshot = nil
            break
        case .failure:
            // Uma falha transitória de rede não invalida a última oferta autorizada; a resposta
            // ainda será revalidada pelo servidor ao tocar em uma ação.
            break
        }
    }

    func respondToGuincho(accept: Bool) {
        guard !isRespondingToGuincho,
              let snapshot = guinchoIncomingSnapshot,
              let appointment = snapshot.appointment,
              snapshot.dispatchKind == .guinchoDirect,
              appointment.status == .pending,
              snapshot.allowedActions.contains(accept ? .accept : .decline) else { return }
        isRespondingToGuincho = true
        guinchoResponseFailure = nil
        Task { [weak self] in
            guard let self else { return }
            switch await dispatchRepository.respond(
                appointmentID: appointment.appointmentID,
                accept: accept,
                expectedRevision: appointment.revision
            ) {
            case .snapshot, .noActiveFlow:
                guinchoIncomingSnapshot = nil
                await guinchoAlertNotifier.clear(providerID: accountIDForTopic, appointmentID: appointment.appointmentID)
                if !accept { dismissedIncomingID = appointment.appointmentID }
                await checkIncoming()
            case .failure:
                guinchoResponseFailure = "Não foi possível responder. Confira sua conexão e tente novamente."
                await checkIncoming()
            }
            isRespondingToGuincho = false
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
        let available = snapshot.provider.available
        settingsTask = Task { [weak self] in
            guard let self else { return }
            let result = await repository.updateSettings(available: available, locationMode: mode)
            if Task.isCancelled { return }
            apply(result)
        }
    }

    func setAvailability(_ available: Bool) {
        guard let snapshot = currentSnapshot, snapshot.provider.available != available else { return }
        settingsFailure = nil
        settingsTask?.cancel()
        let locationMode = snapshot.provider.locationMode
        settingsTask = Task { [weak self] in
            guard let self else { return }
            if available, locationMode == .mobile {
                await guinchoAlertNotifier.requestPermission()
            }
            let result = await repository.updateSettings(available: available, locationMode: locationMode)
            if Task.isCancelled { return }
            apply(result)
        }
    }

    private func apply(_ result: ProviderSettingsResult) {
        switch result {
        case let .success(update):
            guard let snapshot = currentSnapshot else { return }
            state = .content(makeSnapshot(replacing: snapshot.provider.applying(update)))
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

enum HomeLocationFailureState {
    case permissionDenied
    case locationServicesDisabled
    case unavailable
}
