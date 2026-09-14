//
//  PitGoBottomTabs.swift
//  pitgo
//
//  Barra inferior fixa compartilhada por Home e RequestService (extraída de
//  `Features/Home/Views/HomeView.swift` em 002 — ver plan.md de 003). Só a aba "Início" tem
//  conteúdo funcional nesta etapa; as demais existem apenas como destino selecionável.
//
//  `022`: generalizada para aceitar qualquer conjunto de abas (`PitGoBottomTabItem`) em vez de só
//  os 5 destinos do cliente — reaproveitada pela home do PitTec (4 abas) sem duplicar a montagem de
//  `TabView`/`tabItem`/`Label`. `BottomItemID` (cliente) e `PitTecHomeTab` (`022`) são os dois
//  conjuntos concretos hoje; nenhum comportamento do cliente muda.
//

import SwiftUI

/// Qualquer conjunto de abas usável por `PitGoBottomTabs` — só título e ícone, sem nenhuma lógica.
/// Deliberadamente NÃO herda de `Hashable` aqui: um `enum` sem valores associados já ganha
/// `Equatable`/`Hashable` de graça do compilador; declarar `Hashable` de novo neste protocolo
/// forçava essas conformances a serem (re)geradas como "isolated conformance" da main actor sob o
/// isolamento padrão do módulo, travando a compilação (`PitGoBottomTabs<Item: ... & Hashable>` pede
/// `Hashable` como constraint genérica separada, que usa a conformância implícita sem problema).
protocol PitGoBottomTabItem {
    var title: LocalizedStringResource { get }
    var symbolName: String { get }
}

enum BottomItemID: CaseIterable, PitGoBottomTabItem {
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

/// `TabView` genérica sobre qualquer `PitGoBottomTabItem`. `content` decide o que cada aba
/// renderiza; a seleção é responsabilidade de quem instancia (`@State` do chamador).
struct PitGoBottomTabs<Item: PitGoBottomTabItem & CaseIterable & Hashable, Content: View>: View where Item.AllCases: RandomAccessCollection {
    @Binding var selection: Item
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        TabView(selection: $selection) {
            ForEach(Item.allCases, id: \.self) { item in
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
