//
//  ProviderMigrationClaimView.swift
//  pitgo
//
//  Segunda metade da migração — já na nova sessão PROVIDER (`.authenticatedProviderOnboarding` +
//  desafio em memória, ver contracts/navigation-session.md). Sem `TabView`.
//

import SwiftUI

struct ProviderMigrationClaimView: View {
    @Environment(\.pitGoTokens) private var tokens
    @StateObject private var viewModel: ProviderMigrationClaimViewModel
    @State private var locationMode: ProviderLocationMode = .fixed

    let onMigrated: () -> Void

    init(
        repository: ProviderMigrationRepository,
        coordinator: ProviderMigrationCoordinator,
        onMigrated: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ProviderMigrationClaimViewModel(repository: repository, coordinator: coordinator))
        self.onMigrated = onMigrated
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Concluir migração da empresa")
                    .font(PitGoTypography.sectionTitle)
                    .accessibilityAddTraits(.isHeader)

                Text("Confirme a modalidade da empresa para concluir a transferência para esta conta.")
                    .font(PitGoTypography.body)
                    .foregroundStyle(tokens.textSecondary)

                Picker("Modalidade", selection: $locationMode) {
                    Text("Fixo (endereço)").tag(ProviderLocationMode.fixed)
                    Text("Móvel (em atendimento)").tag(ProviderLocationMode.mobile)
                }
                .pickerStyle(.segmented)

                content
            }
            .padding(20)
        }
        .background(tokens.background)
        .navigationTitle("Migrar empresa")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onChange(of: viewModel.state) { newValue in
            if newValue == .succeeded { onMigrated() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .claiming:
            claimButton
        case .succeeded:
            EmptyView()
        case let .failure(reason):
            VStack(alignment: .leading, spacing: 12) {
                Text(message(for: reason))
                    .font(PitGoTypography.caption)
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
                claimButton
            }
        }
    }

    private var claimButton: some View {
        Button(action: { viewModel.claim(locationMode: locationMode) }) {
            ZStack {
                if viewModel.state == .claiming {
                    ProgressView().tint(.white)
                }
                Text("Concluir migração")
                    .opacity(viewModel.state == .claiming ? 0 : 1)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .foregroundStyle(.white)
        .background(tokens.accent)
        .clipShape(Capsule())
        .frame(minHeight: 56)
        .disabled(viewModel.state == .claiming)
    }

    private func message(for reason: ProviderMigrationFailureReason) -> LocalizedStringResource {
        switch reason {
        case .offline: "Sem conexão com a internet. Verifique sua rede e tente novamente."
        case .service: "Não foi possível concluir agora. Tente novamente em instantes."
        case .sessionExpired: "Sua sessão expirou. Entre novamente."
        case .expiredOrInvalid: "O desafio de migração expirou ou não é mais válido. Reinicie a migração a partir da conta de cliente."
        case .unknown: "Não foi possível concluir a migração. Tente novamente."
        }
    }
}
