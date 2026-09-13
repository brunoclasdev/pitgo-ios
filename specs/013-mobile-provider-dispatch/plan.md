# Implementation Plan: Busca e despacho de prestadores móveis (iOS)

**Branch**: `013-mobile-provider-dispatch` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/013-mobile-provider-dispatch/spec.md`

## Summary

Implementar o client iOS de um fluxo dedicado de despacho móvel (guincho), consumindo o backend
**já implementado e compartilhado** com o Android: schema de busca/candidatos/appointment
estendido, ~10 RPCs transacionais e idempotentes, Supabase Cron de expiração de 60 segundos e
Broadcast privado em dois tópicos. Nenhuma migration, RPC ou job novo é criado nesta feature iOS.

O client mantém `@Observable` ViewModels separados por papel (cliente/provider), reutiliza MapLibre
Native iOS (`010`), `CoreLocation` (`009`) e Realtime (`009`), e restaura o destino correto após
reinício do app ou nova autenticação da mesma conta via um `DispatchResumeCoordinator`.

## Technical Context

**Language/Version**: Swift 6, modo de concorrência estrita

**Primary Dependencies**: `supabase-swift` (`Auth`/`PostgREST`/`Realtime`, já habilitados);
MapLibre Native iOS (`010`); `CoreLocation` (`009`). Nenhuma dependência nova.

**Storage**: Supabase PostgreSQL/PostGIS (schema compartilhado, inalterado); sem banco local, fila
offline ou histórico de localização; uma preferência técnica leve em `UserDefaults` apenas para
lease de tracker/conta (sem coordenada/proposta/token)

**Testing**: sem testes automatizados, conforme a governança do projeto; verificação (leitura) do
schema/Cron compartilhados, build via `xcodebuild` e matriz manual em `quickstart.md`

**Target Platform**: iOS 17+, iPhone e iPad, primeiro e segundo plano, portrait/landscape, Dynamic
Type grande

**Project Type**: aplicativo iOS nativo de alvo único com backend Supabase compartilhado

**Performance Goals**: primeira proposta ou vazio em até 5s em 95% das buscas; posição válida
publicada a cada ~10s e refletida em até 15s; posição stale após 30s; expiração sem resposta aos
60s (garantida pelo backend); seleção correta com 100 providers elegíveis numa região

**Constraints**: raios fixos 10/25/50km (backend); uma busca ativa por cliente/serviço e uma
solicitação ativa por provider (backend); preço congelado (backend); sem service-role no bundle,
DML direto, relógio do dispositivo como autoridade, histórico de coordenadas, push notifications,
`NSLocationAlwaysAndWhenInUseUsageDescription` além do já pedido em `009`, `SwiftData`/
`UserDefaults` para o fluxo além da lease técnica, ou migration nova

**Scale/Scope**: nenhuma migration nova; duas Views dedicadas (cliente e provider), integração com
Home/Dashboard/MapLibre/navegação existentes, generalização do `ProviderLocationTracker` (`009`)
para dois alvos

## Constitution Check

*GATE inicial e pós-design: aprovado sem exceções.*

- **Simplicidade/YAGNI — PASS**: reutiliza `Auth`/`PostgREST`/`Realtime`, MapLibre, `CoreLocation`,
  tracker de localização e tabelas de appointments já existentes. Nenhuma dependência de push,
  `SwiftData` para o fluxo, framework de DI ou Use Case.
- **iOS nativo/MVVM — PASS**: Views SwiftUI permanecem stateless; ViewModels separados por papel
  possuem estado e coordenação; um Repository encapsula o Supabase; a navegação recebe somente IDs
  opacos; o `ProviderLocationTracker` é o proprietário processual do loop de localização.
- **Estado/UX — PASS**: busca, proposta, espera, aceite, atendimento, cancelamento, término, erros,
  localização e ações pendentes são `enum`s explícitos no `@Observable`. O mapa é complementar e
  toda informação/ação tem representação textual acessível.
- **Dados/segurança — PASS**: RPCs já `SECURITY DEFINER`, `search_path=''`, ownership de
  `auth.uid()`, papéis validados, transições serializadas (backend, inalterado). Broadcast privado
  já autorizado por RLS e carrega apenas IDs/status/revisão. Coordenadas correntes nunca formam
  histórico.
- **Qualidade proporcional — PASS**: migration/constraints/índices/Cron já existentes e verificados
  pelo Android cobrem os riscos de backend. Build, verificação de schema e matriz manual verificam
  o client sem gerar testes automatizados não solicitados.

O design pós-Phase 1 mantém todos os gates aprovados. Nenhuma migration nova é necessária — o
schema/RPCs/Cron já existem e são compartilhados.

## Project Structure

### Documentation (this feature)

```text
specs/013-mobile-provider-dispatch/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── mobile-dispatch-rpcs.md            # já existente/compartilhado
│   ├── mobile-dispatch-realtime.md
│   └── mobile-dispatch-ui-navigation.md
└── tasks.md                         # criado posteriormente por $speckit-tasks
```

### Source Code (repository root)

```text
pitgo/
├── Core/
│   ├── Catalog/{Model,Repository}/ServiceCatalogModels.swift, ServiceCatalogRepository.swift   # + dispatchKind
│   ├── Location/{Data,Model,Repository}/                     # 009, inalterado
│   ├── Map/Model/MapSurfaceModels.swift                       # 010, + .mobileProvider
│   ├── Navigation/{PitGoRoute.swift, PitGoRootView.swift}
│   └── Auth/Store/SessionStore.swift
└── Features/
    ├── AppointmentTracking/{Data,Model,Repository,ViewModel,Views}/   # 009/010, inalterado
    ├── Home/{Model,ViewModel,Views}/
    ├── MobileDispatch/
    │   ├── Data/MobileDispatchDTOs.swift
    │   ├── Model/MobileDispatchModels.swift
    │   ├── Repository/MobileDispatchRepository.swift
    │   ├── Coordinator/DispatchResumeCoordinator.swift
    │   ├── Views/
    │   │   ├── ClientMobileDispatchView.swift
    │   │   ├── MobileDispatchMapCoordinator.swift
    │   │   └── ProviderIncomingRequestView.swift
    │   └── ViewModel/
    │       ├── ClientMobileDispatchViewModel.swift
    │       └── ProviderIncomingRequestViewModel.swift
    ├── ProviderDashboard/{Model,Repository,ViewModel,Views}/
    ├── ProviderMap/{Model,Repository,ViewModel,Views}/
    └── ProviderTracking/
        ├── Model/ProviderTrackingModels.swift            # + ProviderTrackingTarget
        ├── Data/ProviderLocationDTOs.swift
        ├── Repository/{ProviderLocationRepository.swift, ProviderTrackingStateRepository.swift}
        └── ProviderLocationTracker.swift                  # generalizado: .discovery | .appointment

# Nenhuma migration nova — o backend já existe no repositório Android.
```

**Structure Decision**: manter o alvo único e a arquitetura feature-first. O novo domínio fica em
`Features/MobileDispatch`; catálogo, mapa e navegação recebem apenas extensões compartilhadas que
já têm mais de um consumidor. O `ProviderLocationTracker` (`009`) é generalizado para descoberta e
atendimento, evitando dois loops de sensor. Nenhuma migration é autorada neste repositório.

## Complexity Tracking

Nenhuma violação constitucional foi identificada.
