//
//  ProfileView.swift
//  pitgo
//
//  Aba "Perfil" (ver contracts/navigation.md). Nome/e-mail atuais do snapshot; sem CPF/CNPJ nesta
//  entrega. `Sair` exige confirmação. "Migrar empresa" só aparece para contas com empresa legada
//  pendente (`AccountSnapshot.legacyProviderMigrationAvailable`, ver contracts/
//  account-provider-database.md e contracts/navigation-session.md "Assisted migration stack" de
//  `009`) — não existe mais um atalho de "Área da empresa" na conta cliente (`007`): providers agora
//  são uma conta independente.
//

import SwiftUI

struct ProfileView: View {
    @Environment(\.pitGoTokens) private var tokens
    @AppearancePreference private var appearance
    let snapshot: AccountSnapshot
    let migrationRepository: ProviderMigrationRepository
    let migrationCoordinator: ProviderMigrationCoordinator
    let clientAddressRepository: ClientAddressRepository
    let locationRepository: DeviceLocationRepository
    let savedCardRepository: SavedCardRepository
    let guinchoHistoryRepository: GuinchoHistoryRepository
    let serviceRatingRepository: ServiceRatingRepository
    let storeRepository: StoreRepository
    let guinchoInspectionRepository: GuinchoInspectionRepository
    let onOpenGarage: () -> Void
    let onSignOut: () -> Void
    /// Logout intencional a partir da tela de migração — distinto de `onSignOut` só pelo ponto de
    /// entrada; ambos chamam `SessionStore.signOut()`.
    let onSwitchAccountForMigration: () -> Void

    @State private var showSignOutConfirmation = false
    @State private var path: [PitGoRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 20) {
                avatar
                VStack(spacing: 4) {
                    Text(snapshot.profile.displayName)
                        .font(PitGoTypography.sectionTitle)
                        .foregroundStyle(tokens.textPrimary)
                    Text(snapshot.profile.email)
                        .font(PitGoTypography.body)
                        .foregroundStyle(tokens.textSecondary)
                    // `027` FR-003/SC-007: identificação do ambiente ativo, nunca URL/chave/token.
                    Text(EnvironmentDiagnostics.label)
                        .font(PitGoTypography.caption)
                        .foregroundStyle(tokens.textSecondary)
                }

                addressEntry
                vehicleEntry
                paymentMethodsEntry
                Button { path.append(.storeCatalog) } label: {
                    Label("Catálogo de lojas", systemImage: "storefront")
                        .font(PitGoTypography.categoryTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(tokens.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Button {
                    guard path.isEmpty else { return }
                    path.append(.providerGuinchoHistory)
                } label: {
                    Label("Histórico de atendimentos", systemImage: "clock.arrow.circlepath")
                        .font(PitGoTypography.categoryTitle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(tokens.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                appearanceSection

                if snapshot.legacyProviderMigrationAvailable {
                    migrationEntry
                }

                Spacer()

                Button(action: { showSignOutConfirmation = true }) {
                    Text("Sair")
                        .font(PitGoTypography.categoryTitle)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .foregroundStyle(.red)
                .overlay(Capsule().stroke(Color.red, lineWidth: 1.5))
                .frame(minHeight: 44)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(tokens.background)
            .navigationTitle("Perfil")
            .navigationDestination(for: PitGoRoute.self) { route in
                switch route {
                case .providerMigrationStart:
                    ProviderMigrationStartView(
                        repository: migrationRepository,
                        coordinator: migrationCoordinator,
                        onSwitchAccount: onSwitchAccountForMigration
                    )
                case .clientAddress:
                    ClientAddressView(
                        repository: clientAddressRepository,
                        locationRepository: locationRepository,
                        onFinished: { path.removeLast() },
                        onSessionExpired: onSignOut
                    )
                case .paymentMethods:
                    PaymentMethodsView(repository: savedCardRepository)
                case .providerGuinchoHistory:
                    GuinchoHistoryView(repository: guinchoHistoryRepository, inspectionRepository: guinchoInspectionRepository,
                                       ratingRepository: serviceRatingRepository,
                                       onBack: { path.removeLast() })
                case .storeCatalog:
                    StoreCatalogView(repository: storeRepository, ownerStoreID: nil)
                case .serviceMap, .requestService, .appointmentTracking, .guinchoInspectionReview, .providerAppointmentTracking,
                     .mobileDispatchNewSearch, .mobileDispatchSearch, .providerRequest,
                     .pitTec, .pitTecProviderRequest, .guincho:
                    EmptyView()
                }
            }
            .confirmationDialog(
                "Encerrar sessão?",
                isPresented: $showSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sair", role: .destructive, action: onSignOut)
                Button("Cancelar", role: .cancel) {}
            }
        }
    }

    /// `014` FR-007 — endereço editável sem sair da aba Perfil.
    private var addressEntry: some View {
        Button(action: { guard path.isEmpty else { return }; path.append(.clientAddress) }) {
            HStack {
                Image(systemName: "mappin.and.ellipse").foregroundStyle(tokens.accent).accessibilityHidden(true)
                Text("Endereço")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding()
        }
        .foregroundStyle(tokens.textPrimary)
        .background(tokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(tokens.outline, lineWidth: 1))
        .frame(minHeight: 44)
    }

    /// `018` FR-019 — único ponto de entrada para cadastrar/gerenciar cartões; nunca inline no
    /// checkout.
    private var paymentMethodsEntry: some View {
        Button(action: { guard path.isEmpty else { return }; path.append(.paymentMethods) }) {
            HStack {
                Image(systemName: "creditcard").foregroundStyle(tokens.accent).accessibilityHidden(true)
                Text("Formas de pagamento")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding()
        }
        .foregroundStyle(tokens.textPrimary)
        .background(tokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(tokens.outline, lineWidth: 1))
        .frame(minHeight: 44)
    }

    /// `014` FR-007 — veículo padrão visível e com atalho de edição/cadastro.
    private var vehicleEntry: some View {
        Button(action: onOpenGarage) {
            HStack {
                Image(systemName: "car.fill").foregroundStyle(tokens.accent).accessibilityHidden(true)
                if let vehicle = snapshot.primaryVehicle {
                    Text("\(vehicle.brand) \(vehicle.model)")
                } else {
                    Text("Nenhum veículo cadastrado")
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding()
        }
        .foregroundStyle(tokens.textPrimary)
        .background(tokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(tokens.outline, lineWidth: 1))
        .frame(minHeight: 44)
    }

    /// `014` FR-008 — aparência aplicada imediatamente e persistida entre sessões (`@AppStorage`).
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aparência").font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
            Picker("Aparência", selection: $appearance) {
                ForEach(AppAppearance.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var migrationEntry: some View {
        Button(action: { path.append(.providerMigrationStart) }) {
            HStack {
                Text("Migrar empresa")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding()
        }
        .foregroundStyle(tokens.textPrimary)
        .background(tokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(tokens.outline, lineWidth: 1))
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = snapshot.profile.avatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                case let .success(image):
                    image.resizable().scaledToFill()
                case .failure:
                    initialsAvatar
                @unknown default:
                    initialsAvatar
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(Circle())
        } else {
            initialsAvatar
        }
    }

    private var initialsAvatar: some View {
        Text(snapshot.profile.initials)
            .font(PitGoTypography.sectionTitle)
            .foregroundStyle(.white)
            .frame(width: 88, height: 88)
            .background(tokens.accent)
            .clipShape(Circle())
    }
}
