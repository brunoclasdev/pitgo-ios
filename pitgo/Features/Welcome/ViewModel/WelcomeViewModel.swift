//
//  WelcomeViewModel.swift
//  pitgo
//

import Foundation

/// Estado imutável da Welcome. Nasce completo; "Criar conta" e "Cadastrar empresa" não o alteram.
struct WelcomeUiState {
    let benefits: [WelcomeBenefit]
}

@Observable
@MainActor
final class WelcomeViewModel {
    private(set) var state: WelcomeUiState

    init(benefits: [WelcomeBenefit] = WelcomeBenefit.all) {
        state = WelcomeUiState(benefits: benefits.sorted { $0.displayOrder < $1.displayOrder })
    }
}
