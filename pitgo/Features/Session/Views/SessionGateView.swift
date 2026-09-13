//
//  SessionGateView.swift
//  pitgo
//
//  Destino raiz para `.initializing`/`.verifying`/`.offlineVerification`/`.blocked`
//  (ver contracts/navigation.md "SessionGateView"). Nunca mostra dados da Home.
//

import SwiftUI

struct SessionGateView: View {
    @Environment(\.pitGoTokens) private var tokens
    let state: AppSessionState
    let onRetry: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            switch state {
            case .initializing, .verifying:
                ProgressView()
            case .offlineVerification:
                Image(systemName: "wifi.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(tokens.textSecondary)
                Text("Não foi possível verificar sua sessão sem conexão com a internet.")
                    .font(PitGoTypography.body)
                    .foregroundStyle(tokens.textPrimary)
                    .multilineTextAlignment(.center)
                retryButton
            case .blocked:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(tokens.textSecondary)
                Text("Não foi possível carregar seu perfil agora.")
                    .font(PitGoTypography.body)
                    .foregroundStyle(tokens.textPrimary)
                    .multilineTextAlignment(.center)
                retryButton
                signOutButton
            default:
                ProgressView()
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tokens.background)
    }

    private var retryButton: some View {
        Button(action: onRetry) {
            Text("Tentar novamente")
                .font(PitGoTypography.categoryTitle)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .foregroundStyle(.white)
        .background(tokens.accent)
        .clipShape(Capsule())
        .frame(minHeight: 44)
    }

    private var signOutButton: some View {
        Button(action: onSignOut) {
            Text("Sair")
                .font(PitGoTypography.categoryTitle)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .foregroundStyle(tokens.accent)
        .overlay(Capsule().stroke(tokens.accent, lineWidth: 1.5))
        .frame(minHeight: 44)
    }
}
