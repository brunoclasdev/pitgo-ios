# Implementation Plan: PitTec sob demanda (iOS)

**Branch**: `015-pittec-on-demand` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/015-pittec-on-demand/spec.md`

## Summary

Adicionar o client iOS do PitTec — terceira modalidade de prestador e serviço sob demanda — sobre o
backend **já implementado e compartilhado** com o Android: novo `dispatch_kind`, RPCs transacionais
de descoberta anonimizada/despacho/chegada/conclusão, Supabase Cron/expiração e Edge Function
`pittec-route` (proxy OSRM). Nenhuma migration ou Edge Function nova é criada nesta feature iOS.

O client reutiliza o modelo de estados, os canais privados e o `ProviderLocationTracker` do despacho
móvel (`013`), generalizado para o modo `PITTEC`, e adiciona um fluxo SwiftUI em `Features/PitTec`,
extensões nos fluxos compartilhados do provider e um `RoutingRepository` para consumir a Edge
Function. Alertas de oferta em background/tela bloqueada usam notificações locais
(`UNUserNotificationCenter`), nunca push remoto (APNs) — mesma decisão consciente do Android de não
usar FCM nesta entrega.

## Technical Context

**Language/Version**: Swift 6, modo de concorrência estrita

**Primary Dependencies**: `supabase-swift` (`Auth`/`PostgREST`/`Functions`/`Realtime`, já
habilitados); MapLibre Native iOS (`010`); `CoreLocation` (`009`); `UserNotifications` (framework do
sistema, novo nesta feature — sem Swift Package). Nenhuma dependência de terceiros.

**Storage**: Supabase PostgreSQL com PostGIS/RLS/Realtime (backend compartilhado, inalterado);
nenhuma persistência local nova além das preferências técnicas já existentes (`013`)

**Testing**: sem testes automatizados, conforme a governança do projeto; verificação (leitura) do
schema/Edge Function compartilhados, build via `xcodebuild` e matriz manual em `quickstart.md`

**Target Platform**: iOS 17+, iPhone e iPad, primeiro/segundo plano e tela bloqueada

**Project Type**: aplicativo iOS nativo de alvo único com backend Supabase compartilhado

**Performance Goals**: atualizar o estado de despacho em até 5s quando o Realtime falhar (fallback
de polling); selecionar a próxima oferta numa transação (backend); atualização de rota refletida em
até 15s após movimento relevante; interação de mapa fluida

**Constraints**: timeout de 60s por provider (backend); raios progressivos 10/25/50km (backend); no
máximo 200 marcadores aproximados; uma busca PitTec ativa por cliente (backend); posições exatas
acessíveis somente aos participantes após aceite; sem chave de roteamento no bundle; sem
`NSLocationAlwaysAndWhenInUseUsageDescription` além do já pedido em `009`; sem APNs/push remoto;
nenhuma migration/Edge Function nova

**Scale/Scope**: um novo fluxo cliente (`Features/PitTec`), extensões em cadastro/dashboard/
atendimento do provider, um `Core/Routing`, notificações locais; nenhuma migration nova

## Constitution Check

*GATE inicial e pós-design: aprovado sem exceções.*

- **Simplicidade/YAGNI — PASS**: reutiliza `Auth`/`PostgREST`/`Functions`/`Realtime`, MapLibre,
  `CoreLocation` e o tracker de localização já existentes. `UserNotifications` é framework do
  sistema, sem dependência nova. Nenhum push remoto, framework de DI ou Use Case.
- **iOS nativo/MVVM — PASS**: Views SwiftUI stateless; ViewModels `@Observable` expõem estado e
  eventos; Repositories isolam Supabase/roteamento; `ProviderLocationTracker` é o proprietário
  processual do loop de localização/alerta.
- **Estado/UX — PASS**: busca, oferta, aceite, chegada, conclusão, cancelamento, timeout e retomada
  têm `enum`s explícitos. O mapa é complementar; toda informação/ação tem representação textual.
- **Dados/segurança — PASS**: RPCs já `SECURITY DEFINER`, descoberta já anonimizada, coordenadas
  exatas e rota limitadas aos participantes (backend, inalterado). Segredos de roteamento ficam na
  Edge Function, nunca no bundle.
- **Qualidade proporcional — PASS**: build, verificação de schema/Edge Function e matriz manual
  cobrem o risco sem gerar testes automatizados não solicitados.

## Design Decisions

1. `dispatchKind = .pittecAutoSequential` e `locationMode = .pittec` já existem no backend
   compartilhado; o client iOS só decodifica os novos casos de `enum` já existentes desde `009`/
   `013`.
2. PitTec continua modalidade de provider, não um novo papel de conta — nenhuma mudança em
   `AppSessionState` (`006`/`009`).
3. Seleção/ordenação/exclusão de recusados e criação da oferta acontecem inteiramente no backend
   (transação, lock, revisão, idempotência) — o client apenas consome o snapshot.
4. `.accepted` = "a caminho"; `.inProgress` = "chegou" para PitTec. A ação "Cheguei" efetua essa
   transição; concluir só é permitido depois dela.
5. Antes do aceite, o mapa recebe pontos estáveis aproximados (grade de ~500m) e IDs opacos —
   projeção já fechada pelo backend. Após o aceite, só os participantes acessam as tabelas exatas.
6. Enquanto disponível como PitTec, o `ProviderLocationTracker` (generalizado de `013`) observa o
   canal privado de ofertas e publica alerta local (`UserNotifications`) de alta prioridade, com som
   e deep link. A disponibilidade exige autorização de notificação. APNs não faz parte desta
   entrega; portanto, reinício do dispositivo e finalização forçada não têm garantia.
7. `RoutingRepository` chama a Edge Function `pittec-route` (já existente) para obter coordenadas
   privadas processadas e uma rota OSRM; em indisponibilidade, a UI mostra distância haversine e
   percurso tracejado.

Detalhes e alternativas em [research.md](research.md).

## Project Structure

### Documentation (this feature)

```text
specs/015-pittec-on-demand/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── pittec-rpcs.md                     # já existente/compartilhado
│   ├── pittec-realtime-notifications.md
│   └── pittec-routing-ui.md
└── tasks.md                         # criado posteriormente por $speckit-tasks
```

### Source Code (repository root)

```text
pitgo/
├── Core/
│   ├── Account/Model/AccountContext.swift          # 009, inalterado
│   ├── Catalog/{Model,Repository}/                  # 009, + PITTEC_AUTO_SEQUENTIAL já decodificado
│   ├── Location/                                    # 009, inalterado
│   ├── Map/Model/MapSurfaceModels.swift             # 010, + .pittecProvider
│   ├── Navigation/{PitGoRoute.swift, PitGoRootView.swift}
│   ├── Network/SupabaseClientProvider.swift
│   └── Routing/                                     # NOVO: contrato/Repository da Edge Function
│       ├── Model/RouteModels.swift
│       └── Repository/RoutingRepository.swift
└── Features/
    ├── PitTec/                                       # NOVO: descoberta, solicitação, mapa, ViewModel cliente
    │   ├── Model/PitTecModels.swift
    │   ├── Data/PitTecDTOs.swift
    │   ├── Repository/PitTecRepository.swift
    │   ├── ViewModel/PitTecClientViewModel.swift
    │   └── Views/{PitTecMapView.swift, PitTecMapCoordinator.swift}
    ├── MobileDispatch/                               # 013, transporte/estados compartilhados e oferta provider
    ├── AppointmentTracking/                          # 009/010/014, participantes/percurso/ações do atendimento
    ├── ProviderTracking/                              # 009/013, tracker generalizado + alerta de oferta
    │   └── ProviderLocationTracker.swift              # ajuste: + alvo .pittecAvailable
    ├── ProviderRegistration/                          # 007/009, opção PITTEC
    ├── ProviderDashboard/                              # 009/013, disponibilidade e modalidade pendente
    └── Home/                                           # card e navegação PitTec

# Nenhuma migration/Edge Function nova — o backend já existe no repositório Android.
```

**Structure Decision**: manter o alvo único e a arquitetura feature-first. `Features/PitTec`
concentra a experiência específica; componentes realmente transversais ficam em `Core`
(`Routing`), enquanto despacho, localização e atendimento existentes recebem extensões pequenas.
Nenhuma migration é autorada neste repositório.

## Complexity Tracking

Nenhuma violação constitucional foi identificada.
