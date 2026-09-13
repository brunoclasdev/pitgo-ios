//
//  AppointmentTrackingView.swift
//  pitgo
//
//  Acompanhamento privado de atendimento — `View` filha focada, sem `TabView` (ver contracts/
//  navigation-session.md "UI shells"). Conecta ao aparecer, desconecta ao desaparecer — nenhum
//  histórico é mantido; só a posição atual aplicável.
//

import SwiftUI

struct AppointmentTrackingView: View {
    @Environment(\.pitGoTokens) private var tokens
    @State private var viewModel: AppointmentTrackingViewModel

    let appointmentID: UUID

    init(appointmentID: UUID, repository: AppointmentTrackingRepository) {
        self.appointmentID = appointmentID
        _viewModel = State(initialValue: AppointmentTrackingViewModel(repository: repository))
    }

    var body: some View {
        VStack(spacing: 0) {
            mapSection
            statusBar
        }
        .background(tokens.background)
        .navigationTitle("Acompanhar atendimento")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.connect(appointmentID: appointmentID) }
        .onDisappear { viewModel.disconnect() }
    }

    @ViewBuilder
    private var mapSection: some View {
        switch viewModel.marker {
        case .unavailable, .ended:
            VStack(spacing: 12) {
                Image(systemName: "location.slash")
                    .font(.system(size: 40))
                    .foregroundStyle(tokens.textSecondary)
                Text(viewModel.marker.isEnded ? "Este atendimento foi encerrado." : "Localização ainda não disponível.")
                    .font(PitGoTypography.body)
                    .foregroundStyle(tokens.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .live(location, _), let .stale(location, _):
            PitGoMapView(
                annotations: [PitGoMapAnnotationItem(id: "provider", coordinate: location, title: "Prestador")],
                centerCoordinate: location,
                zoomLevel: 15
            )
            .overlay(alignment: .bottomLeading) { MapAttributionView() }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: statusSymbol)
                .foregroundStyle(statusColor)
            Text(statusText)
                .font(PitGoTypography.caption)
                .foregroundStyle(tokens.textPrimary)
            Spacer()
        }
        .padding(16)
        .background(tokens.surface)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var statusSymbol: String {
        switch viewModel.marker {
        case .unavailable: "location.slash"
        case .live: "location.fill"
        case .stale: "location"
        case .ended: "checkmark.circle"
        }
    }

    private var statusColor: Color {
        switch viewModel.marker {
        case .unavailable: tokens.textSecondary
        case .live: .green
        case .stale: .orange
        case .ended: tokens.textSecondary
        }
    }

    private var statusText: String {
        switch viewModel.marker {
        case .unavailable: "Aguardando localização do prestador…"
        case let .live(_, updatedAt): "Ao vivo — atualizado às \(updatedAt.formatted(date: .omitted, time: .standard))"
        case let .stale(_, updatedAt): "Desatualizado — última atualização às \(updatedAt.formatted(date: .omitted, time: .standard))"
        case .ended: "Atendimento encerrado."
        }
    }
}

private extension AppointmentMarkerState {
    var isEnded: Bool {
        if case .ended = self { return true }
        return false
    }
}
