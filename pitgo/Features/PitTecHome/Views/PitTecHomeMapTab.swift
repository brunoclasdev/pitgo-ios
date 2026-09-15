//
//  PitTecHomeMapTab.swift
//  pitgo
//
//  Aba "Mapa" da home do PitTec (`022`, US1) — mapa centralizado na posição atual do próprio
//  dispositivo (`viewModel.discoveryTracker.lastFix`, mesmo fix já usado para publicar a
//  localização de despacho) com um card de disponibilidade fixo no topo, tocável para alternar
//  (FR-001 a FR-004, FR-011).
//

import CoreLocation
import SwiftUI

struct PitTecHomeMapTab: View {
    @Environment(\.pitGoTokens) private var tokens
    @ObservedObject var viewModel: PitTecHomeViewModel
    let snapshot: ProviderSnapshot

    var body: some View {
        VStack(spacing: 0) {
            availabilityCard
            mapOrDegradedMessage
        }
        .background(tokens.background)
    }

    private var availabilityCard: some View {
        Button {
            viewModel.setAvailability(!snapshot.provider.available)
        } label: {
            HStack {
                Label {
                    Text(snapshot.provider.available ? "Disponível" : "Indisponível")
                        .font(PitGoTypography.sectionTitle)
                } icon: {
                    Image(systemName: snapshot.provider.available ? "checkmark.circle.fill" : "moon.zzz.fill")
                }
                Spacer()
            }
            .padding(16)
        }
        .foregroundStyle(snapshot.provider.available ? .green : tokens.textSecondary)
        .background(tokens.surface)
        .accessibilityAddTraits(.updatesFrequently)
        .overlay(alignment: .bottom) {
            if let failure = viewModel.settingsFailure {
                Text(message(for: failure))
                    .font(PitGoTypography.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    @ViewBuilder
    private var mapOrDegradedMessage: some View {
        // `022` fix: `discoveryTracker.lastFix` só existe enquanto "Disponível" está ligado — com o
        // provider indisponível, cai no `viewModel.mapFix` (fix único pedido sob demanda) em vez de
        // ficar preso para sempre em "Obtendo localização…".
        if let fix = viewModel.discoveryTracker.lastFix ?? viewModel.mapFix {
            PitGoMapView(
                annotations: [],
                centerCoordinate: CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude),
                showsUserLocation: true
            )
            .overlay(alignment: .bottomLeading) { MapAttributionView() }
        } else if let failure = viewModel.mapFixFailure {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "location.slash.fill")
                    .font(.largeTitle)
                    .foregroundStyle(tokens.textSecondary)
                Text(message(for: failure))
                    .font(PitGoTypography.body)
                    .foregroundStyle(tokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button("Tentar novamente") { viewModel.retryMapFix() }
                    .frame(minHeight: 44)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityAddTraits(.updatesFrequently)
        } else if case let .degraded(reason) = viewModel.discoveryTracker.state {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "location.slash.fill")
                    .font(.largeTitle)
                    .foregroundStyle(tokens.textSecondary)
                Text(degradedMessage(for: reason))
                    .font(PitGoTypography.body)
                    .foregroundStyle(tokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityAddTraits(.updatesFrequently)
        } else {
            VStack(spacing: 12) {
                Spacer()
                ProgressView("Obtendo localização…")
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private func degradedMessage(for reason: TrackingDegradedReason) -> String {
        switch reason {
        case .permissionDenied: return "Permita o acesso à localização nas Configurações para ver o mapa."
        case .locationServicesDisabled: return "Ative os Serviços de Localização para ver o mapa."
        case .publisherConflict: return "Localização sendo publicada por outro dispositivo/sessão."
        case .offline: return "Sem conexão — sua posição pode ficar desatualizada."
        case .service, .sessionExpired, .notEligible, .appointmentTerminal: return "Não foi possível obter sua localização agora."
        }
    }

    private func message(for reason: LocationRequiredReason) -> String {
        switch reason {
        case .permissionDenied: return "Permita o acesso à localização nas Configurações para ver o mapa."
        case .serviceDisabled: return "Ative os Serviços de Localização para ver o mapa."
        case .timeout, .unknown: return "Não foi possível obter sua localização agora."
        }
    }

    private func message(for reason: ProviderSettingsFailureReason) -> String {
        switch reason {
        case .offline: "Sem conexão com a internet. Verifique sua rede e tente novamente."
        case .service: "Não foi possível concluir agora. Tente novamente em instantes."
        case .sessionExpired: "Sua sessão expirou. Entre novamente."
        case .unknown: "Não foi possível concluir a ação. Tente novamente."
        }
    }
}
