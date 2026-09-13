# Implementation Plan: Mapa do PitTec sempre centralizado na localização do cliente

**Branch**: `020-pittec-client-map-centering` | **Date**: 2026-09-13 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/020-pittec-client-map-centering/spec.md`

## Summary

Ao tocar no card PitTec, a tela de descoberta (`PitTecClientView.discoveringState`) hoje só
apresenta `PitGoMapView` quando existe ao menos um PitTec elegível, e mesmo nesse caso não passa
`centerCoordinate`/`showsUserLocation` — nenhum dos dois cenários mostra a posição do cliente. Sem
PitTec disponível (descoberta vazia ou busca esgotada), a tela cai para um estado só de texto sem
mapa nenhum. A correção reaproveita o fix de localização já obtido por
`PitTecClientViewModel.loadDiscovery()` (hoje descartado numa propriedade privada) para sempre
centralizar `PitGoMapView` na posição do cliente — com ou sem marcador de PitTec — e substitui os
dois estados hoje só-texto (descoberta vazia e busca esgotada) por mapa centralizado com a mensagem
sobreposta, sem alterar nenhum outro estado, contrato de backend ou RPC.

## Technical Context

**Language/Version**: Swift 6.0 (`SWIFT_VERSION` do projeto)

**Primary Dependencies**: SwiftUI, MapLibre Native iOS (`PitGoMapView`, já usado por esta e outras
telas), Swift Concurrency (`async`/`await`) — nenhuma dependência nova

**Storage**: N/A (nenhuma mudança de persistência local ou schema Supabase)

**Testing**: XCTest disponível no projeto; não solicitado explicitamente para esta feature (regra
V da constituição) — validação por `quickstart.md`

**Target Platform**: iOS 17+

**Project Type**: App iOS nativo (Xcode single project), mudança restrita à feature
`Features/PitTec`

**Performance Goals**: nenhum aumento no tempo entre obter o fix de localização e apresentar o
mapa (SC-003) — nenhuma chamada de rede adicional é introduzida

**Constraints**: nenhuma permissão nova; reaproveita o mesmo fluxo de autorização/fix one-shot já
existente (`DeviceLocationRepository.requestOneShotFix`); nenhuma mudança de RPC, Edge Function ou
schema Supabase

**Scale/Scope**: uma View (`PitTecClientView`) e uma ViewModel (`PitTecClientViewModel`); afeta 2
dos ~7 estados de UI do PitTec (`discovering` e `terminal` quando `status == .exhausted`); os
demais estados (`content`/aceito, `completed`, `cancelled`, `locationRequired`, `failure`,
`sessionExpired`) permanecem inalterados

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Simplicidade/YAGNI**: PASS — reaproveita `PitGoMapView` e `DeviceLocationRepository` já
  existentes; nenhuma dependência, camada ou abstração nova. Único ajuste estrutural é expor
  (`private(set)`) um fix já obtido, no mesmo padrão já usado por `routeContext` na mesma
  ViewModel.
- **II. MVVM**: PASS — a View só monta `centerCoordinate`/`annotations` a partir de estado exposto
  pela ViewModel; nenhuma regra de negócio nova na View, nenhum acesso direto a
  `CLLocationManager`/repositório pela View.
- **III. Estado previsível**: PASS — nenhum novo `Bool` paralelo; o mapa nos dois estados afetados
  continua determinado pelo `enum` existente (`PitTecClientUiState.discovering`,
  `ServiceSearchStatus.exhausted` dentro de `.terminal`).
- **IV. Dados/segurança**: PASS — nenhuma posição exata de provider é exposta antes do aceite
  (marcadores de `PitTecMarker` continuam aproximados); a posição exibida é sempre a do próprio
  cliente. Nenhum dado sensível novo em log.
- **Localização (IV)**: PASS — o comportamento de permissão negada/desativada
  (`locationRequiredState`) não muda; esta feature só atua a partir do momento em que um fix válido
  já existe.

Nenhuma violação — tabela de Complexity Tracking não se aplica.

**Re-check pós-design (Fase 1)**: `research.md` e `data-model.md` confirmam que nenhuma entidade,
RPC, dependência ou camada nova é introduzida — apenas a exposição de um valor já existente
(`lastFix`) no mesmo padrão de `routeContext`. Todos os gates permanecem PASS sem alteração.

## Project Structure

### Documentation (this feature)

```text
specs/020-pittec-client-map-centering/
├── plan.md              # This file ($speckit-plan command output)
├── research.md          # Phase 0 output ($speckit-plan command)
├── data-model.md         # Phase 1 output ($speckit-plan command)
├── quickstart.md         # Phase 1 output ($speckit-plan command)
├── contracts/            # Phase 1 output ($speckit-plan command)
└── tasks.md              # Phase 2 output ($speckit-tasks command - NOT created by $speckit-plan)
```

### Source Code (repository root)

```text
pitgo/
├── Features/PitTec/
│   ├── ViewModel/
│   │   └── PitTecClientViewModel.swift   # expõe o fix de localização já obtido (lastFix)
│   ├── Views/
│   │   └── PitTecClientView.swift        # discoveringState + terminalState(.exhausted) passam
│   │                                      # a centralizar PitGoMapView na posição do cliente
│   └── Model/
│       └── PitTecModels.swift            # inalterado (PitTecClientUiState mantém a mesma forma)
└── Core/UI/
    └── PitGoMapView.swift                # inalterado — já suporta centerCoordinate/showsUserLocation
```

**Structure Decision**: Mudança contida inteiramente na feature `Features/PitTec` existente (View +
ViewModel), sem novo grupo/arquivo e sem tocar `Features/ProviderMap` (mapa genérico de outros
serviços, fora de escopo desta spec) nem `Core/UI/PitGoMapView.swift` (já expõe as propriedades
necessárias).
