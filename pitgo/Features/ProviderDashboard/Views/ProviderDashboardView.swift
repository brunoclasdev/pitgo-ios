//
//  ProviderDashboardView.swift
//  pitgo
//
//  Home da conta empresarial pronta (`.authenticatedProviderReady`). Nunca renderiza a `TabView` do
//  cliente (ver contracts/navigation-session.md "UI shells" de `009`).
//

import CoreLocation
import SwiftUI

struct ProviderDashboardView: View {
    @Environment(\.pitGoTokens) private var tokens
    @StateObject private var viewModel: ProviderDashboardViewModel
    @State private var showSignOutConfirmation = false
    @State private var showProviderRatings = false
    @State private var providerRatingSummary: ProviderRatingSummary?
    @State private var isLoadingProviderRating = false
    @State private var providerRatingSummaryFailed = false
    @State private var showStoreCatalog = false
    @State private var path: [PitGoRoute] = []
    @State private var followsHomeLocation = true
    @State private var homeMapCenterTrigger = 0

    let accountID: UUID
    /// `providers.id` — identidade estável usada pelo tópico privado `provider-dispatch:<providerID>`
    /// (nunca `account_id`, que é o owner Auth substituível).
    let providerID: UUID
    let trackingStateRepository: ProviderTrackingStateRepository
    let dashboardRepository: ProviderDashboardRepository
    let dispatchRepository: MobileDispatchRepository
    let pitTecRepository: PitTecRepository
    let guinchoHistoryRepository: GuinchoHistoryRepository
    let serviceRatingRepository: ServiceRatingRepository
    let guinchoInspectionRepository: GuinchoInspectionRepository
    let guinchoRouteRepository: GuinchoRouteRepository
    let storeRepository: StoreRepository
    let onSignOut: () -> Void

