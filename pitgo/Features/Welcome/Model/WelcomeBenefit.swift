//
//  WelcomeBenefit.swift
//  pitgo
//

import Foundation

enum WelcomeBenefitID: CaseIterable {
    case rapidAssistance
    case verifiedTechnicians
    case allInApp
}

struct WelcomeBenefit: Identifiable {
    let id: WelcomeBenefitID
    let title: LocalizedStringResource
    let description: LocalizedStringResource
    let symbolName: String
    let displayOrder: Int
}

extension WelcomeBenefit {
    /// Os três benefícios da Welcome, na ordem de exibição (FR-004).
    static let all: [WelcomeBenefit] = [
        WelcomeBenefit(
            id: .rapidAssistance,
            title: "Atendimento rápido",
            description: "PitTechs próximos em minutos.",
            symbolName: "bolt.fill",
            displayOrder: 0
        ),
        WelcomeBenefit(
            id: .verifiedTechnicians,
            title: "Técnicos verificados",
            description: "Profissionais avaliados e aprovados.",
            symbolName: "checkmark.seal.fill",
            displayOrder: 1
        ),
        WelcomeBenefit(
            id: .allInApp,
            title: "Tudo pelo app",
            description: "Bateria, óleo, pneus, diagnóstico e mais.",
            symbolName: "iphone",
            displayOrder: 2
        ),
    ]
}
