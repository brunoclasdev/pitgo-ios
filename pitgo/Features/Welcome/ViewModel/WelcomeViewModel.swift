//
//  WelcomeViewModel.swift
//  pitgo
//

import Combine
import Foundation

/// Estado imutável da Welcome. Nasce completo; "Criar conta" e "Cadastrar empresa" não o alteram.
struct WelcomeUiState {
    let benefits: [WelcomeBenefit]
}

@MainActor
final class WelcomeViewModel: ObservableObject {
    @Published private(set) var state: WelcomeUiState

    init(benefits: [WelcomeBenefit] = WelcomeBenefit.all) {
        state = WelcomeUiState(benefits: benefits.sorted { $0.displayOrder < $1.displayOrder })
    }
}
