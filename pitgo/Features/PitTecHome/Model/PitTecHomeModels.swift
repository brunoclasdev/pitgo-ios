//
//  PitTecHomeModels.swift
//  pitgo
//
//  Home dedicada de quem está na modalidade PitTec (`022`) — mapa + disponibilidade + 4 abas
//  (Mapa/Dados da corrida/Valores/Perfil), substituindo a `ProviderDashboardView` genérica só para
//  essa modalidade. Nenhuma tabela, RPC ou Edge Function nova (ver research.md).
//

import Foundation

/// As 4 abas fixas desta home (spec.md FR-005) — conforma a `PitGoBottomTabItem` para reaproveitar
/// `Core/UI/PitGoBottomTabs` já usado pelo cliente.
enum PitTecHomeTab: CaseIterable, PitGoBottomTabItem {
    case map, ride, values, profile

    var title: LocalizedStringResource {
        switch self {
        case .map: "Mapa"
        case .ride: "Dados da corrida"
        case .values: "Valores"
        case .profile: "Perfil"
        }
    }

    var symbolName: String {
        switch self {
        case .map: "map.fill"
        case .ride: "car.fill"
        case .values: "dollarsign.circle.fill"
        case .profile: "person.crop.circle.fill"
        }
    }
}

/// Estado principal da tela — reaproveita `ProviderDashboardFailureReason` já existente (mesmo
/// motivo de falha ao carregar o `Provider` próprio, independente da apresentação).
enum PitTecHomeUiState {
    case content(ProviderSnapshot)
    case failure(ProviderDashboardFailureReason)
}

/// Preço configurado do atendimento PitTec (aba "Valores") — somente leitura (spec.md
/// Clarifications, 2026-09-14).
struct PitTecPricingInfo: Equatable {
    let price: Decimal
    let serviceName: String
}

enum PitTecPricingLoadState: Equatable {
    case loading
    case loaded(PitTecPricingInfo)
    case failure
}
