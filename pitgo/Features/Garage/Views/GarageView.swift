//
//  GarageView.swift
//  pitgo
//
//  Aba "Garagem" (ver contracts/navigation.md). `TabView` fixa compartilhada; conteúdo rolável
//  acima dela. Mantém sua própria `NavigationStack` para empilhar `VehicleFormView(.garage)`.
//

import SwiftUI

struct GarageView: View {
    @Environment(\.pitGoTokens) private var tokens
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel: GarageViewModel
    @State private var isAddingVehicle = false

    private let repository: VehicleRepository

    init(repository: VehicleRepository, userID: UUID) {
        self.repository = repository
        _viewModel = StateObject(wrappedValue: GarageViewModel(repository: repository, userID: userID))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Garagem")
                .navigationDestination(isPresented: $isAddingVehicle) {
                    VehicleFormView(
                        repository: repository,
                        existingVehicleCount: existingVehicleCount,
                        origin: .garage,
                        onSaved: { vehicle in
                            sessionStore.applyAuthoritativePrimaryVehicle(vehicle)
                            isAddingVehicle = false
                            Task { await viewModel.load() }
                        },
                        onSessionExpired: { Task { await sessionStore.signOut() } }
                    )
                }
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.confirmedPrimaryVehicle) { vehicle in
            if let vehicle {
                sessionStore.applyAuthoritativePrimaryVehicle(vehicle)
            }
        }
    }

    private var existingVehicleCount: Int {
        if case let .content(vehicles, _) = viewModel.state { return vehicles.count }
        return 0
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            emptyState
        case let .content(vehicles, changingID):
            vehicleList(vehicles, changingID: changingID)
        case .failure:
            failureState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "car.2.fill")
                .font(.system(size: 40))
                .foregroundStyle(tokens.textSecondary)
            Text("Nenhum veículo cadastrado")
                .font(PitGoTypography.categoryTitle)
                .foregroundStyle(tokens.textPrimary)
            addButton
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failureState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Não foi possível carregar seus veículos agora.")
                .font(PitGoTypography.body)
                .foregroundStyle(tokens.textPrimary)
                .multilineTextAlignment(.center)
            Button("Tentar novamente") { Task { await viewModel.load() } }
                .foregroundStyle(tokens.accent)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func vehicleList(_ vehicles: [Vehicle], changingID: UUID?) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(vehicles) { vehicle in
                    VehicleCard(
                        vehicle: vehicle,
                        isChanging: changingID == vehicle.id,
                        onSelectPrimary: { viewModel.selectPrimary(vehicle.id) }
                    )
                    NavigationLink {
                        VehicleCategoryEditor(vehicle: vehicle, repository: repository) {
                            Task { await viewModel.load() }
                        }
                    } label: {
                        Label(vehicle.transportCategoryID == nil ? "Completar categoria para guincho" : "Editar categoria de transporte", systemImage: "car.side")
                    }
                    .disabled(changingID != nil)
                }
                addButton
            }
            .padding(16)
        }
    }

    private var addButton: some View {
        Button(action: { isAddingVehicle = true }) {
            Text("Adicionar veículo")
                .font(PitGoTypography.categoryTitle)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .foregroundStyle(.white)
        .background(tokens.accent)
        .clipShape(Capsule())
        .frame(minHeight: 44)
    }
}

private struct VehicleCard: View {
    @Environment(\.pitGoTokens) private var tokens
    let vehicle: Vehicle
    let isChanging: Bool
    let onSelectPrimary: () -> Void

    var body: some View {
        Button(action: onSelectPrimary) {
            HStack(spacing: 12) {
                Image(systemName: "car.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(tokens.accent)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(vehicle.brand) \(vehicle.model)")
                        .font(PitGoTypography.categoryTitle)
                        .foregroundStyle(tokens.textPrimary)
                    if !vehicle.summaryLine.isEmpty {
                        Text(vehicle.summaryLine)
                            .font(PitGoTypography.caption)
                            .foregroundStyle(tokens.textSecondary)
                    }
                }

                Spacer(minLength: 0)

                if isChanging {
                    ProgressView()
                } else if vehicle.isPrimary {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Principal")
                    }
                    .font(PitGoTypography.caption)
                    .foregroundStyle(tokens.accent)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tokens.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(vehicle.isPrimary ? tokens.accent : tokens.outline, lineWidth: vehicle.isPrimary ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isChanging || vehicle.isPrimary)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(vehicle.isPrimary ? "\(vehicle.brand) \(vehicle.model), principal" : "\(vehicle.brand) \(vehicle.model)"))
    }
}
