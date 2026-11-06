//
//  PitGoRootView.swift
//  pitgo
//
//  Host de navegação raiz: observa somente `SessionStore.state` (ver contracts/navigation-session.md
//  "Session destination matrix" de `009`). Qualquer transição para fora de um estado autenticado
//  descarta imediatamente a `TabView`/`OnboardingFlow`/telas de provider inteiras, removendo também
//  qualquer estado de ViewModel associado. Antes de sair de `.authenticatedProviderReady`, sinaliza
//  o controller de tracking para parar (ver contracts/navigation-session.md "Tracking cleanup").
//

import Supabase
import SwiftUI

struct PitGoRootView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var providerRegistrationIdentity: AuthIdentity?
    @State private var providerRegistrationPresented = false
    @State private var startingProviderRegistration = false
    @State private var registrationStartError: String?

    private let client: SupabaseClient
    private let accountRepository: AccountRepository
    private let catalogRepository: ServiceCatalogRepository
    private let vehicleRepository: VehicleRepository
    private let providerRegistrationRepository: ProviderRegistrationRepository
    private let addressVerificationRepository: ProviderAddressVerificationRepository
    private let providerDashboardRepository: ProviderDashboardRepository
    private let pitTecPricingRepository: PitTecPricingRepository
    private let migrationRepository: ProviderMigrationRepository
    private let serviceMapRepository: ServiceMapRepository
    private let mobileDispatchRepository: MobileDispatchRepository
    private let pitTecRepository: PitTecRepository
    private let clientAddressRepository: ClientAddressRepository
    private let paymentRepository: PaymentGateway
    private let savedCardRepository: SavedCardRepository
    private let guinchoRepository: GuinchoRepository
    private let guinchoHistoryRepository: GuinchoHistoryRepository
    private let guinchoInspectionRepository: GuinchoInspectionRepository
    private let guinchoRouteRepository: GuinchoRouteRepository
    private let serviceRatingRepository: ServiceRatingRepository
    private let storeRepository: StoreRepository
    @StateObject private var inspectionAlertViewModel: GuinchoInspectionAlertViewModel
    private let guinchoAddressRepository: GuinchoAddressRepository
    private let locationRepository: DeviceLocationRepository
    private let trackingStateRepository: ProviderTrackingStateRepository
    private let onboardingStore = VehicleOnboardingStore()
    @StateObject private var migrationCoordinator = ProviderMigrationCoordinator()
    private let dispatchResumeCoordinator: DispatchResumeCoordinator

    @State private var isOnboardingPending = false
    /// Cópia manual do valor anterior de `isProviderReady` — `onChange(of:)` de um único parâmetro
    /// (compatível com iOS 16) não entrega o valor antigo como a variante de dois parâmetros.
    @State private var wasProviderReady = false

    init(client: SupabaseClient) {
        self.client = client
        accountRepository = AccountRepository(client: client)
        catalogRepository = ServiceCatalogRepository(client: client)
        vehicleRepository = VehicleRepository(client: client)
        providerRegistrationRepository = ProviderRegistrationRepository(client: client)
        providerDashboardRepository = ProviderDashboardRepository(client: client)
        pitTecPricingRepository = PitTecPricingRepository(client: client)
        migrationRepository = ProviderMigrationRepository(client: client)
        serviceMapRepository = ServiceMapRepository(client: client)
        mobileDispatchRepository = MobileDispatchRepository(client: client)
        pitTecRepository = PitTecRepository(client: client)
        clientAddressRepository = ClientAddressRepository(client: client)
        // `027`: Dev nunca cria uma transação real — troca a fronteira inteira por um gateway em
        // memória, sem o resto do app saber a diferença (ver PaymentGateway/SimulatedPaymentGateway).
        paymentRepository = EnvironmentConfig.current.simulated
            ? SimulatedPaymentGateway(client: client)
            : PaymentRepository(client: client)
        savedCardRepository = SavedCardRepository(client: client)
        guinchoRepository = GuinchoRepository(client: client)
        guinchoHistoryRepository = GuinchoHistoryRepository(client: client)
        guinchoInspectionRepository = GuinchoInspectionRepository(client: client)
        guinchoRouteRepository = GuinchoRouteRepository(client: client)
        serviceRatingRepository = ServiceRatingRepository(client: client)
        storeRepository = StoreRepository(client: client)
        let alertRepository = GuinchoInspectionAlertRepository(client: client)
        _inspectionAlertViewModel = StateObject(wrappedValue: GuinchoInspectionAlertViewModel(repository: alertRepository))
        guinchoAddressRepository = GuinchoAddressRepository(client: client)
        dispatchResumeCoordinator = DispatchResumeCoordinator(repository: mobileDispatchRepository)

        let sharedLocationRepository = DeviceLocationRepository()
        locationRepository = sharedLocationRepository
        addressVerificationRepository = ProviderAddressVerificationRepository(client: client)
        trackingStateRepository = ProviderTrackingStateRepository(
            locationRepository: sharedLocationRepository,
            publishRepository: ProviderLocationRepository(client: client)
        )
    }

    var body: some View {
        Group {
            switch sessionStore.state {
            case .initializing, .verifying, .offlineVerification, .blocked:
                SessionGateView(
                    state: sessionStore.state,
                    onRetry: { Task { await sessionStore.retry() } },
                    onSignOut: { Task { await sessionStore.signOut() } }
                )
            case let .passwordRecovery(valid):
                NavigationStack { PasswordRecoveryView(client: client, validRecoverySession: valid) }
            case let .registrationRequired(identity, mode):
                NavigationStack {
                    RegistrationVerificationView(client: client, identity: identity, mode: mode)
                }.id(identity.userID.uuidString + mode.rawValue)
            case .unauthenticated:
                UnauthenticatedFlow(client: client, onboardingStore: onboardingStore)
            case let .authenticatedClient(snapshot):
                if isOnboardingPending {
                    OnboardingFlow(
                        vehicleRepository: vehicleRepository,
                        onResolved: {
                            onboardingStore.resolve(snapshot.userID)
                            isOnboardingPending = false
                        }
                    )
                } else {
                    ClientMainTabView(
                        snapshot: snapshot,
                        accountRepository: accountRepository,
                        catalogRepository: catalogRepository,
                        vehicleRepository: vehicleRepository,
                        serviceMapRepository: serviceMapRepository,
                        mobileDispatchRepository: mobileDispatchRepository,
                        pitTecRepository: pitTecRepository,
                        clientAddressRepository: clientAddressRepository,
                        paymentRepository: paymentRepository,
                        savedCardRepository: savedCardRepository,
                        guinchoRepository: guinchoRepository,
                        guinchoAddressRepository: guinchoAddressRepository,
                        guinchoInspectionRepository: guinchoInspectionRepository,
                        guinchoHistoryRepository: guinchoHistoryRepository,
                        serviceRatingRepository: serviceRatingRepository,
                        storeRepository: storeRepository,
                        inspectionAlertViewModel: inspectionAlertViewModel,
                        dispatchResumeCoordinator: dispatchResumeCoordinator,
                        locationRepository: locationRepository,
                        migrationRepository: migrationRepository,
                        migrationCoordinator: migrationCoordinator,
                        appointmentTrackingRepositoryFactory: { AppointmentTrackingRepository(client: client) },
                        onSignOut: { Task { await sessionStore.signOut() } }
                    )
                }
            case let .authenticatedProviderOnboarding(identity):
                NavigationStack {
                    if migrationCoordinator.activeToken != nil {
                        ProviderMigrationClaimView(
                            repository: migrationRepository,
                            coordinator: migrationCoordinator,
                            onMigrated: { Task { await sessionStore.bootstrap() } }
                        )
                    } else {
                        ProviderRegistrationView(
                            repository: providerRegistrationRepository,
                            verificationRepository: addressVerificationRepository,
                            accountID: identity.userID,
                            authEmail: identity.authEmail,
                            providerKind: ProviderKind(rawValue: UserDefaults.standard.string(forKey: "pitgo.pendingProviderKind.\(identity.userID.uuidString)") ?? "") ?? .guincho,
                            onFinished: {
                                UserDefaults.standard.removeObject(forKey: "pitgo.pendingProviderKind.\(identity.userID.uuidString)")
                                Task { await sessionStore.bootstrap() }
                            },
                            onSessionExpired: { Task { await sessionStore.signOut() } }
                        )
                    }
                }
            case let .authenticatedProviderReady(snapshot):
                // `022` — modalidade PitTec ganha uma home dedicada (mapa + 4 abas); Fixo/Móvel
                // continuam na `ProviderDashboardView` de sempre, sem nenhuma mudança.
                if snapshot.provider.locationMode == .pittec {
                    PitTecHomeView(
                        repository: providerDashboardRepository,
                        snapshot: snapshot,
                        pitTecRepository: pitTecRepository,
                        pricingRepository: pitTecPricingRepository,
                        dispatchRepository: mobileDispatchRepository,
                        locationRepository: locationRepository,
                        onSignOut: { Task { await sessionStore.signOut() } }
                    )
                } else {
                    ProviderDashboardView(
                        repository: providerDashboardRepository,
                        snapshot: snapshot,
                        trackingStateRepository: trackingStateRepository,
                        dispatchRepository: mobileDispatchRepository,
                        pitTecRepository: pitTecRepository,
                        guinchoHistoryRepository: guinchoHistoryRepository,
                        serviceRatingRepository: serviceRatingRepository,
                        guinchoInspectionRepository: guinchoInspectionRepository,
                        guinchoRouteRepository: guinchoRouteRepository,
                        storeRepository: storeRepository,
                        locationRepository: locationRepository,
                        onSignOut: { Task { await sessionStore.signOut() } }
                    )
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if modeSwitchAvailable {
                HStack {
                    Spacer()
                    if startingProviderRegistration { ProgressView() }
                    Menu("Modalidade da conta", systemImage: "person.crop.circle") {
                        ForEach(sessionStore.memberships, id: \.account_type) { membership in
                            Button(membership.account_type == .client ? "Usar como cliente" : "Usar como prestador") {
                                Task { await sessionStore.selectMode(membership.account_type) }
                            }
                        }
                        if !sessionStore.memberships.contains(where: { $0.account_type == .provider }) {
                            Button("Cadastrar como prestador") { openProviderRegistration() }
                        }
                    }.disabled(startingProviderRegistration)
                }.padding(.horizontal).padding(.vertical, 6).background(.bar)
            }
        }
        .sheet(isPresented: $providerRegistrationPresented) {
            if let identity = providerRegistrationIdentity {
                NavigationStack {
                    RegistrationVerificationView(client: client, identity: identity, mode: .provider, onClose: { providerRegistrationPresented = false })
                }
            }
        }
        .alert("Cadastro de prestador", isPresented: Binding(get: { registrationStartError != nil }, set: { if !$0 { registrationStartError = nil } })) {
            Button("OK", role: .cancel) { registrationStartError = nil }
        } message: { Text(registrationStartError ?? "") }
        .pitGoTheme()
        .onChange(of: sessionAuthenticationKey) { key in
            if key == nil {
                providerRegistrationPresented = false
                providerRegistrationIdentity = nil
            }
            if case let .authenticatedClient(snapshot) = sessionStore.state {
                // Uma pendência local (`UserDefaults`) pode sobreviver a uma criação já concluída em
                // outra sessão/dispositivo — o snapshot autoritativo do servidor sempre prevalece
                // (`012` — data-model.md "ignorar pendência legada quando o snapshot já possuir
                // principal").
                isOnboardingPending = snapshot.primaryVehicle == nil && onboardingStore.isPending(snapshot.userID)
            }
        }
        .task { wasProviderReady = isProviderReady }
        .onChange(of: isProviderReady) { isReady in
            if wasProviderReady, !isReady {
                trackingStateRepository.stop()
            }
            wasProviderReady = isReady
        }
    }

    private var modeSwitchAvailable: Bool {
        switch sessionStore.state {
        case .authenticatedClient, .authenticatedProviderReady, .registrationRequired: true
        default: false
        }
    }

    private func openProviderRegistration() {
        guard !startingProviderRegistration else { return }
        startingProviderRegistration = true
        Task {
            defer { startingProviderRegistration = false }
            do {
                providerRegistrationIdentity = try await sessionStore.beginProviderRegistration()
                providerRegistrationPresented = true
            } catch {
                registrationStartError = RegistrationVerificationViewModel.message(error)
            }
        }
    }

    /// Chave estável que só muda quando a identidade CLIENT autenticada muda — evita reavaliar a
    /// pendência de onboarding a cada recomposição não relacionada.
    private var sessionAuthenticationKey: UUID? {
        if case let .authenticatedClient(snapshot) = sessionStore.state { return snapshot.userID }
        return nil
    }

    private var isProviderReady: Bool {
        if case .authenticatedProviderReady = sessionStore.state { return true }
        return false
    }
}

private struct UnauthenticatedFlow: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @State private var path: [UnauthenticatedRoute] = []

    let client: SupabaseClient
    let onboardingStore: VehicleOnboardingStore

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(
                onCreateAccount: {
                    guard path.isEmpty else { return }
                    path.append(.signUp)
                },
                onEnter: {
                    guard path.isEmpty else { return }
                    path.append(.login)
                },
                onRegisterCompany: {
                    guard path.isEmpty else { return }
                    path.append(.providerKindSelection)
                }
            )
            .navigationDestination(for: UnauthenticatedRoute.self) { route in
                switch route {
                case .signUp:
                    BasicRegistrationView(
                        client: client, mode: .client,
                        onAuthenticated: { _ in
                            Task { await sessionStore.bootstrap() }
                        }
                    )
                case .providerKindSelection:
                    ProviderKindSelectionView { kind in
                        path.append(.providerSignUp(kind: kind))
                    }
                case let .providerSignUp(kind):
                    BasicRegistrationView(
                        client: client, mode: .provider,
                        onAuthenticated: { userID in
                            UserDefaults.standard.set(kind.rawValue, forKey: "pitgo.pendingProviderKind.\(userID.uuidString)")
                            Task { await sessionStore.bootstrap() }
                        }
                    )
                case .login:
                    LoginView(sessionStore: sessionStore)
                }
            }
        }
    }
}

