//
//  ProviderDashboardView.swift
//  pitgo
//
//  Home da conta empresarial pronta (`.authenticatedProviderReady`). Nunca renderiza a `TabView` do
//  cliente (ver contracts/navigation-session.md "UI shells" de `009`).
//

import SwiftUI

struct ProviderDashboardView: View {
    @Environment(\.pitGoTokens) private var tokens
    @StateObject private var viewModel: ProviderDashboardViewModel
    @State private var showSignOutConfirmation = false
    @State private var path: [PitGoRoute] = []

    let accountID: UUID
    /// `providers.id` — identidade estável usada pelo tópico privado `provider-dispatch:<providerID>`
    /// (nunca `account_id`, que é o owner Auth substituível).
    let providerID: UUID
    let trackingStateRepository: ProviderTrackingStateRepository
    let dashboardRepository: ProviderDashboardRepository
    let dispatchRepository: MobileDispatchRepository
    let pitTecRepository: PitTecRepository
    let onSignOut: () -> Void

    init(
        repository: ProviderDashboardRepository,
        snapshot: ProviderSnapshot,
        trackingStateRepository: ProviderTrackingStateRepository,
        dispatchRepository: MobileDispatchRepository,
        pitTecRepository: PitTecRepository,
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
                    case .serviceMap, .requestService, .appointmentTracking, .providerMigrationStart,
                         .mobileDispatchNewSearch, .mobileDispatchSearch, .pitTec, .clientAddress,
                         .paymentMethods:
                        EmptyView()
                    }
                }
                .onChange(of: viewModel.sessionExpired) { expired in
                    if expired { onSignOut() }
                }
                .onChange(of: viewModel.incomingAppointmentID) { appointmentID in
                    guard let appointmentID, path.isEmpty else { return }
                    viewModel.acknowledgeIncoming()
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
        .task { viewModel.onAppear() }
        .onDisappear { viewModel.tearDown() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case let .content(snapshot), let .refreshing(snapshot):
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(snapshot)
                    modeSection(snapshot)
                    availabilitySection(snapshot)
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
            Text("Modalidade").font(PitGoTypography.categoryTitle).accessibilityAddTraits(.isHeader)
            Picker(
                "Modalidade",
                selection: Binding(get: { snapshot.provider.locationMode }, set: { viewModel.setMode($0) })
            ) {
                Text("Fixo (endereço)").tag(ProviderLocationMode.fixed)
                Text("Móvel (em atendimento)").tag(ProviderLocationMode.mobile)
            }
            .pickerStyle(.segmented)
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
