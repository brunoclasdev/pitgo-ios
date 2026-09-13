//
//  ProviderMigrationStartView.swift
//  pitgo
//
//  Primeira metade da migração assistida — rodando ainda na sessão CLIENT original (ver
//  contracts/navigation-session.md "Assisted migration stack"). "Trocar de conta" faz logout
//  intencional; o desafio sobrevive em `ProviderMigrationCoordinator`.
//

import SwiftUI

struct ProviderMigrationStartView: View {
    @Environment(\.pitGoTokens) private var tokens
    @State private var viewModel: ProviderMigrationStartViewModel

    let onSwitchAccount: () -> Void

    init(
        repository: ProviderMigrationRepository,
        coordinator: ProviderMigrationCoordinator,
        onSwitchAccount: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: ProviderMigrationStartViewModel(repository: repository, coordinator: coordinator))
        self.onSwitchAccount = onSwitchAccount
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Migrar empresa para uma conta própria")
                    .font(PitGoTypography.sectionTitle)
                    .accessibilityAddTraits(.isHeader)

                Text("Sua conta de cliente possui uma empresa cadastrada pelo modelo anterior. Você pode transferir essa empresa para uma conta empresarial própria, com um e-mail diferente. Seu perfil de cliente permanece como está.")
                    .font(PitGoTypography.body)
                    .foregroundStyle(tokens.textSecondary)

                content
            }
            .padding(20)
        }
        .background(tokens.background)
        .navigationTitle("Migrar empresa")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            startButton
        case .beginning:
            ProgressView("Preparando migração…")
        case let .pending(expiresAt, requirements):
            VStack(alignment: .leading, spacing: 16) {
                Label("Migração iniciada — válida até \(expiresAt.formatted(date: .omitted, time: .shortened)).", systemImage: "clock")
                    .font(PitGoTypography.caption)
                    .foregroundStyle(tokens.textSecondary)
                    .accessibilityAddTraits(.updatesFrequently)
                if let requirements, !requirements.isEmpty {
                    Text(requirements)
                        .font(PitGoTypography.caption)
                        .foregroundStyle(tokens.textSecondary)
                }
                Text("Agora saia desta conta e entre ou cadastre-se com a conta empresarial que deve receber a empresa (um e-mail diferente do seu e-mail de cliente).")
                    .font(PitGoTypography.body)
                switchAccountButton
                Button("Cancelar migração") { viewModel.cancel() }
                    .frame(minHeight: 44)
            }
        case let .failure(reason):
            VStack(alignment: .leading, spacing: 12) {
                Text(message(for: reason))
                    .font(PitGoTypography.caption)
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
                startButton
            }
        }
    }

    private var startButton: some View {
        Button(action: { viewModel.begin() }) {
            Text("Iniciar migração")
                .frame(maxWidth: .infinity)
                .padding()
        }
        .foregroundStyle(.white)
        .background(tokens.accent)
        .clipShape(Capsule())
        .frame(minHeight: 56)
    }

    private var switchAccountButton: some View {
        Button(action: onSwitchAccount) {
            Text("Trocar de conta")
                .frame(maxWidth: .infinity)
                .padding()
        }
        .foregroundStyle(.white)
        .background(tokens.accent)
        .clipShape(Capsule())
        .frame(minHeight: 56)
    }

    private func message(for reason: ProviderMigrationFailureReason) -> LocalizedStringResource {
        switch reason {
        case .offline: "Sem conexão com a internet. Verifique sua rede e tente novamente."
        case .service: "Não foi possível concluir agora. Tente novamente em instantes."
        case .sessionExpired: "Sua sessão expirou. Entre novamente."
        case .expiredOrInvalid: "Não foi possível iniciar a migração. Verifique se sua conta possui uma empresa pendente."
        case .unknown: "Não foi possível iniciar a migração. Tente novamente."
        }
    }
}