/// Fluxo do convite pós-cadastro, com sua própria `NavigationStack` para poder empilhar
/// `VehicleFormView(.onboarding)` (ver contracts/navigation.md "Signup and onboarding flow" de
/// `006`).
private struct OnboardingFlow: View {
    @EnvironmentObject private var sessionStore: SessionStore

    let vehicleRepository: VehicleRepository
    let onResolved: () -> Void

    @State private var isRegisteringVehicle = false

    var body: some View {
        NavigationStack {
            VehicleOnboardingView(
                onRegisterVehicle: { isRegisteringVehicle = true },
                onSkip: onResolved
            )
            .navigationDestination(isPresented: $isRegisteringVehicle) {
                VehicleFormView(
                    repository: vehicleRepository,
                    existingVehicleCount: 0,
                    origin: .onboarding,
                    onSaved: { vehicle in
                        sessionStore.applyAuthoritativePrimaryVehicle(vehicle)
                        onResolved()
                    },
                    // Voltar do formulário SEM salvar retorna ao convite — não resolve a pendência
                    // (a pendência só é resolvida por criação confirmada ou pela ação explícita
                    // "Agora não", nunca por abrir/fechar o formulário — FR-026/`012`).
                    onCancel: { isRegisteringVehicle = false },
                    onSessionExpired: { Task { await sessionStore.signOut() } }
                )
            }
        }
    }
}

