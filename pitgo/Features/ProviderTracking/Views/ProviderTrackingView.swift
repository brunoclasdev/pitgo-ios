//
//  ProviderTrackingView.swift
//  pitgo
//
//  Controle/indicador de tracking do lado provider — `View` filha focada, sem `TabView` (ver
//  contracts/navigation-session.md "UI shells" de `009`). O iOS mostra automaticamente o indicador
//  de sistema de uso de localização em segundo plano; nenhuma notificação própria é construída.
//

import SwiftUI

struct ProviderTrackingView: View {
    @Environment(\.pitGoTokens) private var tokens
    @State private var viewModel: ProviderTrackingViewModel

    init(
        appointmentID: UUID,
        accountID: UUID,
        stateRepository: ProviderTrackingStateRepository,
        dashboardRepository: ProviderDashboardRepository
    ) {
        _viewModel = State(initialValue: ProviderTrackingViewModel(
            appointmentID: appointmentID,
            accountID: accountID,
            stateRepository: stateRepository,
            dashboardRepository: dashboardRepository
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Atendimento \(viewModel.appointmentID.uuidString.prefix(8))")
                .font(PitGoTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)

            statusView

            if let failure = viewModel.eligibilityFailure {
                Text(message(for: failure))
                    .font(PitGoTypography.caption)
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
            }

            actionButton

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.background)
        .navigationTitle("Localização em tempo real")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.state {
        case .stopped:
            Label("Localização não está sendo publicada.", systemImage: "location.slash")
                .font(PitGoTypography.body)
                .foregroundStyle(tokens.textSecondary)
        case .starting:
            Label("Iniciando…", systemImage: "location")
                .font(PitGoTypography.body)
                .foregroundStyle(tokens.textSecondary)
        case let .active(lastPublishedAt):
            Label("Publicando — última atualização às \(lastPublishedAt.formatted(date: .omitted, time: .standard))", systemImage: "location.fill")
                .font(PitGoTypography.body)
                .foregroundStyle(.green)
                .accessibilityAddTraits(.updatesFrequently)
        case let .degraded(reason):
            Label(degradedMessage(reason), systemImage: "exclamationmark.triangle.fill")
                .font(PitGoTypography.body)
                .foregroundStyle(.orange)
                .accessibilityAddTraits(.updatesFrequently)
        case .stopping:
            Label("Encerrando…", systemImage: "location.slash")
                .font(PitGoTypography.body)
                .foregroundStyle(tokens.textSecondary)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch viewModel.state {
        case .stopped, .degraded:
            Button(action: { viewModel.start() }) {
                Text("Iniciar publicação de localização")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .foregroundStyle(.white)
            .background(tokens.accent)
            .clipShape(Capsule())
            .frame(minHeight: 56)
        case .starting, .active:
            Button(role: .destructive, action: { viewModel.stop() }) {
                Text("Parar")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .foregroundStyle(.red)
            .overlay(Capsule().stroke(Color.red, lineWidth: 1.5))
            .frame(minHeight: 56)
        case .stopping:
            ProgressView()
        }
    }

    private func degradedMessage(_ reason: TrackingDegradedReason) -> String {
        switch reason {
        case .permissionDenied: "Permita o acesso à localização nas Configurações."
        case .locationServicesDisabled: "Ative os Serviços de Localização nas Configurações do sistema."
        case .publisherConflict: "Outro dispositivo está publicando a localização deste atendimento."
        case .offline: "Sem conexão com a internet."
        case .service: "Não foi possível concluir agora. Tente novamente em instantes."
        case .sessionExpired: "Sua sessão expirou. Entre novamente."
        case .notEligible: "Sua empresa não está elegível para tracking no momento (verifique modalidade/disponibilidade)."
        case .appointmentTerminal: "Este atendimento já foi concluído ou cancelado."
        }
    }

    private func message(for reason: TrackingDegradedReason) -> LocalizedStringResource {
        switch reason {
        case .permissionDenied: "Permita o acesso à localização nas Configurações."
        case .locationServicesDisabled: "Ative os Serviços de Localização nas Configurações do sistema."
        case .publisherConflict: "Outro dispositivo está publicando a localização deste atendimento."
        case .offline: "Sem conexão com a internet."
        case .service: "Não foi possível concluir agora. Tente novamente em instantes."
        case .sessionExpired: "Sua sessão expirou. Entre novamente."
        case .notEligible: "Sua empresa não está elegível para tracking no momento."
        case .appointmentTerminal: "Este atendimento já foi concluído ou cancelado."
        }
    }
}
