//
//  PitTecHomeView.swift
//  pitgo
//
//  Home dedicada da modalidade PitTec (`022`) — `TabView` de 4 abas (Mapa/Dados da
//  corrida/Valores/Perfil) em vez do `ScrollView` único de `ProviderDashboardView` (que continua
//  servindo Fixo/Móvel). Uma única `NavigationStack` envolve a `TabView` inteira (mesmo desenho de
//  `ProviderDashboardView`) para que uma solicitação nova sempre abra por cima, qualquer que seja a
//  aba selecionada (FR-010/SC-004) — não uma pilha de navegação por aba.
//

import SwiftUI

struct PitTecHomeView: View {
    @Environment(\.pitGoTokens) private var tokens
    @State private var viewModel: PitTecHomeViewModel
    @State private var showSignOutConfirmation = false
    @State private var path: [PitGoRoute] = []

    let providerID: UUID
    let pitTecRepository: PitTecRepository
    let onSignOut: () -> Void

    init(
        repository: ProviderDashboardRepository,
        snapshot: ProviderSnapshot,
        pitTecRepository: PitTecRepository,
        pricingRepository: PitTecPricingRepository,
        dispatchRepository: MobileDispatchRepository,
        locationRepository: DeviceLocationRepository,
        onSignOut: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: PitTecHomeViewModel(
            repository: repository,
            snapshot: snapshot,
            pitTecRepository: pitTecRepository,
            pricingRepository: pricingRepository,
            dispatchRepository: dispatchRepository,
            locationRepository: locationRepository
        ))
        providerID = snapshot.provider.id
        self.pitTecRepository = pitTecRepository
        self.onSignOut = onSignOut
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationDestination(for: PitGoRoute.self) { route in
                    switch route {
                    case let .pitTecProviderRequest(appointmentID):
                        PitTecIncomingRequestView(
                            providerID: providerID,
                            repository: pitTecRepository,
                            onBack: { path.removeLast() },
                            onSessionExpired: onSignOut
                        )
                        .id(appointmentID)
                    case .serviceMap, .requestService, .providerMigrationStart, .appointmentTracking,
                         .providerAppointmentTracking, .mobileDispatchNewSearch, .mobileDispatchSearch,
                         .providerRequest, .pitTec, .clientAddress, .paymentMethods:
                        EmptyView()
                    }
                }
                .onChange(of: viewModel.sessionExpired) { _, expired in
                    if expired { onSignOut() }
                }
                .onChange(of: viewModel.pitTecAppointmentToOpen) { _, appointmentID in
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
        case let .content(snapshot):
            PitGoBottomTabs(selection: Binding(get: { viewModel.selectedTab }, set: { viewModel.selectTab($0) })) { tab in
                switch tab {
                case .map:
                    PitTecHomeMapTab(viewModel: viewModel, snapshot: snapshot)
                case .ride:
                    PitTecHomeRideTab(activeAppointment: viewModel.activeAppointment)
                case .values:
                    PitTecHomeValuesTab(pricingState: viewModel.pricingState)
                case .profile:
                    PitTecHomeProfileTab(snapshot: snapshot, showSignOutConfirmation: $showSignOutConfirmation, onSignOut: onSignOut)
                }
            }
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
}