/// `TabView` do cliente (Início/Serviços/Garagem/Atendimentos/Perfil).
private struct ClientMainTabView: View {
    let snapshot: AccountSnapshot
    let accountRepository: AccountRepository
    let catalogRepository: ServiceCatalogRepository
    let vehicleRepository: VehicleRepository
    let serviceMapRepository: ServiceMapRepository
    let mobileDispatchRepository: MobileDispatchRepository
    let pitTecRepository: PitTecRepository
    let clientAddressRepository: ClientAddressRepository
    let paymentRepository: PaymentGateway
    let savedCardRepository: SavedCardRepository
    let guinchoRepository: GuinchoRepository
    let guinchoAddressRepository: GuinchoAddressRepository
    let guinchoInspectionRepository: GuinchoInspectionRepository
    let guinchoHistoryRepository: GuinchoHistoryRepository
    let serviceRatingRepository: ServiceRatingRepository
    let storeRepository: StoreRepository
    @ObservedObject var inspectionAlertViewModel: GuinchoInspectionAlertViewModel
    let dispatchResumeCoordinator: DispatchResumeCoordinator
    let locationRepository: DeviceLocationRepository
    let migrationRepository: ProviderMigrationRepository
    let migrationCoordinator: ProviderMigrationCoordinator
    let appointmentTrackingRepositoryFactory: () -> AppointmentTrackingRepository
    let onSignOut: () -> Void

