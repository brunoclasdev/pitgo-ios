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
    @Environment(SessionStore.self) private var sessionStore

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
    private let paymentRepository: PaymentRepository
    private let savedCardRepository: SavedCardRepository
    private let locationRepository: DeviceLocationRepository
    private let trackingStateRepository: ProviderTrackingStateRepository
    private let onboardingStore = VehicleOnboardingStore()
    private let migrationCoordinator = ProviderMigrationCoordinator()
    private let dispatchResumeCoordinator: DispatchResumeCoordinator

    @State private var isOnboardingPending = false

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
        paymentRepository = PaymentRepository(client: client)
        savedCardRepository = SavedCardRepository(client: client)
        dispatchResumeCoordinator = DispatchResumeCoordinator(repository: mobileDispatchRepository)

        let sharedLocationRepository = DeviceLocationRepository()
        locationRepository = sharedLocationRepository
        addressVerificationRepository = ProviderAddressVerificationRepository(client: client, locationRepository: sharedLocationRepository)
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
                            onFinished: { Task { await sessionStore.bootstrap() } },
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
                        locationRepository: locationRepository,
                        onSignOut: { Task { await sessionStore.signOut() } }
                    )
                }
            }
        }
        .pitGoTheme()
        .onChange(of: sessionAuthenticationKey) { _, _ in
            if case let .authenticatedClient(snapshot) = sessionStore.state {
                // Uma pendência local (`UserDefaults`) pode sobreviver a uma criação já concluída em
                // outra sessão/dispositivo — o snapshot autoritativo do servidor sempre prevalece
                // (`012` — data-model.md "ignorar pendência legada quando o snapshot já possuir
                // principal").
                isOnboardingPending = snapshot.primaryVehicle == nil && onboardingStore.isPending(snapshot.userID)
            }
        }
        .onChange(of: isProviderReady) { wasReady, isReady in
            if wasReady, !isReady {
                trackingStateRepository.stop()
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
    @Environment(SessionStore.self) private var sessionStore
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
                    path.append(.providerSignUp)
                }
            )
            .navigationDestination(for: UnauthenticatedRoute.self) { route in
                switch route {
                case .signUp:
                    SignUpView(
                        repository: SignUpRepository(client: client, onboardingStore: onboardingStore),
                        onAuthenticated: { _ in
                            Task { await sessionStore.bootstrap() }
                        }
                    )
                case .providerSignUp:
                    ProviderSignUpView(
                        repository: ProviderSignUpRepository(client: client),
                        onAuthenticated: { _ in
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
    @Environment(SessionStore.self) private var sessionStore

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
    let paymentRepository: PaymentRepository
    let savedCardRepository: SavedCardRepository
    let dispatchResumeCoordinator: DispatchResumeCoordinator
    let locationRepository: DeviceLocationRepository
    let migrationRepository: ProviderMigrationRepository
    let migrationCoordinator: ProviderMigrationCoordinator
    let appointmentTrackingRepositoryFactory: () -> AppointmentTrackingRepository
    let onSignOut: () -> Void

    @State private var selectedTab: BottomItemID = .home
    @State private var homePath: [PitGoRoute] = []

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
                        case let .mobileDispatchNewSearch(serviceID):
                            ClientMobileDispatchView(
                                serviceID: serviceID,
                                repository: mobileDispatchRepository,
                                locationRepository: locationRepository,
                                catalogRepository: catalogRepository,
                                paymentRepository: paymentRepository,
                                savedCardRepository: savedCardRepository,
                                onBack: { homePath.removeLast() },
                                onOpenTracking: { appointmentID in
                                    guard homePath.count == 1 else { return }
                                    homePath.append(.appointmentTracking(appointmentID: appointmentID))
                                },
                                onSessionExpired: onSignOut
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
                                catalogRepository: catalogRepository,
                                paymentRepository: paymentRepository,
                                savedCardRepository: savedCardRepository,
                                onBack: { homePath.removeLast() },
                                onOpenTracking: { appointmentID in
                                    guard homePath.count == 1 else { return }
                                    homePath.append(.appointmentTracking(appointmentID: appointmentID))
                                },
                                onSessionExpired: onSignOut
                            )
                        case let .pitTec(serviceID):
                            PitTecClientView(
                                serviceID: serviceID,
                                repository: pitTecRepository,
                                locationRepository: locationRepository,
                                catalogRepository: catalogRepository,
                                paymentRepository: paymentRepository,
                                savedCardRepository: savedCardRepository,
                                onBack: { homePath.removeLast() },
                                onSessionExpired: onSignOut
                            )
                        case let .appointmentTracking(appointmentID):
                            AppointmentTrackingView(
                                appointmentID: appointmentID,
                                repository: appointmentTrackingRepositoryFactory()
                            )
                        case .clientAddress:
                            ClientAddressView(
                                repository: clientAddressRepository,
                                locationRepository: locationRepository,
                                onFinished: { homePath.removeLast() },
                                onSessionExpired: onSignOut
                            )
                        case .providerAppointmentTracking, .providerMigrationStart, .providerRequest,
                             .pitTecProviderRequest, .paymentMethods:
                            EmptyView()
                        }
                    }
                }
                .task {
                    guard homePath.isEmpty else { return }
                    switch await dispatchResumeCoordinator.resolveForClient() {
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
                    onOpenGarage: { selectedTab = .garage },
                    onSignOut: onSignOut,
                    onSwitchAccountForMigration: onSignOut
                )
            }
        }
    }

    private func handleServiceTap(_ serviceID: UUID, dispatchKind: ServiceDispatchKind) {
        guard homePath.isEmpty else { return }
        switch dispatchKind {
        case .browse:
            homePath.append(.serviceMap(serviceID: serviceID))
        case .mobileSequential:
            homePath.append(.mobileDispatchNewSearch(serviceID: serviceID))
        case .pittecAutoSequential:
            homePath.append(.pitTec(serviceID: serviceID))
        }
    }
}

#Preview {
    PitGoRootView(client: SupabaseClientProvider.client)
        .environment(SessionStore(client: SupabaseClientProvider.client))
}
