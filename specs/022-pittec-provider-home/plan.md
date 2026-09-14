# Implementation Plan: Home do PitTec

**Branch**: `022-pittec-provider-home` | **Date**: 2026-09-14 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/022-pittec-provider-home/spec.md`

## Summary

Hoje, todo prestador logado (`.authenticatedProviderReady`) — Fixo, Móvel ou PitTec — cai na mesma
`ProviderDashboardView`: um `ScrollView` simples com nome/e-mail, seletor de modalidade, toggle de
disponibilidade, status de publicação de localização (texto) e botão de sair. Não há mapa, e a
disponibilidade fica perdida no meio do scroll.

Esta feature introduz uma home dedicada e exclusiva para quem está na modalidade PitTec
(`ProviderLocationMode.pittec`): uma `TabView` de 4 abas (Mapa, Dados da corrida, Valores, Perfil),
onde a aba "Mapa" mostra `PitGoMapView` centralizado na posição atual do próprio dispositivo (a
mesma posição já capturada por `ProviderDiscoveryTracker` para despacho, sem nova fonte de
localização) com um card de disponibilidade fixo no topo. Prestadores Fixo/Móvel continuam vendo a
`ProviderDashboardView` atual, sem nenhuma mudança. A notificação de novas solicitações (push
Realtime + navegação automática já existente em `ProviderDashboardViewModel`) não muda.

## Technical Context

**Language/Version**: Swift 6.0 (`SWIFT_VERSION` do projeto)

**Primary Dependencies**: SwiftUI (`TabView`, `NavigationStack`), MapLibre Native iOS
(`PitGoMapView`, já usado por `PitTecClientView`/`ProviderTrackingView`), Swift Concurrency
(`async`/`await`, `AsyncStream`) — nenhuma dependência nova

**Storage**: N/A (nenhuma mudança de persistência local ou schema Supabase; lê `providers` e
`provider_services` já existentes via Postgrest, mesmo padrão de
`ProviderRegistrationRepository.fetchOwnAggregate`)

**Testing**: XCTest disponível no projeto; não solicitado explicitamente para esta feature (regra V
da constituição) — validação por `quickstart.md`

**Target Platform**: iOS 17+

**Project Type**: App iOS nativo (Xcode single project); nova feature `Features/PitTecHome`
(View/ViewModel/Repository/Model) + ajuste pontual em `PitGoRootView` (roteamento por
`locationMode`) + generalização de `Core/UI/PitGoBottomTabs` para aceitar um conjunto de abas
diferente do cliente

**Performance Goals**: mapa e card de disponibilidade visíveis em até 2s após abrir a home (SC-001);
posição no mapa atualizada a cada publicação de localização (hoje 10s, `ProviderDiscoveryTracker.
publishInterval`), sem chamada de rede adicional além da já existente

**Constraints**: nenhuma permissão nova (reaproveita `NSLocationWhenInUseUsageDescription`/`Always`
já solicitadas por `ProviderDiscoveryTracker`); nenhuma mudança de RPC, Edge Function ou schema
Supabase; card de disponibilidade reaproveita `ProviderDashboardRepository.setAvailability` já
existente

**Scale/Scope**: uma feature nova (4 Views de aba + 1 ViewModel + 1 Repository leve para
"Valores") + 1 componente `Core/UI` generalizado (`PitGoBottomTabs`) + 1 ponto de decisão em
`PitGoRootView`/`ProviderDashboardView`; não afeta o fluxo do cliente nem prestadores Fixo/Móvel

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Simplicidade/YAGNI**: PASS — reaproveita `PitGoMapView`, `ProviderDiscoveryTracker`,
  `ProviderDashboardRepository.setAvailability` e o padrão de leitura direta de
  `provider_services` via Postgrest já usado em `ProviderRegistrationRepository`. Nenhuma RPC,
  Edge Function, tabela ou dependência nova. A única generalização de código existente
  (`PitGoBottomTabs`) é necessária porque hoje ele está hardcoded aos 5 destinos do cliente — sem
  generalizar, a alternativa seria duplicar toda a montagem de `TabView`+`tabItem`, o que a
  constituição desencoraja mais do que generalizar um componente já teoricamente genérico.
- **II. MVVM**: PASS — nova `PitTecHomeViewModel` concentra estado (aba atual, snapshot do
  provider, último fix de localização, preço, atendimento ativo); as 4 Views só renderizam. Nenhum
  acesso direto a Repository/CLLocationManager pelas Views.
- **III. Estado previsível**: PASS — aba selecionada é um único `enum` (`PitTecHomeTab`), estados de
  carregamento/erro de cada aba seguem o mesmo padrão de `enum` já usado em
  `ProviderDashboardUiState`/`PitTecClientUiState`, sem `Bool`s paralelos.
- **IV. Dados/segurança/falhas explícitas**: PASS — localização segue o mesmo tratamento de
  permissão negada/serviço desativado já existente em `ProviderDiscoveryTracker`
  (`TrackingDegradedReason`); nenhum dado sensível novo é exibido ou logado.
- **V. Qualidade proporcional**: PASS — sem testes automatizados não solicitados; mudança
  localizada a uma feature nova + 1 componente compartilhado + 1 ponto de roteamento existente.

Nenhuma violação a justificar em Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/022-pittec-provider-home/
├── plan.md              # This file ($speckit-plan command output)
├── research.md          # Phase 0 output ($speckit-plan command)
├── data-model.md        # Phase 1 output ($speckit-plan command)
├── quickstart.md        # Phase 1 output ($speckit-plan command)
├── contracts/           # Phase 1 output ($speckit-plan command)
└── tasks.md             # Phase 2 output ($speckit-tasks command - NOT created by $speckit-plan)
```

### Source Code (repository root)

```text
pitgo/
├── Core/
│   ├── Navigation/
│   │   └── PitGoRootView.swift            # ajuste: decide PitTecHomeView vs ProviderDashboardView
│   └── UI/
│       └── PitGoBottomTabs.swift          # generalizado para aceitar qualquer conjunto de abas
└── Features/
    ├── ProviderDashboard/                  # inalterado — continua servindo Fixo/Móvel
    └── PitTecHome/                         # NOVA feature desta spec
        ├── Model/
        │   └── PitTecHomeModels.swift       # PitTecHomeTab, PitTecHomeUiState, PitTecPricingInfo
        ├── Repository/
        │   └── PitTecPricingRepository.swift # leitura de provider_services (preço, view-only)
        ├── ViewModel/
        │   └── PitTecHomeViewModel.swift
        └── Views/
            ├── PitTecHomeView.swift          # TabView raiz (4 abas)
            ├── PitTecHomeMapTab.swift        # mapa + card de disponibilidade
            ├── PitTecHomeRideTab.swift       # "Dados da corrida"
            ├── PitTecHomeValuesTab.swift     # "Valores"
            └── PitTecHomeProfileTab.swift    # "Perfil"
```

**Structure Decision**: Nova feature `Features/PitTecHome`, seguindo a mesma organização por
feature (Model/Repository/ViewModel/Views) das demais (`ProviderDashboard`, `PitTec`). Reaproveita
`ProviderDiscoveryTracker`, `ProviderDashboardRepository` e `PitTecRepository` já existentes via
injeção pelo inicializador — nenhum deles é duplicado. `PitGoRootView` passa a escolher entre
`ProviderDashboardView` e `PitTecHomeView` a partir de `snapshot.provider.locationMode`, no mesmo
ponto onde já injeta as demais dependências do provider hoje.

## Complexity Tracking

*Sem violações à Constitution Check — seção não aplicável.*