    @State private var selectedTab: BottomItemID = .home
    @State private var homePath: [PitGoRoute] = []
    @State private var openInspectionAppointmentID: UUID?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        PitGoBottomTabs(selection: $selectedTab) { item in
            switch item {
            case .home:
                NavigationStack(path: $homePath) {
                    HomeView(
                        repository: accountRepository,
                        catalogRepository: catalogRepository,
                        userID: snapshot.userID,
                        authEmail: snapshot.authEmail,
                        onDiagnosticTap: {},
                        onServiceTap: handleServiceTap,
                        onOpenGarage: { selectedTab = .garage },
                        onOpenAppointment: { appointmentID in
                            guard homePath.isEmpty else { return }
                            homePath.append(.appointmentTracking(appointmentID: appointmentID))
                        },
                        onOpenAddress: {
                            guard homePath.isEmpty else { return }
                            homePath.append(.clientAddress)
                        }
                    )
                    .navigationDestination(for: PitGoRoute.self) { route in
                        switch route {
                        case let .serviceMap(serviceID):
                            ServiceMapView(
                                serviceID: serviceID,
                                repository: serviceMapRepository,
                                locationRepository: locationRepository,
                                onRequestService: { providerID, serviceID in
                                    guard homePath.count == 1 else { return }
                                    homePath.append(.requestService(serviceID: serviceID, providerID: providerID))
                                }
                            )
                        case let .requestService(serviceID, providerID):
                            RequestServiceView(
                                serviceID: serviceID,
                                providerID: providerID,
                                catalogRepository: catalogRepository,
                                onBack: { homePath.removeLast() }
                            )
                        case .guincho, .guinchoSearchResume:
                            GuinchoMapView(
                                userID: snapshot.userID,
                                repository: guinchoRepository,
                                vehicleRepository: vehicleRepository,
                                locationRepository: locationRepository,
                                addressRepository: guinchoAddressRepository,
                                onBack: { homePath.removeLast() },
                                onGarage: { selectedTab = .garage },
                                onContract: { snapshot in
                                    guard homePath.count == 1 else { return }
                                    homePath.append(.mobileDispatchSearch(searchID: snapshot.searchID))
                                },
                                onSessionExpired: onSignOut
                            )
                        case let .mobileDispatchNewSearch(serviceID):
                            ClientMobileDispatchView(
                                serviceID: serviceID,
                                repository: mobileDispatchRepository,
                                locationRepository: locationRepository,
                                trackingRepository: appointmentTrackingRepositoryFactory(),
                                catalogRepository: catalogRepository,
                                paymentRepository: paymentRepository,
                                savedCardRepository: savedCardRepository,
                                inspectionRepository: guinchoInspectionRepository,
                                ratingRepository: serviceRatingRepository,
                                onBack: { homePath.removeLast() },
                                onOpenTracking: { appointmentID in
                                    guard homePath.count == 1 else { return }
                                    homePath.append(.appointmentTracking(appointmentID: appointmentID))
                                },
                                onSessionExpired: onSignOut,
                                onInspectionVisibility: { openInspectionAppointmentID = $0 }
                            )
                        case .mobileDispatchSearch:
                            // Retomada: `get_my_active_mobile_dispatch()` não recebe `serviceID` —
                            // a View resolve a busca ativa da própria sessão sem precisar dele
                            // (`serviceID: nil` pula a checagem de correspondência e o caminho de
                            // "iniciar nova busca", ver `ClientMobileDispatchViewModel`).
                            ClientMobileDispatchView(
                                serviceID: nil,
                                repository: mobileDispatchRepository,
                                locationRepository: locationRepository,
                                trackingRepository: appointmentTrackingRepositoryFactory(),
                                catalogRepository: catalogRepository,
                                paymentRepository: paymentRepository,
                                savedCardRepository: savedCardRepository,
                                inspectionRepository: guinchoInspectionRepository,
                                ratingRepository: serviceRatingRepository,
                                onBack: { homePath.removeLast() },
                                onOpenTracking: { appointmentID in
                                    guard homePath.count == 1 else { return }
                                    homePath.append(.appointmentTracking(appointmentID: appointmentID))
                                },
                                onSessionExpired: onSignOut,
                                onInspectionVisibility: { openInspectionAppointmentID = $0 }
                            )
                        case let .pitTec(serviceID):
                            PitTecClientView(
                                serviceID: serviceID,
                                repository: pitTecRepository,
                                locationRepository: locationRepository,
                                catalogRepository: catalogRepository,
                                paymentRepository: paymentRepository,
                                savedCardRepository: savedCardRepository,
                                ratingRepository: serviceRatingRepository,
                                onBack: { homePath.removeLast() },
                                onSessionExpired: onSignOut
                            )
                        case let .appointmentTracking(appointmentID):
                            AppointmentTrackingView(
                                appointmentID: appointmentID,
                                repository: appointmentTrackingRepositoryFactory(),
                                ratingRepository: serviceRatingRepository
                            )
                        case let .guinchoInspectionReview(appointmentID):
                            GuinchoInspectionView(appointmentID: appointmentID, repository: guinchoInspectionRepository)
                        case .clientAddress:
                            ClientAddressView(
                                repository: clientAddressRepository,
                                locationRepository: locationRepository,
                                onFinished: { homePath.removeLast() },
                                onSessionExpired: onSignOut
                            )
                        case .providerAppointmentTracking, .providerMigrationStart, .providerRequest,
                             .pitTecProviderRequest, .providerGuinchoHistory, .paymentMethods, .storeCatalog:
                            EmptyView()
                        }
                    }
                }
                .task {
                    guard homePath.isEmpty else { return }
                    if case let .success(resume) = await guinchoRepository.searchResume(), resume.isResumable, homePath.isEmpty {
                        homePath = [.guinchoSearchResume]
                        return
                    }
                    let destination = await dispatchResumeCoordinator.resolveForClient()
                    guard homePath.isEmpty else { return }
                    switch destination {
                    case let .clientSearch(searchID):
                        homePath.append(.mobileDispatchSearch(searchID: searchID))
                        return
                    case let .clientTracking(appointmentID):
                        homePath.append(.appointmentTracking(appointmentID: appointmentID))
                        return
                    case .none, .providerIncoming, .providerTracking:
                        break
                    }
                    // PitTec (`015`) usa um snapshot/RPC próprio — não passa por
                    // `DispatchResumeCoordinator` (que só conhece o guincho móvel, `013`). O
                    // acompanhamento pós-aceite do PitTec vive dentro da própria `PitTecClientView`
                    // (rota/distância), não em `.appointmentTracking` — resume sempre para `.pitTec`.
                    guard homePath.isEmpty else { return }
                    if case let .snapshot(pitTecSnapshot) = await pitTecRepository.getActiveDispatch(), !pitTecSnapshot.status.isTerminal {
                        homePath.append(.pitTec(serviceID: pitTecSnapshot.serviceID))
                    }
                }
            case .services, .appointments:
                PlaceholderTabContent(title: item.title)
            case .garage:
                GarageView(repository: vehicleRepository, userID: snapshot.userID)
            case .profile:
                ProfileView(
                    snapshot: snapshot,
                    migrationRepository: migrationRepository,
                    migrationCoordinator: migrationCoordinator,
                    clientAddressRepository: clientAddressRepository,
                    locationRepository: locationRepository,
                    savedCardRepository: savedCardRepository,
                    guinchoHistoryRepository: guinchoHistoryRepository,
                    serviceRatingRepository: serviceRatingRepository,
                    storeRepository: storeRepository,
                    guinchoInspectionRepository: guinchoInspectionRepository,
                    onOpenGarage: { selectedTab = .garage },
                    onSignOut: onSignOut,
                    onSwitchAccountForMigration: onSignOut
                )
            }
        }
        .task(id: snapshot.userID) {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                guard scenePhase == .active else { continue }
                let expectedPath = homePath
                let eligible: Bool
                if expectedPath.isEmpty { eligible = true }
                else if case .mobileDispatchSearch = expectedPath.last { eligible = true }
                else { eligible = false }
                guard eligible else { continue }
                if case let .success(resume) = await guinchoRepository.searchResume(), resume.isResumable,
                   homePath == expectedPath {
                    selectedTab = .home
                    homePath = [.guinchoSearchResume]
                }
            }
        }
        .task(id: snapshot.userID) {
            inspectionAlertViewModel.start(accountID: snapshot.userID)
            inspectionAlertViewModel.setForeground(scenePhase == .active)
        }
        .onChange(of: scenePhase) { phase in
            inspectionAlertViewModel.setForeground(phase == .active)
        }
        .alert("Vistoria para aprovação", isPresented: Binding(
            get: { shouldShowInspectionAlert },
            set: { if !$0, shouldShowInspectionAlert, let alert = inspectionAlertViewModel.presentedAlert { inspectionAlertViewModel.dismiss(alert) } }
        ), presenting: shouldShowInspectionAlert ? inspectionAlertViewModel.presentedAlert : nil) { alert in
            Button(inspectionAlertViewModel.isOpening ? "Verificando…" : "Revisar vistoria") {
                Task {
                    guard let result = await inspectionAlertViewModel.review(alert) else { return }
                    selectedTab = .home
                    switch result {
                    case let .pending(current): homePath = [.guinchoInspectionReview(appointmentID: current.appointmentID)]
                    case let .resolved(appointmentID): homePath = [.appointmentTracking(appointmentID: appointmentID)]
                    }
                }
            }
            .disabled(inspectionAlertViewModel.isOpening)
            Button("Agora não", role: .cancel) { inspectionAlertViewModel.dismiss(alert) }
        } message: { _ in
            Text(inspectionAlertViewModel.openFailure ?? "Há uma vistoria aguardando seu aceite.")
        }
        .onDisappear { inspectionAlertViewModel.stop() }
    }

    private var shouldShowInspectionAlert: Bool {
        guard let alert = inspectionAlertViewModel.presentedAlert else { return false }
        if openInspectionAppointmentID == alert.appointmentID { return false }
        if case let .guinchoInspectionReview(appointmentID)? = homePath.last, appointmentID == alert.appointmentID { return false }
        return true
    }

    private func handleServiceTap(_ serviceID: UUID, dispatchKind: ServiceDispatchKind) {
        guard homePath.isEmpty else { return }
        switch dispatchKind {
        case .browse:
            homePath.append(.serviceMap(serviceID: serviceID))
        case .mobileSequential:
            // `028`: o card de Guincho da Home passa a abrir a escolha no mapa, não mais a busca
            // automática antiga (`.mobileDispatchNewSearch` continua existindo só para retomada).
            homePath.append(.guincho(serviceID: serviceID))
        case .pittecAutoSequential:
            homePath.append(.pitTec(serviceID: serviceID))
        }
    }
}

#Preview {
    PitGoRootView(client: SupabaseClientProvider.client)
        .environmentObject(SessionStore(client: SupabaseClientProvider.client))
}
