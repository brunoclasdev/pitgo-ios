//
//  PitTecHomeRideTab.swift
//  pitgo
//
//  Aba "Dados da corrida" da home do PitTec (`022`, US2, FR-007) — resumo do atendimento PitTec
//  ativo (já aceito) ou mensagem vazia quando não há nenhum. Uma solicitação nova (`PENDING`)
//  continua indo para o push automático já existente (`PitTecIncomingRequestView`) — não passa por
//  aqui, ver `research.md` §4.
//

import SwiftUI

struct PitTecHomeRideTab: View {
    @Environment(\.pitGoTokens) private var tokens
    let activeAppointment: PitTecAppointment?

    var body: some View {
        VStack {
            Spacer()
            if let appointment = activeAppointment {
                VStack(spacing: 12) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.largeTitle)
                        .foregroundStyle(tokens.accent)
                    Text(statusText(appointment))
                        .font(PitGoTypography.sectionTitle)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits([.isHeader, .updatesFrequently])
                    Text(formattedPrice(appointment.quotedPrice))
                        .font(PitGoTypography.body)
                        .foregroundStyle(tokens.textSecondary)
                }
                .padding(.horizontal, 32)
            } else {
                Text("As informações da corrida aparecem aqui depois de aceitar uma solicitação.")
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

    private func statusText(_ appointment: PitTecAppointment) -> String {
        switch appointment.status {
        case .awaitingClientConfirmation: "Aguardando o cliente confirmar o orçamento."
        case .awaitingPayment: "Orçamento confirmado — aguardando o pagamento."
        case .accepted: "A caminho do cliente."
        case .inProgress: "Atendimento em andamento."
        default: "Atendimento em andamento."
        }
    }

    private func formattedPrice(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: amount as NSDecimalNumber) ?? "R$ \(amount)"
    }
}
