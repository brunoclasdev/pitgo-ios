//
//  VehicleOnboardingView.swift
//  pitgo
//
//  Convite pós-cadastro (ver contracts/navigation.md "VehicleOnboardingView"). Superfície
//  autenticada sem `TabView`; Voltar/gesto não resolve a decisão pendente silenciosamente — como é
//  a raiz renderizada diretamente por `PitGoRootView` (sem `NavigationStack`/gesto de borda), não há
//  ação de descarte implícita. Conteúdo é simples o bastante para dispensar um ViewModel dedicado
//  (chama `VehicleOnboardingStore`/navegação diretamente via closures) — sem estado local próprio.
//

import SwiftUI

struct VehicleOnboardingView: View {
    @Environment(\.pitGoTokens) private var tokens
    let onRegisterVehicle: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "car.fill")
                .font(.system(size: 48))
                .foregroundStyle(tokens.accent)
            Text("Quer cadastrar seu veículo agora?")
                .font(PitGoTypography.sectionTitle)
                .foregroundStyle(tokens.textPrimary)
                .multilineTextAlignment(.center)
            Text("Isso personaliza a Home com os dados do seu carro. Você pode fazer isso depois pela Garagem.")
                .font(PitGoTypography.body)
                .foregroundStyle(tokens.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()

            Button(action: onRegisterVehicle) {
                Text("Cadastrar veículo")
                    .font(PitGoTypography.categoryTitle)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .foregroundStyle(.white)
            .background(tokens.accent)
            .clipShape(Capsule())
            .frame(minHeight: 56)

            Button(action: onSkip) {
                Text("Agora não")
                    .font(PitGoTypography.categoryTitle)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .foregroundStyle(tokens.accent)
            .frame(minHeight: 44)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tokens.background)
        .interactiveDismissDisabled()
    }
}
