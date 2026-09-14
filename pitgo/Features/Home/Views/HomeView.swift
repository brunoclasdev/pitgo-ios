//
//  HomeView.swift
//  pitgo
//
//  Conteúdo da aba "Início": snapshot autorizado da conta + catálogo real em duas colunas fixas. A
//  `TabView` que hospeda esta View é compartilhada (`Core/UI/PitGoBottomTabs`, ver `002`/`003`).
//  Desde `009`, cada card abre o mapa de descoberta pelo UUID real do serviço (`PitGoRoute.
//  serviceMap`), substituindo o `RequestServiceView` demo de `003`.
//

import SwiftUI

struct HomeView: View {
    @Environment(\.pitGoTokens) private var tokens
    @State private var viewModel: HomeViewModel

    let onDiagnosticTap: () -> Void
    let onServiceTap: (UUID, ServiceDispatchKind) -> Void
    let onOpenGarage: () -> Void
    let onOpenAppointment: (UUID) -> Void
    /// `014` FR-005 — abre o cadastro/edição de endereço do cliente.
    let onOpenAddress: () -> Void

    @State private var appointmentIDInput = ""

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    init(
        repository: AccountRepository,
        catalogRepository: ServiceCatalogRepository,
        userID: UUID,
        authEmail: String,
        onDiagnosticTap: @escaping () -> Void,
        onServiceTap: @escaping (UUID, ServiceDispatchKind) -> Void,
        onOpenGarage: @escaping () -> Void,
        onOpenAppointment: @escaping (UUID) -> Void,
        onOpenAddress: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: HomeViewModel(
            repository: repository,
            catalogRepository: catalogRepository,
            userID: userID,
            authEmail: authEmail
        ))
        self.onDiagnosticTap = onDiagnosticTap
        self.onServiceTap = onServiceTap
        self.onOpenGarage = onOpenGarage
        self.onOpenAppointment = onOpenAppointment
        self.onOpenAddress = onOpenAddress
    }

    var body: some View {
        content
            .background(tokens.background)
            .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .content(snapshot, services):
            mainContent(profile: snapshot.profile, vehicle: snapshot.primaryVehicle, services: services)
        case let .noVehicle(profile, services):
            mainContent(profile: profile, vehicle: nil, services: services)
        case .failure:
            failureState
        }
    }

    private var failureState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("Não foi possível carregar sua Home agora.")
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

    private func mainContent(profile: Profile, vehicle: Vehicle?, services: LoadState<[HomeServiceListing]>) -> some View {
        ScrollView {
            // `.gridCellColumns(2)` num `Group` dentro de `LazyVGrid` não estava propagando de
            // forma confiável para cada filho (achado nesta sessão, confirmado num device físico —
            // header/veículo e diagnóstico/título apareciam lado a lado em vez de empilhados).
            // Seções de largura total ficam num `LazyVStack` comum; só a grade de serviços — que
            // realmente precisa de 2 colunas — usa `LazyVGrid`.
            LazyVStack(spacing: 16) {
                headerSection(profile: profile)
                vehicleSection(vehicle: vehicle)
                diagnosticSection
                Text("O que seu carro precisa hoje?")
                    .font(PitGoTypography.sectionTitle)
                    .foregroundStyle(tokens.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)

                LazyVGrid(columns: columns, spacing: 16) {
                    servicesGridContent(services)
                }

                appointmentTrackingEntry
            }
            .padding(16)
        }
    }

    /// Despacho/aceite de atendimento está fora do escopo desta feature (ver spec.md "Out of
    /// Scope") — ponto de entrada mínimo para acompanhar um atendimento já existente (ex.: inserido
    /// por fixture administrativa, ver quickstart.md).
    private var appointmentTrackingEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Acompanhar atendimento").font(PitGoTypography.categoryTitle)
            HStack {
                TextField("ID do atendimento", text: $appointmentIDInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .frame(minHeight: 44)
                    .background(tokens.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button("Abrir") {
                    guard let appointmentID = UUID(uuidString: appointmentIDInput) else { return }
                    onOpenAppointment(appointmentID)
                }
                .frame(minHeight: 44)
                .disabled(UUID(uuidString: appointmentIDInput) == nil)
            }
        }
    }

    @ViewBuilder
    private func servicesGridContent(_ services: LoadState<[HomeServiceListing]>) -> some View {
        switch services {
        case .loading:
            ProgressView("Carregando serviços…")
                .gridCellColumns(2)
        case .empty:
            Text("Nenhum serviço disponível no momento.")
                .font(PitGoTypography.caption)
                .foregroundStyle(tokens.textSecondary)
                .gridCellColumns(2)
        case .failure:
            VStack(alignment: .leading, spacing: 8) {
                Text("Não foi possível carregar os serviços.")
                    .font(PitGoTypography.caption)
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
                Button("Tentar novamente") { viewModel.retryServices() }
            }
            .gridCellColumns(2)
        case let .content(listings):
            ForEach(listings) { listing in
                ServiceCard(listing: listing) {
                    onServiceTap(listing.serviceID, listing.dispatchKind)
                }
            }
        }
    }

    private func headerSection(profile: Profile) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Olá,")
                    .font(PitGoTypography.body)
                    .foregroundStyle(tokens.textSecondary)
                (Text(profile.displayName) + Text(" 👋"))
                    .font(PitGoTypography.sectionTitle)
                    .foregroundStyle(tokens.textPrimary)
            }

            Spacer(minLength: 0)

            avatar(profile: profile)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func avatar(profile: Profile) -> some View {
        if let url = profile.avatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                case let .success(image):
                    image.resizable().scaledToFill()
                case .failure:
                    initialsAvatar(profile: profile)
                @unknown default:
                    initialsAvatar(profile: profile)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(Circle())
        } else {
            initialsAvatar(profile: profile)
        }
    }

    private func initialsAvatar(profile: Profile) -> some View {
        Text(profile.initials)
            .font(PitGoTypography.categoryTitle)
            .foregroundStyle(.white)
            .frame(width: 48, height: 48)
            .background(tokens.accent)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func vehicleSection(vehicle: Vehicle?) -> some View {
        if let vehicle {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Veículo selecionado")
                        .font(PitGoTypography.caption)
                        .foregroundStyle(tokens.textSecondary)

                    HStack(spacing: 12) {
                        Text("🚗")
                            .font(.system(size: 22))
                            .frame(width: 44, height: 44)
                            .background(tokens.purpleContainer)
                            .clipShape(Circle())
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
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tokens.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(tokens.outline, lineWidth: 1)
                )
                .accessibilityElement(children: .combine)

                Button(action: onOpenAddress) {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(tokens.accent)
                            .accessibilityHidden(true)
                        Text("Endereço não cadastrado")
                            .font(PitGoTypography.body)
                            .foregroundStyle(tokens.textPrimary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .foregroundStyle(tokens.textSecondary)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Toque para cadastrar seu endereço")
            }
        } else {
            Button(action: onOpenGarage) {
                HStack(spacing: 12) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(tokens.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nenhum veículo selecionado")
                            .font(PitGoTypography.categoryTitle)
                            .foregroundStyle(tokens.textPrimary)
                        Text("Toque para cadastrar ou selecionar um veículo")
                            .font(PitGoTypography.caption)
                            .foregroundStyle(tokens.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tokens.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(tokens.outline, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .accessibilityAddTraits(.isButton)
        }
    }

    private var diagnosticSection: some View {
        Button(action: onDiagnosticTap) {
            HStack(spacing: 12) {
                Image(systemName: viewModel.diagnostic.symbolName)
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(tokens.accent)
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.diagnostic.title)
                        .font(PitGoTypography.categoryTitle)
                        .foregroundStyle(tokens.textPrimary)
                    Text(viewModel.diagnostic.description)
                        .font(PitGoTypography.caption)
                        .foregroundStyle(tokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .foregroundStyle(tokens.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tokens.purpleContainer)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tokens.accent.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct ServiceCard: View {
    @Environment(\.pitGoTokens) private var tokens
    let listing: HomeServiceListing
    let action: () -> Void

    /// Restrição temporária a pedido do cliente (2026-09-14): só PitTec fica navegável na Home — as
    /// demais modalidades continuam vindo do catálogo real (nenhum dado é ocultado), só ficam
    /// visualmente desabilitadas com "Em manutenção" em vez de abrir o despacho.
    private var isUnderMaintenance: Bool { listing.dispatchKind != .pittecAutoSequential }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(categoryEmoji)
                        .font(.system(size: 22))
                        .frame(width: 44, height: 44)
                        .background(tokens.purpleContainer)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                    Spacer(minLength: 4)
                    if isUnderMaintenance {
                        Text("Em manutenção")
                            .font(PitGoTypography.caption)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text(listing.serviceName)
                    .font(PitGoTypography.categoryTitle)
                    .foregroundStyle(tokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !isUnderMaintenance {
                    if let minimumPrice = listing.minimumPrice {
                        Text("A partir de \(formattedPrice(minimumPrice))")
                            .font(PitGoTypography.caption)
                            .foregroundStyle(tokens.textSecondary)
                    } else {
                        Text(listing.categoryName)
                            .font(PitGoTypography.caption)
                            .foregroundStyle(tokens.textSecondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tokens.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(tokens.outline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .disabled(isUnderMaintenance)
        .opacity(isUnderMaintenance ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isUnderMaintenance ? "\(listing.serviceName), em manutenção" : listing.serviceName)
    }

    /// Emoji por categoria (`categoryName` já vem de `list_home_services()`, `013`) — substitui o
    /// ícone único genérico anterior por uma identidade visual por serviço; `🔧` cobre qualquer
    /// categoria fora deste conjunto conhecido, sem quebrar para nomes futuros do catálogo.
    private var categoryEmoji: String {
        let name = listing.categoryName.lowercased()
        if name.contains("bateria") { return "🔋" }
        if name.contains("óleo") || name.contains("oleo") { return "🛢️" }
        if name.contains("pneu") { return "🛞" }
        if name.contains("painel") || name.contains("luz") || name.contains("diagnóstico") || name.contains("diagnostico") { return "⚠️" }
        if name.contains("liga") || name.contains("partida") { return "🚗" }
        if name.contains("reparo") { return "🔧" }
        return "🔧"
    }

    private func formattedPrice(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: value as NSDecimalNumber) ?? "R$ \(value)"
    }
}
