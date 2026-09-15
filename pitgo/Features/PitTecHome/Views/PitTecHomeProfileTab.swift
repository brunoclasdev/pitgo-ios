//
//  PitTecHomeProfileTab.swift
//  pitgo
//
//  Aba "Perfil" da home do PitTec (`022`, US2, FR-009) — dados de conta + disponibilidade para
//  atendimento + encerrar sessão, mesmo padrão de `ProviderDashboardView.availabilitySection`
//  (`Toggle` ligado a `setAvailability`/`settingsFailure`). Segundo ponto de acesso ao mesmo
//  `snapshot.provider.available` já alternável pelo card no topo da aba Mapa
//  (`PitTecHomeMapTab.availabilityCard`) — mesma fonte de estado, sem lógica nova no repositório.
//

import SwiftUI

struct PitTecHomeProfileTab: View {
    @Environment(\.pitGoTokens) private var tokens
    @ObservedObject var viewModel: PitTecHomeViewModel
    let snapshot: ProviderSnapshot
    @Binding var showSignOutConfirmation: Bool
    let onSignOut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.provider.name)
                    .font(PitGoTypography.sectionTitle)
                    .foregroundStyle(tokens.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(snapshot.provider.email)
                    .font(PitGoTypography.body)
                    .foregroundStyle(tokens.textSecondary)
            }
            availabilitySection
            Spacer()
            signOutButton
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tokens.background)
    }

    private var availabilitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "Disponível para atendimento",
                isOn: Binding(get: { snapshot.provider.available }, set: { viewModel.setAvailability($0) })
            )
            .font(PitGoTypography.body)
            Text("Desligado, você fica invisível para novos clientes — atendimentos já aceitos continuam normalmente.")
                .font(PitGoTypography.caption)
                .foregroundStyle(tokens.textSecondary)
            if let failure = viewModel.settingsFailure {
                Text(message(for: failure))
                    .font(PitGoTypography.caption)
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    private func message(for reason: ProviderSettingsFailureReason) -> String {
        switch reason {
        case .offline: "Sem conexão com a internet. Verifique sua rede e tente novamente."
        case .service: "Não foi possível concluir agora. Tente novamente em instantes."
        case .sessionExpired: "Sua sessão expirou. Entre novamente."
        case .unknown: "Não foi possível concluir a ação. Tente novamente."
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
}
