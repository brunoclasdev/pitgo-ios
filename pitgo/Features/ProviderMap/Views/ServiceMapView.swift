//
//  ServiceMapView.swift
//  pitgo
//
//  Mapa de descoberta por serviço (MapLibre — ver contracts/navigation-session.md "UI shells" de
//  `009`). Mantém a `TabView` do cliente com Início selecionada. Sempre oferece uma representação
//  equivalente `Mapa | Lista` (FR-031) — landscape largo mostra as duas, compacto mostra uma.
//
//  NOTA (escopo, ver tasks.md): usa marcadores simples (`MLNPointAnnotation`) em vez de clustering
//  nativo via `MLNShapeSource`/Style Spec. Selecionar um cluster exigiria hit-testing manual de
//  features de shape-source (`MLNMapView.visibleFeatures(at:)`), um caminho de maior risco que não
//  há como validar visualmente nesta sessão (sem projeto Supabase real com muitos providers
//  simultâneos); o limite de 200 resultados da RPC permanece utilizável com marcadores simples.
//

import CoreLocation
import SwiftUI

struct ServiceMapView: View {
    @Environment(\.pitGoTokens) private var tokens
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var viewModel: ServiceMapViewModel
    @State private var displayMode: DisplayMode = .map
    @State private var pendingCenter: CLLocationCoordinate2D?
    @State private var selectedResult: ServiceMapResult?

    private let serviceID: UUID
    /// CTA "SOLICITAR ATENDIMENTO" do resumo — recebe somente IDs opacos (contracts/
    /// map-ui-navigation.md "Provider summary and request").
    let onRequestService: (_ providerID: UUID, _ serviceID: UUID) -> Void

    private enum DisplayMode: String, CaseIterable {
        case map = "Mapa"
        case list = "Lista"
    }

