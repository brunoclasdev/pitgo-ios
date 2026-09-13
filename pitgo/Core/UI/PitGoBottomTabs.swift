//
//  PitGoBottomTabs.swift
//  pitgo
//
//  Barra inferior fixa compartilhada por Home e RequestService (extraída de
//  `Features/Home/Views/HomeView.swift` em 002 — ver plan.md de 003). Só a aba "Início" tem
//  conteúdo funcional nesta etapa; as demais existem apenas como destino selecionável.
//

import SwiftUI

enum BottomItemID: CaseIterable {
    case home
    case services
    case garage
    case appointments
    case profile
}

extension BottomItemID {
    var title: LocalizedStringResource {
        switch self {
        case .home: "Início"
        case .services: "Serviços"
        case .garage: "Garagem"
        case .appointments: "Atendimentos"
        case .profile: "Perfil"
        }
    }

    var symbolName: String {
        switch self {
        case .home: "house.fill"
        case .services: "wrench.and.screwdriver.fill"
        case .garage: "car.2.fill"
        case .appointments: "calendar"
        case .profile: "person.crop.circle.fill"
        }
    }
}

/// `TabView` genérica com os cinco destinos padrão do PitGo. `content` decide o que cada aba
/// renderiza; a seleção é responsabilidade de quem instancia (`@State` do chamador).
struct PitGoBottomTabs<Content: View>: View {
    @Binding var selection: BottomItemID
    @ViewBuilder let content: (BottomItemID) -> Content

    var body: some View {
        TabView(selection: $selection) {
            ForEach(BottomItemID.allCases, id: \.self) { item in
                content(item)
                    .tabItem {
                        Label {
                            Text(item.title)
                        } icon: {
                            Image(systemName: item.symbolName)
                        }
                    }
                    .tag(item)
            }
        }
    }
}

/// Destino sem conteúdo funcional nesta etapa (Scope Boundaries de spec.md de 002/003). Ainda
/// assim selecionável e anunciado corretamente pelo `TabView` nativo.
struct PlaceholderTabContent: View {
    @Environment(\.pitGoTokens) private var tokens
    let title: LocalizedStringResource

    var body: some View {
        VStack {
            Spacer()
            Text(title)
                .font(PitGoTypography.body)
                .foregroundStyle(tokens.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tokens.background)
    }
}
