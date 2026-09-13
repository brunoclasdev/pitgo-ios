# Data Model: Layouts iniciais do PitGo (iOS)

## Overview

Todos os dados são demonstrativos, locais, imutáveis e disponíveis desde a primeira renderização.
Textos vêm do Strings Catalog (`String(localized:)`), ícones são SF Symbols ou assets locais. Sem
persistência, sincronização, identidade de backend ou estados de carregamento/erro/vazio.

## WelcomeBenefitID

```swift
enum WelcomeBenefitID: CaseIterable {
    case rapidAssistance   // displayOrder 0
    case verifiedTechnicians // displayOrder 1
    case allInApp          // displayOrder 2
}
```

## WelcomeBenefit

```swift
struct WelcomeBenefit: Identifiable {
    let id: WelcomeBenefitID
    let title: LocalizedStringResource
    let description: LocalizedStringResource
    let symbolName: String
    let displayOrder: Int
}
```

## WelcomeUiState

```swift
struct WelcomeUiState {
    let benefits: [WelcomeBenefit] // exatamente 3, ordenados por displayOrder
}
```

O estado nasce completo e não possui transições internas. "Criar conta" e "Cadastrar empresa" não
o alteram; "Entrar" é um evento de navegação tratado fora do ViewModel.

## DemoProfile

```swift
struct DemoProfile {
    let name: LocalizedStringResource // "Rafael"
    let initial: String                // "R"
}
```

## DemoVehicle

```swift
struct DemoVehicle {
    let model: LocalizedStringResource   // "BMW 320i M Sport"
    let year: Int                        // 2020
    let plate: LocalizedStringResource   // "PGO-2A20"
    let address: LocalizedStringResource // "Av. Paulista, 1500 · São Paulo"
    let symbolName: String
}
```

O ano e a placa são formatados na apresentação como `"\(year) · \(plate)"`.

## DiagnosticPrompt

```swift
struct DiagnosticPrompt {
    let title: LocalizedStringResource       // "Não sei o que aconteceu"
    let description: LocalizedStringResource // "Descreva o problema e sugerimos o serviço"
    let symbolName: String
}
```

O toque não altera estado nem navegação; apenas produz feedback visual do `Button`.

## DemoServiceID

```swift
enum DemoServiceID: CaseIterable {
    case battery         // displayOrder 0, R$ 320
    case oilChange        // displayOrder 1, R$ 220
    case tires             // displayOrder 2, R$ 180
    case dashboardLight    // displayOrder 3, R$ 150
    case minorRepairs      // displayOrder 4, R$ 260
    case carWontStart      // displayOrder 5, R$ 280
}
```

## DemoService

```swift
struct DemoService: Identifiable {
    let id: DemoServiceID
    let name: LocalizedStringResource
    let symbolName: String
    let startingPriceReais: Int // > 0
    let displayOrder: Int
}
```

A View combina o preço numérico com o texto localizado "A partir de R$ %lld". Selecionar um
serviço emite somente seu `DemoServiceID`, fornece feedback e mantém a Home.

## BottomItemID

```swift
enum BottomItemID: CaseIterable {
    case home        // "Início" — selecionado nesta feature
    case services     // "Serviços"
    case garage        // "Garagem"
    case appointments   // "Atendimentos"
    case profile         // "Perfil"
}
```

Diferente do Android (onde `BottomNavigationItem` é um modelo de dados renderizado manualmente com
`NavigationBar`/`NavigationBarItem`), no iOS os cinco destinos são declarados diretamente como
`.tabItem` do `TabView` — a própria `TabView` já garante exatamente uma aba selecionada por vez,
então não existe um campo `selectedBottomItem` solto no `HomeUiState`: a seleção é o próprio estado
de navegação do `TabView` (`@State private var selectedTab: BottomItemID = .home`).

## HomeUiState

```swift
struct HomeUiState {
    let profile: DemoProfile
    let vehicle: DemoVehicle
    let diagnostic: DiagnosticPrompt
    let services: [DemoService] // exatamente 6, ordenados por displayOrder
}
```

## Relationships and invariants

```text
WelcomeUiState 1 ─── 3 WelcomeBenefit

HomeUiState 1 ─── 1 DemoProfile
            1 ─── 1 DemoVehicle
            1 ─── 1 DiagnosticPrompt
            1 ─── 6 DemoService
```

- Listas são criadas uma vez, ordenadas e expostas somente para leitura (`let`, não `var`).
- IDs e ordens não se repetem.
- Nenhum modelo contém URL, token, localização real, credencial ou identificador remoto.
- Cards não alteram `HomeUiState` nesta feature.
- Não existe mapeamento DTO → domínio → UI porque há somente uma representação local útil.

## Navigation state transitions

```text
WELCOME --Enter--> HOME
HOME --System Back / swipe back--> WELCOME
WELCOME --System Back--> App suspenso (comportamento padrão iOS; não há "sair" explícito)
```

- `Create account` e `Register company`: `WELCOME → WELCOME` com feedback visual.
- `Diagnostic`, `DemoService` e troca de aba do `TabView`: `HOME → HOME` com feedback visual (a
  troca de aba é permitida pela `TabView` nativa, mas as abas além de Início não têm conteúdo
  funcional nesta feature — ver Scope Boundaries do `spec.md`).
- Toques repetidos em Enter durante a transição não adicionam outra Home (ver `research.md` §9).