    init(
        serviceID: UUID,
        repository: ServiceMapRepository,
        locationRepository: DeviceLocationRepository,
        onRequestService: @escaping (_ providerID: UUID, _ serviceID: UUID) -> Void
    ) {
        self.serviceID = serviceID
        self.onRequestService = onRequestService
        _viewModel = State(initialValue: ServiceMapViewModel(serviceID: serviceID, repository: repository, locationRepository: locationRepository))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Modo de exibição", selection: $displayMode) {
                ForEach(DisplayMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            content
        }
        .background(tokens.background)
        .navigationTitle("Providers próximos")
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.load() }
        .sheet(item: $selectedResult) { result in
            providerSummarySheet(result)
                .presentationDetents([.medium, .large])
        }
    }

    private func providerSummarySheet(_ result: ServiceMapResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(result.displayName)
                .font(PitGoTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            Label(result.locationMode == .mobile ? "Atendimento móvel" : "Endereço fixo", systemImage: result.locationMode == .mobile ? "location.fill" : "mappin.circle.fill")
                .font(PitGoTypography.body)
                .foregroundStyle(tokens.textSecondary)

            if let distance = result.distanceMeters {
                Text("A \(formattedDistance(distance)) de você")
                    .font(PitGoTypography.body)
                    .foregroundStyle(tokens.textSecondary)
            }

            Text(result.serviceSummary)
                .font(PitGoTypography.body)

            if let price = result.minimumPrice {
                Text("A partir de \(formattedPrice(price))")
                    .font(PitGoTypography.body)
            }

            Spacer()

            Button(action: {
                let providerID = result.id
                selectedResult = nil
                onRequestService(providerID, serviceID)
            }) {
                Text("SOLICITAR ATENDIMENTO")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .foregroundStyle(.white)
            .background(tokens.accent)
            .clipShape(Capsule())
            .frame(minHeight: 56)
        }
        .padding(24)
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Buscando providers…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .content(results, viewport, locationMode):
            if horizontalSizeClass == .regular {
                HStack(spacing: 0) {
                    mapView(results: results, viewport: viewport)
                    Divider()
                    listView(results: results)
                }
            } else {
                switch displayMode {
                case .map: mapView(results: results, viewport: viewport)
                case .list: listView(results: results)
                }
            }
            if case .unavailable = locationMode {
                manualLocationBanner
            }
        case .empty:
            emptyState
        case .offline:
            failureState(message: "Sem conexão com a internet. Verifique sua rede e tente novamente.")
        case let .failure(reason):
            failureState(message: message(for: reason))
        }
    }

    private func mapView(results: [ServiceMapResult], viewport: MapViewport) -> some View {
        VStack(spacing: 0) {
            PitGoMapView(
                annotations: results.map {
                    PitGoMapAnnotationItem(
                        id: $0.id.uuidString,
                        coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude),
                        title: $0.displayName,
                        subtitle: $0.serviceSummary,
                        symbolName: $0.locationMode == .mobile ? "car.fill" : nil
                    )
                },
                centerCoordinate: CLLocationCoordinate2D(latitude: viewport.centerLatitude, longitude: viewport.centerLongitude),
                showsUserLocation: true,
                onAnnotationSelected: { identifier in
                    selectedResult = results.first { $0.id.uuidString == identifier }
                },
                onRegionChanged: { pendingCenter = $0 }
            )
            .overlay(alignment: .bottomLeading) { MapAttributionView() }
            searchThisAreaButton
        }
    }

    private var searchThisAreaButton: some View {
        Button(action: {
            if let pendingCenter {
                viewModel.searchThisArea(center: pendingCenter)
            }
        }) {
            Label("Buscar nesta área", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
                .padding()
        }
        .foregroundStyle(.white)
        .background(tokens.accent)
        .frame(minHeight: 44)
        .disabled(pendingCenter == nil)
    }

    private func listView(results: [ServiceMapResult]) -> some View {
        List(results) { result in
            Button(action: { selectedResult = result }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.displayName)
                        .font(PitGoTypography.categoryTitle)
                        .foregroundStyle(tokens.textPrimary)
                    HStack(spacing: 4) {
                        Image(systemName: result.locationMode == .mobile ? "location.fill" : "mappin.circle.fill")
                            .accessibilityHidden(true)
                        Text(result.locationMode == .mobile ? "Móvel" : "Fixo")
                    }
                    .font(PitGoTypography.caption)
                    .foregroundStyle(tokens.textSecondary)
                    Text(result.serviceSummary)
                        .font(PitGoTypography.caption)
                        .foregroundStyle(tokens.textSecondary)
                    HStack {
                        if let price = result.minimumPrice {
                            Text("A partir de \(formattedPrice(price))")
                        }
                        Spacer()
                        if let distance = result.distanceMeters {
                            Text(formattedDistance(distance))
                        }
                    }
                    .font(PitGoTypography.caption)
                    .foregroundStyle(tokens.textSecondary)
                }
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
        }
        .listStyle(.plain)
    }

    private var manualLocationBanner: some View {
        Label("Localização não autorizada — mostrando uma região padrão. Ajuste o mapa e toque em \"Buscar nesta área\".", systemImage: "location.slash")
            .font(PitGoTypography.caption)
            .foregroundStyle(tokens.textSecondary)
            .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "map")
                .font(.system(size: 40))
                .foregroundStyle(tokens.textSecondary)
            Text("Nenhum provider encontrado nesta área.")
                .font(PitGoTypography.body)
                .multilineTextAlignment(.center)
            Button("Tentar novamente") { viewModel.retry() }
                .frame(minHeight: 44)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureState(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Text(message)
                .font(PitGoTypography.body)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.updatesFrequently)
            Button("Tentar novamente") { viewModel.retry() }
                .frame(minHeight: 44)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(for reason: ServiceMapFailureReason) -> String {
        switch reason {
        case .service: "Não foi possível concluir agora. Tente novamente em instantes."
        case .sessionExpired: "Sua sessão expirou. Entre novamente."
        case .unknown: "Não foi possível carregar os providers. Tente novamente."
        }
    }

    private func formattedPrice(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: value as NSDecimalNumber) ?? "R$ \(value)"
    }

    private func formattedDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1f km", meters / 1000) : String(format: "%.0f m", meters)
    }
}
