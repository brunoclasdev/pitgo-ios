//
//  PitTecHomeValuesTab.swift
//  pitgo
//
//  Aba "Valores" da home do PitTec (`022`, US2, FR-008) — preço configurado do atendimento PitTec,
//  somente para consulta (spec.md Clarifications, 2026-09-14: sem edição por esta tela).
//

import SwiftUI

struct PitTecHomeValuesTab: View {
    @Environment(\.pitGoTokens) private var tokens
    let pricingState: PitTecPricingLoadState

    var body: some View {
        VStack {
            Spacer()
            switch pricingState {
            case .loading:
                ProgressView()
            case let .loaded(info):
                VStack(spacing: 8) {
                    Text(info.serviceName)
                        .font(PitGoTypography.categoryTitle)
                        .foregroundStyle(tokens.textSecondary)
                    Text(formattedPrice(info.price))
                        .font(PitGoTypography.sectionTitle)
                        .accessibilityAddTraits(.isHeader)
                }
            case .failure:
                Text("Não foi possível carregar o valor configurado agora.")
                    .font(PitGoTypography.body)
                    .foregroundStyle(tokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tokens.background)
    }

    private func formattedPrice(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: amount as NSDecimalNumber) ?? "R$ \(amount)"
    }
}
