//
//  GuinchoIncomingRequestCard.swift
//  pitgo
//
//  Card global da oferta paga do guincho (`029`). Recebe um snapshot já autorizado pelo backend;
//  não carrega dados nem executa regras de despacho.
//

import SwiftUI

struct GuinchoIncomingRequestCard: View {
    @Environment(\.pitGoTokens) private var tokens

    let snapshot: MobileDispatchSnapshot
    let isResponding: Bool
    let failure: String?
    let onAccept: () -> Void
    let onDecline: () -> Void

    private var appointment: DispatchAppointment? { snapshot.appointment }
    private var trip: GuinchoTripSummary? { snapshot.guinchoTrip }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.fill").foregroundStyle(tokens.accent)
                Text("Nova solicitação de guincho")
                    .font(PitGoTypography.categoryTitle)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                if let deadline = appointment?.responseDeadline {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(remaining(deadline: deadline, serverNow: snapshot.serverNow, now: context.date))
                            .font(PitGoTypography.caption.monospacedDigit())
                            .accessibilityLabel("Tempo restante para responder")
                    }
                }
            }

            if let trip {
                Text(trip.clientName).font(PitGoTypography.body).bold()
                Label(trip.vehicle, systemImage: "car.fill")
                    .font(PitGoTypography.caption)
                detail("Retirada", trip.pickupAddress, symbol: "location.fill")
                detail("Destino", trip.destinationAddress, symbol: "flag.fill")
            }
            if let appointment {
                Text("Sua remuneração: \(appointment.quotedPrice.formatted(.currency(code: "BRL")))")
                    .font(PitGoTypography.body).bold()
            }
            if let failure {
                Text(failure)
                    .font(PitGoTypography.caption)
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            HStack(spacing: 12) {
                Button(action: onAccept) {
                    label("Aceitar", symbol: "checkmark", color: .green)
                }
                .disabled(isResponding || !(snapshot.allowedActions.contains(.accept)))
                Button(action: onDecline) {
                    label("Recusar", symbol: "xmark", color: .red)
                }
                .disabled(isResponding || !(snapshot.allowedActions.contains(.decline)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(tokens.accent, lineWidth: 2))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
    }

    private func detail(_ title: String, _ value: String, symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
                Text(value).font(PitGoTypography.caption).lineLimit(2)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(tokens.accent)
        }
    }

    private func label(_ title: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 8) {
            if isResponding { ProgressView().tint(color) }
            else { Image(systemName: symbol) }
            Text(title).font(PitGoTypography.body).bold()
        }
        .foregroundStyle(color == .green ? .white : color)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(color == .green ? color : .clear)
        .overlay(Capsule().stroke(color, lineWidth: color == .green ? 0 : 1.5))
        .clipShape(Capsule())
        .contentShape(Capsule())
    }

    private func remaining(deadline: Date, serverNow: Date, now: Date) -> String {
        // `serverNow` mantém a referência do snapshot; diferença desde então acompanha a expiração
        // sem reiniciar a janela de resposta quando a view é recriada.
        let seconds = max(0, Int(deadline.timeIntervalSince(serverNow) - now.timeIntervalSince(snapshot.serverNow)))
        return "\(seconds)s"
    }
}
