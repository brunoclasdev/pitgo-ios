//
//  PitTecHomeProfileTab.swift
//  pitgo
//
//  Aba "Perfil" da home do PitTec (`022`, US2, FR-009) — dados de conta + encerrar sessão, mesmo
//  padrão de `ProviderDashboardView.signOutButton`.
//

import SwiftUI

struct PitTecHomeProfileTab: View {
    @Environment(\.pitGoTokens) private var tokens
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
            Spacer()
            signOutButton
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tokens.background)
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
