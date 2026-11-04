//
//  AppointmentTrackingView.swift
//  pitgo
//
//  Acompanhamento privado de atendimento — `View` filha focada, sem `TabView` (ver contracts/
//  navigation-session.md "UI shells"). Conecta ao aparecer, desconecta ao desaparecer — nenhum
//  histórico é mantido; só a posição atual aplicável.
//

import CoreLocation
import SwiftUI

struct AppointmentTrackingView: View {
    @Environment(\.pitGoTokens) private var tokens
    @StateObject private var viewModel: AppointmentTrackingViewModel
    let ratingRepository: ServiceRatingRepository

    let appointmentID: UUID

    init(appointmentID: UUID, repository: AppointmentTrackingRepository, ratingRepository: ServiceRatingRepository) {
        self.appointmentID = appointmentID
        self.ratingRepository = ratingRepository
        _viewModel = StateObject(wrappedValue: AppointmentTrackingViewModel(repository: repository))
    }

    var body: some View {
        ZStack {
            mapSection.ignoresSafeArea(edges: .bottom)
            ServiceMapCard {
                VStack(spacing: 0) {
                    statusBar
                    ServiceRatingOffer(appointmentID: appointmentID, repository: ratingRepository)
                }
            }
        }
        .background(tokens.background)
        .navigationTitle("Acompanhar atendimento")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.connect(appointmentID: appointmentID) }
        .onDisappear { viewModel.disconnect() }
    }

    private var mapSection: some View {
        let coordinate: CLLocationCoordinate2D? = {
            switch viewModel.marker {
            case let .live(location, _), let .stale(location, _): return location
            case .unavailable, .ended: return nil
            }
        }()
        return PitGoMapView(annotations: coordinate.map { [PitGoMapAnnotationItem(id: "provider", coordinate: $0, title: "Prestador")] } ?? [],
            centerCoordinate: coordinate, zoomLevel: 15, showsUserLocation: true)
            .overlay(alignment: .topLeading) { MapAttributionView().padding(12) }
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
