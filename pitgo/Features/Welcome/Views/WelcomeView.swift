//
//  WelcomeView.swift
//  pitgo
//
//  Destino inicial do app: gradiente roxo fixo em Light/Dark (ver contracts/initial-ui-navigation.md).
//  Somente "Entrar" navega; as demais ações dão feedback visual e permanecem aqui.
//

import SwiftUI

struct WelcomeView: View {
    @StateObject private var viewModel = WelcomeViewModel()

    let onCreateAccount: () -> Void
    let onEnter: () -> Void
    let onRegisterCompany: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [PitGoPalette.brandPurple, PitGoPalette.darkPurple],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    Text("PitGo")
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.top, 24)

                    VStack(spacing: 12) {
                        VStack(spacing: 4) {
                            Text("Seu carro precisa.")
                            Text("O PitGo resolve.")
                        }
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)

                        Text("Encontre assistência para bateria, óleo, pneus e muito mais, onde você estiver.")
                            .font(PitGoTypography.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    VStack(spacing: 16) {
                        ForEach(viewModel.state.benefits) { benefit in
                            WelcomeBenefitCard(benefit: benefit)
                        }
                    }

                    VStack(spacing: 12) {
                        Button(action: onEnter) {
                            Text("Entrar")
                                .font(PitGoTypography.categoryTitle)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .foregroundStyle(PitGoPalette.brandPurple)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .frame(minHeight: 44)

                        Button(action: onCreateAccount) {
                            Text("Criar conta")
                                .font(PitGoTypography.categoryTitle)
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .foregroundStyle(.white)
                        .overlay(Capsule().stroke(Color.white, lineWidth: 1.5))
                        .frame(minHeight: 44)

                        Button(action: onRegisterCompany) {
                            Text("Sou uma empresa · Cadastrar")
                                .font(PitGoTypography.body)
                                .underline()
                        }
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(minHeight: 44)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct WelcomeBenefitCard: View {
    let benefit: WelcomeBenefit

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: benefit.symbolName)
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.15))
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(benefit.title)
                    .font(PitGoTypography.categoryTitle)
                    .foregroundStyle(.white)
                Text(benefit.description)
                    .font(PitGoTypography.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WelcomeView(onCreateAccount: {}, onEnter: {}, onRegisterCompany: {})
}
