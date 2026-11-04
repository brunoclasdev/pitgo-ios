//
//  GuinchoMapView.swift
//  pitgo
//
//  `028` (porte do app Android — `GuinchoMapScreen.kt`): retirada (automática pela localização,
//  manual no mapa se indisponível) → destino (busca de endereço + marcação no mapa) → confirmação
//  (veículo) → descoberta (mini card por guincheiro, Contratar). Ao contratar, `onContract` recebe o
//  snapshot de despacho compartilhado (`013`) e a tela que apresenta esta View assume o
//  acompanhamento — esta View nunca observa o pós-aceite.
//

import CoreLocation
import SwiftUI

/// Mede a altura real do conteúdo do card inferior — sem isso, o `ScrollView` reivindica sempre o
/// teto de `.frame(maxHeight:)` para hit-testing, mesmo quando o conteúdo visível é bem menor,
/// engolindo toques nos pinos do mapa e arrastos que deveriam ir para o mapa por baixo (achado real
/// desta sessão: pinos próximos ao topo do mapa ficavam impossíveis de tocar).
private struct GuinchoCardHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat?
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

struct GuinchoMapView: View {
    @Environment(\.pitGoTokens) private var tokens
    @StateObject private var viewModel: GuinchoMapViewModel
    @FocusState private var addressFieldFocused: Bool
    @State private var bottomCardHeight: CGFloat?

    let onBack: () -> Void
    let onGarage: () -> Void
    let onContract: (MobileDispatchSnapshot) -> Void
    let onSessionExpired: () -> Void