    init(
        repository: ProviderDashboardRepository,
        snapshot: ProviderSnapshot,
        trackingStateRepository: ProviderTrackingStateRepository,
        dispatchRepository: MobileDispatchRepository,
        pitTecRepository: PitTecRepository,
        guinchoHistoryRepository: GuinchoHistoryRepository,
        serviceRatingRepository: ServiceRatingRepository,
        guinchoInspectionRepository: GuinchoInspectionRepository,
        guinchoRouteRepository: GuinchoRouteRepository,
        storeRepository: StoreRepository,
        locationRepository: DeviceLocationRepository,
        onSignOut: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ProviderDashboardViewModel(
            repository: repository,
            snapshot: snapshot,
            dispatchRepository: dispatchRepository,
            pitTecRepository: pitTecRepository,
            locationRepository: locationRepository
        ))
        accountID = snapshot.accountID
        providerID = snapshot.provider.id
        dashboardRepository = repository
        self.trackingStateRepository = trackingStateRepository
        self.dispatchRepository = dispatchRepository
        self.pitTecRepository = pitTecRepository
        self.guinchoHistoryRepository = guinchoHistoryRepository
        self.serviceRatingRepository = serviceRatingRepository
        self.guinchoInspectionRepository = guinchoInspectionRepository
        self.guinchoRouteRepository = guinchoRouteRepository
        self.storeRepository = storeRepository
        self.onSignOut = onSignOut
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Área da empresa")
                .navigationDestination(for: PitGoRoute.self) { route in
                    switch route {
                    case let .providerAppointmentTracking(appointmentID):
                        ProviderTrackingView(
                            appointmentID: appointmentID,
                            accountID: accountID,
                            stateRepository: trackingStateRepository,
                            dashboardRepository: dashboardRepository
                        )
                    case let .providerRequest(appointmentID):
                        ProviderIncomingRequestView(
                            providerID: providerID,
                            repository: dispatchRepository,
                            inspectionRepository: guinchoInspectionRepository,
                            routeRepository: guinchoRouteRepository,
                            discoveryTracker: viewModel.discoveryTracker,
                            onBack: { path.removeLast() },
                            onOpenTracking: { trackedAppointmentID in
                                path.removeLast()
                                path.append(.providerAppointmentTracking(appointmentID: trackedAppointmentID))
                            },
                            onSessionExpired: onSignOut
                        )
                        .id(appointmentID)
                    case let .pitTecProviderRequest(appointmentID):
                        PitTecIncomingRequestView(
                            providerID: providerID,
                            repository: pitTecRepository,
                            onBack: { path.removeLast() },
                            onSessionExpired: onSignOut
                        )
                        .id(appointmentID)
                    case .providerGuinchoHistory:
                        GuinchoHistoryView(repository: guinchoHistoryRepository, inspectionRepository: guinchoInspectionRepository,
                                           ratingRepository: serviceRatingRepository,
                                           onBack: { path.removeLast() })
                    case .serviceMap, .requestService, .appointmentTracking, .guinchoInspectionReview, .providerMigrationStart,
                         .mobileDispatchNewSearch, .mobileDispatchSearch, .pitTec, .clientAddress,
                         .paymentMethods, .guincho, .storeCatalog:
                        EmptyView()
                    }
                }
                .onChange(of: viewModel.sessionExpired) { expired in
                    if expired { onSignOut() }
                }
                .onChange(of: viewModel.incomingAppointmentID) { appointmentID in
                    guard let appointmentID else { return }
                    viewModel.acknowledgeIncoming()
                    // Atendimento aceito do card global pode chegar enquanto o prestador está em
                    // outra tela; o tracking vigente passa a ser a tela prioritária.
                    if !path.isEmpty { path.removeAll() }
                    path.append(.providerRequest(appointmentID: appointmentID))
                }
                .onChange(of: viewModel.resumedTrackingAppointmentID) { appointmentID in
                    guard let appointmentID, path.isEmpty else { return }
                    viewModel.acknowledgeResumedTracking()
                    path.append(.providerAppointmentTracking(appointmentID: appointmentID))
                }
                .onChange(of: viewModel.pitTecAppointmentToOpen) { appointmentID in
                    guard let appointmentID, path.isEmpty else { return }
                    viewModel.acknowledgePitTecAppointment()
                    path.append(.pitTecProviderRequest(appointmentID: appointmentID))
                }
        }
        .sheet(isPresented: $showProviderRatings) {
            NavigationStack {
                ProviderRatingsView(providerID: providerID, repository: serviceRatingRepository) {
                    showProviderRatings = false
                }
            }
        }
        .sheet(isPresented: $showStoreCatalog) {
            NavigationStack { StoreCatalogView(repository: storeRepository, ownerStoreID: providerID) }
        }
        .overlay(alignment: .top) {
            if let snapshot = viewModel.guinchoIncomingSnapshot {
                GuinchoIncomingRequestCard(
                    snapshot: snapshot,
                    isResponding: viewModel.isRespondingToGuincho,
                    failure: viewModel.guinchoResponseFailure,
                    onAccept: { viewModel.respondToGuincho(accept: true) },
                    onDecline: { viewModel.respondToGuincho(accept: false) }
                )
                .padding(.top, 8)
                .zIndex(10)
            }
        }
        .task { viewModel.onAppear() }
        .task(id: providerID) { await loadProviderRatingSummary() }
        .onDisappear { viewModel.tearDown() }
    }

    @MainActor
    private func loadProviderRatingSummary() async {
        guard !isLoadingProviderRating else { return }
        isLoadingProviderRating = true
        providerRatingSummaryFailed = false
        do { providerRatingSummary = try await serviceRatingRepository.summary(providerID: providerID) }
        catch { providerRatingSummaryFailed = true }
        isLoadingProviderRating = false
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case let .content(snapshot), let .refreshing(snapshot):
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(snapshot)
                    if snapshot.provider.locationMode == .mobile {
                        guinchoHomeMap
                    }
                    modeSection(snapshot)
                    availabilitySection(snapshot)
                    if snapshot.provider.providerKind == .store {
                        Button { showStoreCatalog = true } label: {
                            Label("Gerenciar produtos da loja", systemImage: "shippingbox")
                                .font(PitGoTypography.categoryTitle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(tokens.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    NavigationLink(value: PitGoRoute.providerGuinchoHistory) {
                        Label("Histórico de atendimentos", systemImage: "clock.arrow.circlepath")
                            .font(PitGoTypography.categoryTitle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(tokens.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    if snapshot.provider.locationMode == .mobile {
                        VStack(alignment: .leading, spacing: 8) {
                            if let providerRatingSummary {
                                ProviderRatingSummaryLabel(summary: providerRatingSummary)
                            } else if isLoadingProviderRating {
                                ProgressView("Carregando avaliações…").font(PitGoTypography.caption)
                            } else if providerRatingSummaryFailed {
                                Button("Não foi possível carregar a média. Tentar novamente") {
                                    Task { await loadProviderRatingSummary() }
                                }
                                .font(PitGoTypography.caption)
                            }
                            Button { showProviderRatings = true } label: {
                                Label("Avaliações e comentários", systemImage: "star.bubble")
                                    .font(PitGoTypography.categoryTitle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(tokens.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                    if snapshot.provider.locationMode == .mobile || snapshot.provider.locationMode == .pittec {
                        discoveryStatusSection
                    }
                    if let failure = viewModel.settingsFailure {
                        Text(message(for: failure))
                            .font(PitGoTypography.caption)
                            .foregroundStyle(.red)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    Spacer(minLength: 24)
                    signOutButton
                }
                .padding(20)
            }
            .background(tokens.background)
        case .failure:
            VStack(spacing: 16) {
                Text("Não foi possível carregar os dados da empresa.")
                    .font(PitGoTypography.body)
                    .multilineTextAlignment(.center)
                Button("Tentar novamente") { viewModel.retry() }
                    .frame(minHeight: 44)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tokens.background)
        }
    }

    private var guinchoHomeMap: some View {
        TimelineView(.periodic(from: .now, by: 5)) { timeline in
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sua localização")
                    .font(PitGoTypography.categoryTitle)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: { viewModel.locateHome() }) {
                    Label("Recentralizar", systemImage: "location.fill")
                        .font(PitGoTypography.caption)
                }
                .frame(minHeight: 44)
                .disabled(viewModel.isLocatingHome)
                .simultaneousGesture(TapGesture().onEnded {
                    followsHomeLocation = true
                    homeMapCenterTrigger += 1
                })
            }
            if let fix = viewModel.currentHomeFix, timeline.date.timeIntervalSince(fix.timestamp) < 35 {
                let coordinate = CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude)
                PitGoMapView(
                    annotations: [PitGoMapAnnotationItem(
                        id: "provider-home-location",
                        coordinate: coordinate,
                        title: "Sua localização",
                        symbolName: "car.fill"
                    )],
                    centerCoordinate: coordinate,
                    zoomLevel: 15,
                    centerTrigger: homeMapCenterTrigger,
                    onUserGesture: { followsHomeLocation = false }
                )
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text("Posição atualizada às \(fix.timestamp.formatted(date: .omitted, time: .shortened))")
                    .font(PitGoTypography.caption)
                    .foregroundStyle(tokens.textSecondary)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(tokens.surface)
                    VStack(spacing: 10) {
                        if viewModel.isLocatingHome { ProgressView("Obtendo localização…") }
                        else if viewModel.currentHomeFix != nil {
                            Text("Sua posição está desatualizada.")
                                .font(PitGoTypography.body)
                                .multilineTextAlignment(.center)
                            Button("Atualizar posição") { viewModel.locateHome() }
                                .frame(minHeight: 44)
                        } else if viewModel.homeLocationUnavailable {
                            Label(homeLocationUnavailableMessage, systemImage: "location.slash")
                                .font(PitGoTypography.body)
                                .multilineTextAlignment(.center)
                            Button("Tentar novamente") { viewModel.locateHome() }
                                .frame(minHeight: 44)
                        } else {
                            ProgressView("Obtendo localização…")
                        }
                    }
                    .padding(20)
                }
                .frame(height: 180)
            }
        }
        .onChange(of: viewModel.currentHomeFix?.timestamp) { _ in
            if followsHomeLocation { homeMapCenterTrigger += 1 }
        }
        }
    }

    private var homeLocationUnavailableMessage: String {
        switch viewModel.locationFailureState {
        case .permissionDenied: "Permita o acesso à localização nos Ajustes do iPhone."
        case .locationServicesDisabled: "Ative os Serviços de Localização nos Ajustes."
        case .unavailable: "Não foi possível obter sua localização. Tente novamente."
        case nil: "Localização indisponível. Verifique a permissão e o GPS."
        }
    }

    private func header(_ snapshot: ProviderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.provider.name)
                .font(PitGoTypography.sectionTitle)
                .foregroundStyle(tokens.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(snapshot.provider.email)
                .font(PitGoTypography.body)
                .foregroundStyle(tokens.textSecondary)
        }
    }

    private func modeSection(_ snapshot: ProviderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tipo de empresa").font(PitGoTypography.categoryTitle).accessibilityAddTraits(.isHeader)
            Text(snapshot.provider.providerKind?.title ?? (snapshot.provider.locationMode == .mobile ? "Guincho" : "Empresa"))
                .font(PitGoTypography.body)
        }
    }

    private func availabilitySection(_ snapshot: ProviderSnapshot) -> some View {
        Toggle(
            "Disponível para novos atendimentos",
            isOn: Binding(get: { snapshot.provider.available }, set: { viewModel.setAvailability($0) })
        )
        .font(PitGoTypography.body)
    }

    /// Indicação persistente e compreensível de que a localização está sendo publicada (`013`,
    /// FR-006) — substitui a entrada manual de `appointmentID` por navegação automática real: uma
    /// solicitação pendente abre `ProviderIncomingRequestView` sozinha (`onChange` em `body`).
    private var discoveryStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Publicação de localização").font(PitGoTypography.categoryTitle).accessibilityAddTraits(.isHeader)
            Label(discoveryStatusText, systemImage: discoveryStatusSymbol)
                .font(PitGoTypography.body)
                .foregroundStyle(discoveryStatusColor)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var discoveryStatusText: String {
        switch viewModel.discoveryTracker.state {
        case .stopped: "Localização não está sendo publicada."
        case .starting: "Iniciando publicação de localização…"
        case let .active(lastPublishedAt):
            "Publicando localização — atualizado às \(lastPublishedAt.formatted(date: .omitted, time: .standard))"
        case let .degraded(reason): discoveryDegradedMessage(reason)
        case .stopping: "Encerrando publicação…"
        }
    }

    private func discoveryDegradedMessage(_ reason: TrackingDegradedReason) -> String {
        switch reason {
        case .permissionDenied: "Permita o acesso à localização nas Configurações para ficar visível."
        case .locationServicesDisabled: "Ative os Serviços de Localização para ficar visível."
        case .publisherConflict: "Localização sendo publicada por outro dispositivo/sessão."
        case .offline: "Sem conexão — sua posição pode ficar desatualizada."
        case .service, .sessionExpired, .notEligible, .appointmentTerminal: "Não foi possível publicar sua localização agora."
        }
    }

    private var discoveryStatusSymbol: String {
        switch viewModel.discoveryTracker.state {
        case .stopped: "location.slash"
        case .starting, .stopping: "location"
        case .active: "location.fill"
        case .degraded: "exclamationmark.triangle.fill"
        }
    }

    private var discoveryStatusColor: Color {
        switch viewModel.discoveryTracker.state {
        case .active: .green
        case .degraded: .orange
        default: tokens.textSecondary
        }
    }

    private var signOutButton: some View {
        Button(action: { showSignOutConfirmation = true }) {
            Text("Sair")
                .font(PitGoTypography.categoryTitle)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .foregroundStyle(.red)
        .overlay(Capsule().stroke(Color.red, lineWidth: 1.5))
        .frame(minHeight: 44)
        .confirmationDialog(
            "Encerrar sessão?",
            isPresented: $showSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sair", role: .destructive, action: onSignOut)
            Button("Cancelar", role: .cancel) {}
        }
    }

    private func message(for reason: ProviderSettingsFailureReason) -> LocalizedStringResource {
        switch reason {
        case .offline: "Sem conexão com a internet. Verifique sua rede e tente novamente."
        case .service: "Não foi possível concluir agora. Tente novamente em instantes."
        case .sessionExpired: "Sua sessão expirou. Entre novamente."
        case .unknown: "Não foi possível concluir a ação. Tente novamente."
        }
    }
}
