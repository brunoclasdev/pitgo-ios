//
//  ProviderDashboardModels.swift
//  pitgo
//
//  Área empresarial pronta (`.authenticatedProviderReady`, ver data-model.md de `009`). Resumo +
//  modalidade/disponibilidade + logout — nenhum dado de outra empresa.
//

import Foundation

enum ProviderDashboardFailureReason: Hashable {
    case offline
    case service
    case unknown
}

enum ProviderDashboardUiState {
    case content(ProviderSnapshot)
    case refreshing(ProviderSnapshot)
    case failure(ProviderDashboardFailureReason)
}

enum ProviderSettingsFailureReason: Hashable {
    case offline
    case service
    case sessionExpired
    case unknown
}
