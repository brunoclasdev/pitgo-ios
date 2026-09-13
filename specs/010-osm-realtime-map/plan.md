# Implementation Plan: Mapa OSM com MapLibre e atualização em tempo real (iOS)

**Branch**: `010-osm-realtime-map` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/010-osm-realtime-map/spec.md`

## Summary

Integrar MapLibre Native iOS (já indicado na constitution desde `009`) nas duas Views de mapa —
descoberta (`ServiceMapView`) e acompanhamento (`AppointmentTrackingView`) — através de um único
`MapLibreMapHost` (`UIViewRepresentable` encapsulando `MLNMapView`). A descoberta continuará
consultando a RPC espacial existente (`discover_service_providers`) e exibirá somente endereços
empresariais por uma `MLNShapeSource` clusterizada. A seleção abrirá um resumo SwiftUI com
"Solicitar atendimento". O acompanhamento reutilizará o mesmo host e atualizará uma
`MLNShapeSource` de um único marcador, sem recriar mapa, estilo ou layer.

O estilo MapLibre e seus tiles/sprites/glyphs virão obrigatoriamente de um provedor OSM gerenciado
configurado por ambiente (mesmo mecanismo de validação de build de `004`), com atribuição acessível
e sem fallback público. Nenhum outro SDK de mapa é introduzido. O hardening do stream de
localização (ordenação, `EMPTY`/`ENDED`, tombstone) já está aplicado no backend compartilhado — esta
feature apenas consome o contrato corrigido.

## Technical Context

**Language/Version**: Swift 6, modo de concorrência estrita

**Primary Dependencies**: MapLibre Native iOS (Swift Package, novo nesta feature); `supabase-swift`
(`PostgREST`/`Realtime`, já habilitados em `009`); `CoreLocation` (`009`, inalterado);
`Network.framework` (`NWPathMonitor`, novo — observação de conectividade, framework do sistema, sem
Swift Package)

**Storage**: PostgreSQL/Supabase existente (backend compartilhado); uma posição corrente por
atendimento; cache padrão gerenciado pelo SDK MapLibre, sem download offline; nenhum histórico

**Testing**: build via `xcodebuild`, verificação (leitura) do hardening já aplicado no backend e
validação manual em `quickstart.md`; nenhum teste automatizado, conforme governança do projeto

**Target Platform**: iOS 17+, iPhone e iPad, Debug e destino `generic/platform=iOS`; dispositivo
físico recomendado para os cenários de tiles/rede adversos

**Project Type**: aplicativo iOS nativo de alvo único, com backend Supabase compartilhado com o
Android

**Performance Goals**: primeiro mapa/resultados ou estado vazio em até 3s p95; até 200 resultados
por busca; nova posição refletida em até 10s p95; stale após 30s; uma atualização de `shape` por
mudança aceita, sem reconstrução do mapa

**Constraints**: MapLibre Native iOS obrigatório; estilo OSM gerenciado HTTPS sem demo/fallback
público; atribuição acessível; nenhum outro SDK de mapa; sem download offline, histórico ou mapa no
cadastro empresarial; posição móvel visível somente a participantes

**Scale/Scope**: duas Views de mapa existentes (`009`), no máximo 200 providers públicos por
viewport, um marcador móvel por atendimento e um host MapLibre compartilhado

## Constitution Check

*GATE inicial e pós-design: aprovado sem exceções.*

- **Simplicidade/YAGNI — PASS**: uma única dependência (MapLibre) e um host atendem os dois mapas.
  GeoJSON nativo fornece layers, clustering e atualização; nenhum wrapper adicional, plugin de
  annotation, cache próprio ou backend paralelo.
- **iOS nativo/MVVM — PASS**: Views SwiftUI continuam stateless, ViewModels `@Observable` e
  Repositories permanecem donos do Supabase. `UIViewRepresentable` encapsula a `UIView` nativa;
  ViewModels não conhecem `MLNMapView`, `MLNStyle` ou GeoJSON.
- **Estado/UX — PASS**: dados, estilo/recursos, permissão, viewport, seleção e recência têm tipos
  `enum` explícitos. Lista e resumo SwiftUI são a superfície acessível equivalente ao mapa.
- **Dados/segurança — PASS**: somente estilo/token client-safe entra no bundle. Descoberta usa o
  endereço público mínimo; localização móvel continua privada (RLS/Broadcast já aplicados).
  Revisões e tombstones (backend já endurecido) impedem regressão ou ressurreição de posição.
- **Qualidade proporcional — PASS**: MapLibre Native iOS tem manutenção ativa e benefício atual e
  já é a escolha da constitution. Build, lifecycle, estilo, acessibilidade e Realtime são
  verificados manualmente, sem criar testes não solicitados.

O design pós-Phase 1 mantém o gate aprovado. Não há hardening SQL a autorar nesta feature — o
hardening já existe e é compartilhado.

## Project Structure

### Documentation (this feature)

```text
specs/010-osm-realtime-map/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── map-ui-navigation.md
│   ├── maplibre-style-runtime.md
│   └── realtime-marker.md
└── tasks.md                         # criado posteriormente por $speckit-tasks
```

### Source Code (repository root)

```text
pitgo/
├── Core/
│   ├── Map/
│   │   ├── Config/ManagedMapStyleConfiguration.swift
│   │   ├── Model/MapSurfaceModels.swift
│   │   └── UI/MapLibreMapHost.swift          # UIViewRepresentable + Coordinator
│   ├── Network/ConnectivityObserver.swift    # NWPathMonitor
│   ├── Navigation/{PitGoRoute.swift, PitGoRootView.swift}
│   └── Catalog/Repository/ServiceCatalogRepository.swift   # de 009
└── Features/
    ├── ProviderMap/
    │   ├── Data/ServiceMapDTOs.swift
    │   ├── Model/ServiceMapModels.swift
    │   ├── Repository/ServiceMapRepository.swift
    │   └── ViewModel/{ServiceMapViewModel.swift}
    │   └── Views/{ServiceMapView.swift, ProviderMapStyleCoordinator.swift}
    ├── AppointmentTracking/
    │   ├── Model/AppointmentTrackingModels.swift
    │   ├── Repository/AppointmentTrackingRepository.swift
    │   ├── ViewModel/AppointmentTrackingViewModel.swift
    │   └── Views/{AppointmentTrackingView.swift, AppointmentMapStyleCoordinator.swift}
    └── RequestService/                        # de 003
        ├── Model/RequestServiceContent.swift
        ├── ViewModel/RequestServiceViewModel.swift
        └── Views/RequestServiceView.swift

# Nenhuma migration nova — o hardening SQL já existe no repositório Android.
```

**Structure Decision**: manter o alvo único e a organização por feature. `Core/Map/UI/
MapLibreMapHost` contém lifecycle, câmera, delegate e a fronteira genérica do estilo; os pequenos
Coordinators por feature transformam estado já validado em GeoJSON, sem regra de negócio.
Repositories existentes (`009`) são corrigidos/estendidos, não duplicados. Descoberta e
geocodificação (Edge Function) não mudam.

## Complexity Tracking

Nenhuma violação constitucional permanece. `UIViewRepresentable` é a integração oficial necessária
para hospedar uma `MLNMapView` UIKit dentro do app SwiftUI e evita adicionar uma segunda camada de
abstração sobre o SDK.