    init(
        userID: UUID,
        repository: GuinchoRepository,
        vehicleRepository: VehicleRepository,
        locationRepository: DeviceLocationRepository,
        addressRepository: GuinchoAddressRepository,
        onBack: @escaping () -> Void,
        onGarage: @escaping () -> Void,
        onContract: @escaping (MobileDispatchSnapshot) -> Void,
        onSessionExpired: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: GuinchoMapViewModel(
            userID: userID,
            repository: repository,
            vehicleRepository: vehicleRepository,
            locationRepository: locationRepository,
            addressRepository: addressRepository
        ))
        self.onBack = onBack
        self.onGarage = onGarage
        self.onContract = onContract
        self.onSessionExpired = onSessionExpired
    }

    var body: some View {
        ZStack {
            mapSection.ignoresSafeArea(edges: .bottom)
            // Keep every flow card fixed to the top edge. The map remains underneath and can
            // receive gestures outside the bounded, visible ScrollView.
            VStack(spacing: 0) {
                bottomCard
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(tokens.background)
        .navigationTitle("Guincho")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    Task { if await viewModel.closeSearch() { onBack() } }
                }) {
                    Image(systemName: "chevron.left")
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Voltar")
            }
        }
        .task {
            await viewModel.start()
            if viewModel.state.stage == .pickup, viewModel.state.pickup == nil, viewModel.state.failure == nil {
                viewModel.locate()
            }
        }
        .onDisappear { viewModel.stopDiscoveryUpdates() }
        .onChange(of: viewModel.state.stage) { stage in
            if stage == .discovery { viewModel.startDiscoveryUpdates() } else { viewModel.stopDiscoveryUpdates() }
        }
        .onChange(of: checkoutSearchID) { _ in
            if let snapshot = viewModel.state.checkout { onContract(snapshot) }
        }
        .onChange(of: viewModel.state.failure) { failure in
            if failure == .sessionExpired { onSessionExpired() }
        }
    }

    private var checkoutSearchID: UUID? { viewModel.state.checkout?.searchID }

    // MARK: - Mapa

    @ViewBuilder
    private var mapSection: some View {
        let state = viewModel.state
        PitGoMapView(
            annotations: mapAnnotations(state),
            // `.pickup`/`.destination`: centraliza uma vez (GPS/estado) e deixa o pan livre depois —
            // `onRegionChanged` realimenta `state.viewport` com o que o mapa já mostra, então o
            // próximo valor passado aqui coincide com `lastCenteredCoordinate` e não força um novo
            // snap (mesma técnica anti-"briga com o pan" de `026`). `.confirm`/`.discovery` usam
            // `fitCoordinates`/`fitTrigger` em vez de `centerCoordinate`.
            centerCoordinate: (state.stage == .pickup || state.stage == .destination) ? state.viewport : nil,
            zoomLevel: 15,
            fitCoordinates: state.fitCoordinates,
            fitTrigger: state.fitTrigger,
            onAnnotationSelected: { id in
                guard let providerID = UUID(uuidString: id) else { return }
                viewModel.selectProvider(id: providerID)
            },
            onRegionChanged: { coordinate in
                guard state.stage == .pickup || state.stage == .destination else { return }
                viewModel.userRepositionedMap(to: coordinate)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) { MapAttributionView() }
        .overlay(alignment: .topTrailing) {
            if state.stage == .pickup || state.stage == .destination {
                Button("Minha localização") { viewModel.locate() }
                    .padding(10)
                    .background(tokens.surface, in: Capsule())
                    .padding(12)
            }
        }
        .overlay {
            // Crosshair fixo no centro — a retirada é sempre `viewport.center`, sem marcador.
            if state.stage == .pickup {
                Image(systemName: "mappin")
                    .font(.system(size: 32))
                    .foregroundStyle(tokens.accent)
                    .offset(y: -16)
                    .allowsHitTesting(false)
            }
        }
    }

    private func mapAnnotations(_ state: GuinchoMapState) -> [PitGoMapAnnotationItem] {
        var items: [PitGoMapAnnotationItem] = []
        if state.stage != .pickup, let pickup = state.pickup {
            items.append(PitGoMapAnnotationItem(id: "pickup", coordinate: pickup, title: state.pickupAddress))
        }
        if state.stage == .confirm || state.stage == .discovery, let destination = state.destination {
            items.append(PitGoMapAnnotationItem(id: "destination", coordinate: destination, title: state.fullDestinationAddress))
        }
        if state.stage == .discovery {
            items += state.providers.map { provider in
                PitGoMapAnnotationItem(
                    id: provider.id.uuidString,
                    coordinate: provider.coordinate,
                    title: provider.name,
                    symbolName: "car.fill"
                )
            }
        }
        return items
    }

    // MARK: - Card inferior

    @ViewBuilder
    private var bottomCard: some View {
        let state = viewModel.state
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if state.operation != .idle {
                    ProgressView().frame(maxWidth: .infinity)
                }
                if state.resumedAfterDecline {
                    Text("O guincheiro recusou. Escolha outro prestador. O acompanhamento financeiro permanece no histórico.")
                        .font(PitGoTypography.body)
                }
                if state.failure == .vehicleCategoryRequired {
                    Button("Completar categoria na Garagem", action: onGarage)
                }
                if let failure = state.failure {
                    Button("Tentar novamente") {
                        Task {
                            await viewModel.start()
                            if viewModel.state.stage == .pickup, viewModel.state.failure == nil { viewModel.locate() }
                        }
                    }.disabled(state.operation != .idle)
                    Text(failureMessage(failure))
                        .font(PitGoTypography.caption)
                        .foregroundStyle(.red)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                if state.locationUnavailable {
                    Text("Não foi possível obter sua localização automaticamente.")
                        .font(PitGoTypography.caption)
                        .foregroundStyle(tokens.textSecondary)
                }
                switch state.stage {
                case .pickup: pickupStage(state)
                case .destination: destinationStage(state)
                case .confirm: confirmStage(state)
                case .discovery: discoveryStage(state)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tokens.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(tokens.accent, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
            .padding(12)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: GuinchoCardHeightPreferenceKey.self, value: proxy.size.height)
                }
            )
        }
        .onPreferenceChange(GuinchoCardHeightPreferenceKey.self) { bottomCardHeight = $0 }
        // Altura real do conteúdo (capada em 48% da tela) em vez de sempre reivindicar o teto — um
        // `ScrollView` com só `.frame(maxHeight:)` ocupa o espaço máximo oferecido para hit-testing
        // mesmo com conteúdo bem menor (ex.: estágio de retirada), bloqueando toques/arrastos no mapa
        // por baixo (achado real desta sessão).
        .frame(height: min(bottomCardHeight ?? UIScreen.main.bounds.height * 0.48, UIScreen.main.bounds.height * 0.48))
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func pickupStage(_ state: GuinchoMapState) -> some View {
        Text("A retirada é definida pela sua localização atual.")
            .font(PitGoTypography.body)
        if state.locationUnavailable {
            Text("Posicione o mapa sobre o ponto de retirada e confirme.")
                .font(PitGoTypography.caption)
                .foregroundStyle(tokens.textSecondary)
            Button("Confirmar este ponto") { viewModel.confirmPoint() }
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(state.operation != .idle)
        }
    }

    @ViewBuilder
    private func destinationStage(_ state: GuinchoMapState) -> some View {
        Text("Retirada: \(state.pickupAddress)")
            .font(PitGoTypography.caption)
            .foregroundStyle(tokens.textSecondary)
        Text("Para onde o veículo deve ir?")
            .font(PitGoTypography.body)
        TextField("Endereço de destino", text: Binding(
            get: { state.destinationAddress },
            set: { viewModel.updateDestinationAddress($0) }
        ))
        .focused($addressFieldFocused)
        .textFieldStyle(.roundedBorder)
        .submitLabel(.search)

        if state.searchingAddress {
            ProgressView("Buscando endereço…").frame(maxWidth: .infinity)
        }
        ForEach(state.addressSuggestions) { suggestion in
            Button(suggestion.label) {
                addressFieldFocused = false
                viewModel.chooseDestination(suggestion)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
        }
        if state.addressSearchFailure {
            Text("Não foi possível buscar o endereço agora.")
                .font(PitGoTypography.caption)
                .foregroundStyle(.red)
        } else if state.addressSearchCompleted, state.addressSuggestions.isEmpty {
            Text("Nenhum endereço encontrado.")
                .font(PitGoTypography.caption)
                .foregroundStyle(tokens.textSecondary)
        }

        TextField("Número", text: Binding(
            get: { state.destinationNumber },
            set: { viewModel.updateDestinationNumber($0) }
        ))
        .textFieldStyle(.roundedBorder)
        .keyboardType(.numbersAndPunctuation)

        if state.destinationNumberNotFound {
            Text("Número não encontrado nesse endereço.")
                .font(PitGoTypography.caption)
                .foregroundStyle(.red)
        }

        Button("Confirmar destino") {
            addressFieldFocused = false
            viewModel.confirmPoint()
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .disabled(state.operation != .idle || !state.canConfirmDestination)
    }

    @ViewBuilder
    private func confirmStage(_ state: GuinchoMapState) -> some View {
        Text("\(state.pickupAddress) → \(state.fullDestinationAddress)")
            .font(PitGoTypography.body)
        Text("Veículo")
            .font(PitGoTypography.caption)
            .foregroundStyle(tokens.textSecondary)
        if state.vehicles.isEmpty {
            Button("Adicionar veículo", action: onGarage)
                .frame(minHeight: 44)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(state.vehicles) { vehicle in
                        Button("\(vehicle.brand) \(vehicle.model)") { viewModel.selectVehicle(vehicle.id) }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(state.vehicleID == vehicle.id ? tokens.accent.opacity(0.2) : tokens.background, in: Capsule())
                            .overlay(Capsule().stroke(tokens.accent, lineWidth: 1))
                    }
                }
            }
        }
        Button("Buscar guincheiros") { viewModel.confirmTrip() }
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(state.operation != .idle || state.vehicleID == nil)
        Button("Editar", action: viewModel.editTrip)
            .frame(minHeight: 44)
    }

    @ViewBuilder
    private func discoveryStage(_ state: GuinchoMapState) -> some View {
        if let provider = state.selected {
            if let sizeName = provider.sizeName { Text(sizeName).font(PitGoTypography.caption) }
            Text(provider.name)
                .font(PitGoTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            ProviderRatingSummaryLabel(summary: provider.ratingSummary)
            if let quote = state.quote {
                Text(formattedAmount(quote.total))
                    .font(PitGoTypography.sectionTitle)
                if let duration = quote.durationMinutes {
                    Text("Cerca de \(duration) min")
                        .font(PitGoTypography.caption)
                        .foregroundStyle(tokens.textSecondary)
                }
            } else if state.operation == .quoting {
                ProgressView("Calculando valor…")
            }
            Button("Contratar") { viewModel.contract() }
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(.white)
                .background(tokens.accent)
                .clipShape(Capsule())
                .disabled(state.quote == nil || state.operation != .idle || state.checkout != nil)
        } else {
            Text(state.providers.isEmpty && state.operation == .idle
                ? "Nenhum guincheiro disponível no momento."
                : "Toque num ícone no mapa para ver o valor.")
                .font(PitGoTypography.body)
                .foregroundStyle(tokens.textSecondary)
        }
        HStack(spacing: 16) {
            Button("Atualizar", action: viewModel.refresh)
                .disabled(state.operation != .idle)
            Button("Editar trajeto", action: viewModel.editTrip)
        }
        .frame(minHeight: 44)
    }

    // MARK: - Helpers

    private func failureMessage(_ reason: GuinchoFailureReason) -> String {
        switch reason {
        case .vehicleCategoryRequired: "Complete a categoria do veículo na Garagem para solicitar guincho."
        case .guinchoSizeRequired: "O guincho precisa ter um porte cadastrado."
        case .incompatibleVehicle: "Este guincho não é compatível. Atualize a busca e escolha outro prestador."
        case .providerExcluded: "Este guincheiro recusou o atendimento. Escolha outro prestador."
        case .catalogConflict: "O cadastro mudou. Atualize a busca."
        case .invalidInput: "Revise os dados informados."
        case .sessionExpired: "Sua sessão expirou."
        case .offline: "Sem conexão com a internet."
        case .timeout: "Não foi possível concluir agora. Tente novamente."
        case .routeUnavailable: "Não foi possível calcular a rota até o destino."
        case .providerUnavailable: "Este guincheiro não está mais disponível."
        case .quoteExpired: "O valor mudou. Escolha novamente."
        case .quoteConflict: "O valor mudou. Escolha novamente."
        case .pricingUnavailable: "A tarifa de guincho não está configurada para este ambiente."
        case .serviceUnavailable: "Não foi possível concluir agora. Tente novamente em instantes."
        case .contract: "Não foi possível concluir esta ação."
        case .unknown: "Não foi possível concluir agora."
        }
    }

    private func formattedAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: amount as NSDecimalNumber) ?? "R$ \(amount)"
    }
}
