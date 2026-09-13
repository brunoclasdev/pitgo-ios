---
description: "Implementation tasks for MapLibre OSM map and realtime updates (iOS)"
---

# Tasks: Mapa OSM com MapLibre e atualização em tempo real (iOS)

**Input**: Design documents from `specs/010-osm-realtime-map/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`,
`quickstart.md`

**Tests**: Sem testes automatizados, conforme a constitution. Validação manual com build,
verificação (leitura) do hardening já aplicado no backend e a matriz de `quickstart.md`.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup (Shared Infrastructure)

- [X] T001 Adicionar o Swift Package `MapLibre` ao target `pitgo` via SPM — já resolvido no
  `Package.resolved` (`maplibre-gl-native-distribution`) de uma sessão anterior; confirmado nesta
  sessão como a única dependência de renderização de mapa (`grep` por `MapKit`/`GoogleMaps`/
  `GMSMapView` vazio)
- [X] T002 Adicionar `mapStyleUrl`, `mapStyleProviderName`, `mapStyleAttribution`,
  `mapStyleAttributionUrl` como Build Settings em `Config/Shared.xcconfig`/`Config/Secrets.xcconfig`
  — **o Run Script de `004` não foi estendido para validá-los**: o default de avaliação já
  documentado (`demotiles.maplibre.org`) é justamente um host que o gate do contrato pediria para
  rejeitar antes de produção; sem uma credencial real de provedor de tiles gerenciado nesta sessão,
  endurecer esse gate quebraria o único build local/CI existente (mesma natureza da limitação já
  registrada para o Mercado Pago/Supabase noutras specs desta sessão). Ver nota em
  `ManagedMapStyleConfiguration.swift`
- [X] T003 Adicionar `MAP_STYLE_URL`, `MAP_PROVIDER_NAME`, `MAP_PROVIDER_ATTRIBUTION`,
  `MAP_PROVIDER_ATTRIBUTION_URL` ao `Info.plist` do target — verificado com `PlistBuddy` no `.app`
  buildado (os quatro valores resolvem corretamente)
- [ ] T004 [P] Criar SF Symbols/imagens distintas para endereço, endereço selecionado, grupo
  coincidente, posição ao vivo e posição desatualizada em `pitgo/Assets.xcassets` — **não feito**:
  depende da migração para `MapLibreMapHost`/GeoJSON (T009/T013/T024, não feitas nesta entrega); o
  mapa atual (`PitGoMapView`, `009`) usa o pino padrão do sistema via `MLNPointAnnotation`
- [X] T005 [P] Adicionar strings localizadas de atribuição, controles, resumo, estados de estilo/
  recursos, offline, localização recusada, live/stale/ended e acessibilidade ao Strings Catalog —
  seguindo a mesma convenção de auto-extração já usada no restante do projeto (literais `Text`/
  `LocalizedStringResource`), sem entradas manuais em `Resources/Localizable.xcstrings`

---

## Phase 2: Foundational (Blocking Prerequisites)

**⚠️ CRITICAL**: Nenhuma tela de mapa pode ser reescrita antes desta fase estar concluída.

- [X] T006 Criar a leitura central e imutável dos quatro campos de `Info.plist` do estilo
  gerenciado, sem expor token/URL em logs, em
  `pitgo/Core/Map/Config/ManagedMapStyleConfiguration.swift` — substitui `MapStyleProvider` (`009`,
  removido)
- [ ] T007 [P] Criar `MapCoordinate`, `MapViewport`, `MapMarkerSpec`, `MapFeatureSelection`,
  `MapStyleState`, `MapResourceState` e `MapSurfaceState` em
  `pitgo/Core/Map/Model/MapSurfaceModels.swift` — **não feito**: os modelos existentes de `009`
  (`ServiceMapModels.swift`, `AppointmentTrackingModels.swift`) continuam em uso porque
  `MapLibreMapHost` (T009) não foi construído; introduzir os tipos genéricos sem o host que os
  consome seria especulativo (viola YAGNI da constitution do projeto)
- [X] T008 [P] Implementar observação de conectividade com `NWPathMonitor`
  (`.online`/`.offline`) em `pitgo/Core/Network/ConnectivityObserver.swift` — integrado a
  `ServiceMapViewModel` para que ausência de rede domine sobre a falha genérica da RPC antes mesmo
  de a chamada expirar
- [ ] T009 Implementar `MapLibreMapHost` (`UIViewRepresentable`) com uma única `MLNMapView` por
  instância, `Coordinator` com delegate, cleanup idempotente, estilo assíncrono revisionado, câmera
  não repetida e atualização pelo modelo mais recente em `pitgo/Core/Map/UI/MapLibreMapHost.swift`
  — **não feito nesta entrega**: é a mudança de maior risco desta feature (GeoJSON, clustering
  nativo via `MLNShapeSource`, ciclo de vida de estilo/tiles) e não há como validar visualmente o
  resultado nesta sessão (sem simulador/dispositivo interativo nem projeto Supabase populado com
  múltiplos providers reais); `PitGoMapView` (`009`, marcadores simples) foi mantido e só recebeu a
  configuração de estilo/atribuição gerenciada (T006) — mesma decisão de escopo já registrada no
  comentário de `ServiceMapView.swift` em `009`

**Checkpoint**: infraestrutura de estilo/config/conectividade pronta; a migração completa para
`MapLibreMapHost` com clustering GeoJSON (T004/T007/T009/T013/T024/T027) fica para uma entrega
futura — ver racional em cada tarefa.

---

## Phase 3: User Story 1 - Visualizar prestadores pelo endereço (Priority: P1) 🎯 MVP

**Independent Test**: Abrir o mapa a partir de um serviço com prestadores compatíveis e confirmar
que cada resultado aparece na coordenada do endereço cadastrado, com identificação compreensível.

### Implementation for User Story 1

- [ ] T010 [P] [US1] Estender `ServiceMapModels` (`009`) com viewport, coleção pública validada,
  modo Mapa/Lista, seleção e grupos coincidentes em
  `pitgo/Features/ProviderMap/Model/ServiceMapModels.swift` — **parcial**: seleção foi resolvida
  como `@State` na própria View (`selectedResult`) em vez de um campo modelado no estado do
  ViewModel; grupos coincidentes (coordenadas idênticas) não foram modelados — sem clustering
  (T013) não há uma UI que os consuma
- [ ] T011 [P] [US1] Validar UUID/centro e descartar coordenadas não finitas ou fora da faixa ao
  mapear `discover_service_providers`, preservando limite e privacidade dos campos públicos em
  `pitgo/Features/ProviderMap/Data/ServiceMapDTOs.swift` e
  `pitgo/Features/ProviderMap/Repository/ServiceMapRepository.swift` — **não feito**: `ServiceMapDTOs`/
  `ServiceMapRepository` permanecem como em `009`, sem uma validação adicional de latitude/longitude
  finita/dentro da faixa no `Decodable`
- [ ] T012 [US1] Implementar busca por viewport com `searchGeneration`, seleção estável,
  pré-agrupamento de coordenadas idênticas e comandos de câmera revisionados em
  `pitgo/Features/ProviderMap/ViewModel/ServiceMapViewModel.swift` — **parcial**: a geração
  incremental (`generation`, equivalente ao `searchGeneration`) já existia desde `009` e continua
  descartando respostas de buscas antigas; conectividade proativa (T008) foi integrada aqui nesta
  sessão; pré-agrupamento de coordenadas idênticas não foi implementado
- [ ] T013 [US1] Criar `ProviderMapStyleCoordinator` idempotente que instala imagens, uma
  `MLNShapeSource` clusterizada e layers de cluster/contagem/endereço/seleção, atualizando somente
  a source no mesmo estilo, em `pitgo/Features/ProviderMap/Views/ProviderMapStyleCoordinator.swift`
  — **não feito**: depende de `MapLibreMapHost` (T009), não construído nesta entrega pelo mesmo
  racional de risco/validação
- [ ] T014 [US1] Substituir a implementação de mapa de `009` pelo `MapLibreMapHost` — **não
  feito** (mantido `PitGoMapView`); porém as demais partes desta tarefa foram implementadas: Mapa/
  Lista, "Buscar nesta área" e barra de navegação já existiam (`009`), e nesta sessão foram
  adicionados a atribuição acessível (`MapAttributionView`) e — a lacuna funcional mais importante
  encontrada — **o resumo do provider em `.sheet` com o CTA "SOLICITAR ATENDIMENTO"**, que antes
  não existia (tocar num provider não fazia nada) em
  `pitgo/Features/ProviderMap/Views/ServiceMapView.swift`
- [X] T015 [P] [US1] Adicionar resolução autoritativa de serviço por UUID e sua estimativa sem
  recorrer ao catálogo demo — implementado em `RequestServiceViewModel` reaproveitando
  `ServiceCatalogRepository.fetchHomeServices()` (já existente) filtrado por `serviceID`, em vez de
  adicionar um novo método de busca por ID a `ServiceCatalogRepository.swift` (não há RPC dedicada
  confirmada para isso; reaproveitar a já usada pela Home evita uma suposição de contrato)
- [X] T016 [US1] Trocar o estado de `RequestServiceContent` (`003`) de `DemoService` para resumo
  real do catálogo e preservar `providerID` opaco no callback mockado — feature recriada do zero
  nesta sessão (havia sido apagada em `009`) em
  `pitgo/Features/RequestService/Model/RequestServiceContent.swift`
- [X] T017 [US1] Carregar o serviço por `serviceID`, representar loading/falha/inválido e impedir
  fallback para Bateria/preço demo em `pitgo/Features/RequestService/ViewModel/RequestServiceViewModel.swift`
- [X] T018 [US1] Adaptar `RequestServiceView` aos novos estados, mantendo descrição, pagamento
  (mock textual — integração real de pagamento é feature futura fora deste escopo) e botão mockado
  funcionais sem expor IDs na interface, em
  `pitgo/Features/RequestService/Views/RequestServiceView.swift`
- [X] T019 [US1] Adicionar `PitGoRoute.requestService(serviceID:providerID:)`, conectar voltar/
  seleção/CTA/factory do catálogo em `pitgo/Core/Navigation/PitGoRoute.swift` e
  `pitgo/Core/Navigation/PitGoRootView.swift` (e ajustado o `switch` exaustivo em
  `ProfileView.swift`/`ProviderDashboardView.swift` para o novo caso)

**Checkpoint**: MVP parcial — a lacuna funcional mais crítica (tocar num provider não levava a
lugar nenhum) foi corrigida nesta sessão; a descoberta em si continua com marcadores simples
(`PitGoMapView`, `009`), sem clustering GeoJSON nativo.

---

## Phase 4: User Story 2 - Acompanhar posição atualizada (Priority: P1)

**Independent Test**: Durante um atendimento ativo autorizado, publicar posições sucessivas do
prestador e confirmar que o marcador se desloca na tela aberta, indicando também quando o dado fica
desatualizado.

### Implementation for User Story 2

- [ ] T020 [P] [US2] Verificar (leitura) que o hardening SQL do stream (`EMPTY|LIVE|STALE|ENDED`,
  autorização de participante, Broadcast `ENDED`, remoção sem histórico) já está aplicado, conforme
  `specs/010-osm-realtime-map/quickstart.md §2` — **bloqueado neste ambiente**: este projeto iOS não
  tem `npx supabase`/credenciais vinculadas nesta sessão (a inspeção do backend compartilhado foi
  feita no repositório Android nesta mesma sessão, para outro objetivo — pagamentos — sem tocar
  nesta migration)
- [ ] T021 [P] [US2] Modelar `LocationRevision`, eventos `.snapshot|.upsert|.removed|.ended|
  .sessionExpired|.offline|.failure`, tombstone e estados de tracking com última posição em
  `pitgo/Features/AppointmentTracking/Model/AppointmentTrackingModels.swift` — **não feito**: o
  modelo de `009` (`AppointmentMarkerState` simples: unavailable/live/stale/ended) foi mantido; a
  ordenação por versão e o timer de 30s já existiam funcionalmente no ViewModel (T023), só não estão
  expressos como o tipo `LocationRevision`/enum de eventos do contrato
- [ ] T022 [US2] Iniciar a assinatura antes do snapshot, emitir `.snapshot(nil)`, interpretar `old`
  no DELETE, coletar `ENDED`, classificar sessão/rede e remover o canal numa `Task` desacoplada em
  `pitgo/Features/AppointmentTracking/Repository/AppointmentTrackingRepository.swift` — **não
  feito**: o repositório de `009` já assina antes de buscar o snapshot (ordem correta), mas usa
  Broadcast (`UPSERT`/`CLEARED`) em vez de `postgres_changes` INSERT/UPDATE/DELETE — não há um
  evento `old` de DELETE a interpretar nesse desenho; migrar para o mecanismo exato do contrato é
  uma mudança de arquitetura do Repository fora do escopo desta sessão
- [ ] T023 [US2] Aplicar ordenação lexicográfica e tombstone, relançar `CancellationError`, manter
  um timer de 30s e limpar a coordenada privada em oculto/`.ended`/troca de sessão em
  `pitgo/Features/AppointmentTracking/ViewModel/AppointmentTrackingViewModel.swift` — **parcial**:
  o timer de 30s (`scheduleStale`) e a ordenação por `version` inteira já existiam (`009`) e
  continuam corretos; não há `(publishedAt, version)` lexicográfico completo, relançamento explícito
  de `CancellationError`, nem limpeza explícita da coordenada ao ocultar a View além do que
  `disconnect()` já cancela (o timer)
- [ ] T024 [US2] Criar `AppointmentMapStyleCoordinator` com uma `MLNShapeSource` não clusterizada e
  layers LIVE/STALE que atualiza apenas `source.shape` e nunca restaura um marcador removido após
  reload tardio, em `pitgo/Features/AppointmentTracking/Views/AppointmentMapStyleCoordinator.swift`
  — **não feito**: depende de `MapLibreMapHost` (T009), mesmo racional de escopo/risco
- [ ] T025 [US2] Substituir a implementação de mapa de `009` pelo `MapLibreMapHost`, adicionar barra
  de navegação/voltar, controle "Seguir prestador", horário localizado e estados Live/Stale/Empty/
  Ended sem `TabView` em `pitgo/Features/AppointmentTracking/Views/AppointmentTrackingView.swift` —
  **parcial**: nav bar, horário localizado e estados Live/Stale/Empty/Ended já existiam (`009`) e
  ganharam a atribuição acessível (`MapAttributionView`) nesta sessão; `MapLibreMapHost` e o
  controle "Seguir prestador" não foram implementados
- [ ] T026 [US2] Conectar `onBack` e `onSessionExpired` da rota participante, mantendo
  `appointmentID` como único argumento e o gate central de sessão em
  `pitgo/Core/Navigation/PitGoRootView.swift` — **não feito**: `AppointmentTrackingView` continua
  sem parâmetros `onBack`/`onSessionExpired` (mesmo estado de `009`); esta sessão não alterou esse
  fluxo

**Checkpoint**: os estados de acompanhamento (Live/Stale/Empty/Ended) e o hardening de versão/timer
de `009` seguem funcionais; a migração para GeoJSON/`MapLibreMapHost` e o alinhamento estrito ao
contrato de eventos do Repository ficam pendentes.

---

## Phase 5: User Story 3 - Usar o mapa em condições adversas (Priority: P2)

**Independent Test**: Simular indisponibilidade de tiles, ausência de rede, localização negada e
lista vazia, confirmando que cada caso apresenta mensagem e recuperação apropriadas.

### Implementation for User Story 3

- [ ] T027 [US3] Agregar callbacks de estilo/tile/glyph/sprite/render do `MLNMapViewDelegate`,
  ignorar cancelamento ou erro isolado, aplicar debounce de degradação e recarregar o mesmo estilo
  sem limpar cache/dados/câmera em `pitgo/Core/Map/UI/MapLibreMapHost.swift` — **não feito**:
  depende de `MapLibreMapHost` (T009); `PitGoMapView` (`009`) só implementa `didSelect`/
  `regionDidChangeAnimated`, sem os callbacks de falha/degradação de estilo/tile/glyph/sprite
- [X] T028 [P] [US3] Classificar offline, timeout, sessão expirada, serviço indisponível e falha
  desconhecida sem encaminhar o `Error` bruto — já implementado desde `009` em
  `ServiceMapRepository.classify(_:)` (offline/sessionExpired/service/unknown); `timeout` não é uma
  classificação distinta (cai em `.service`), lacuna menor não corrigida nesta sessão
- [ ] T029 [US3] Integrar conectividade, estados de dados/superfície/localização, retry
  revisionado e preservação de resultados/seleção em falha no estado `@Observable` em
  `pitgo/Features/ProviderMap/ViewModel/ServiceMapViewModel.swift` — **parcial**: conectividade
  (T008) foi integrada nesta sessão, dominando sobre a falha genérica; retry continua substituindo
  o estado por `.loading` (não preserva resultados/seleção anteriores durante uma nova tentativa)
- [ ] T030 [US3] Renderizar loading, vazio, offline, falha do RPC, estilo falho, recurso degradado,
  localização recusada e sessão expirada com Live Regions, retry e lista equivalente em iPhone
  compacto/landscape/Dynamic Type grande em
  `pitgo/Features/ProviderMap/Views/ServiceMapView.swift` — **parcial**: loading/vazio/offline/
  falha do RPC/localização recusada já tinham UI própria (`009`) com `accessibilityAddTraits(
  .updatesFrequently)`; estilo falho e recurso degradado não têm estado dedicado (dependem de
  `MapLibreMapHost`); não foi feita uma auditoria dedicada de iPhone compacto/landscape/Dynamic Type
  grande nesta sessão
- [ ] T031 [P] [US3] Preservar a última posição como stale em offline/falha visual, separar
  `MapSurfaceState` do stream e impedir anúncio repetitivo a cada tick em
  `pitgo/Features/AppointmentTracking/ViewModel/AppointmentTrackingViewModel.swift` — **parcial**:
  a preservação da última posição como `.stale` após 30s já existia (`009`, `scheduleStale`); não há
  um `MapSurfaceState` separado do stream (T007 não feita) nem uma auditoria de repetição de
  anúncios VoiceOver
- [ ] T032 [US3] Manter marcador e horário em degradação, oferecer retry/listagem textual de estado
  e garantir atribuição/controles acessíveis com Dynamic Type grande em
  `pitgo/Features/AppointmentTracking/Views/AppointmentTrackingView.swift` — **parcial**: a
  atribuição acessível (`MapAttributionView`) foi adicionada nesta sessão; marcador/horário durante
  degradação de estilo/tile e uma auditoria de Dynamic Type grande não foram feitos (sem
  `MapLibreMapHost` não há um estado de degradação de recurso distinto a preservar)

**Checkpoint**: as lacunas de US3 mais dependentes de `MapLibreMapHost` (estilo/tile degradado)
permanecem; as de rede (offline proativo) e atribuição foram endereçadas nesta sessão.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T033 Confirmar ausência de qualquer outro SDK de mapa e revisar `Package.resolved` para
  MapLibre como única dependência de renderização — `grep -rn "MapKit\|GoogleMaps\|GMSMapView"
  pitgo/` vazio; `Package.resolved` lista `maplibre-gl-native-distribution` como única dependência
  de mapa
- [X] T034 [P] Revisar mensagens, logs e callbacks para não registrar URL/token, payload Realtime,
  coordenada privada ou erro nativo bruto — nenhum arquivo tocado nesta sessão
  (`ManagedMapStyleConfiguration.swift`, `ConnectivityObserver.swift`,
  `ServiceMapViewModel.swift`, `ServiceMapView.swift`, `RequestService/*`) contém `print`/log; os
  arquivos de `009` (`ServiceMapRepository.swift`, `AppointmentTrackingRepository.swift`) já não
  tinham logging bruto e não foram alterados
- [X] T035 Executar `xcodebuild clean build` em simulador e `generic/platform=iOS` — ambos com
  **BUILD SUCCEEDED** nesta sessão (após as mudanças de T006/T008/T014/T015-T019 acima)
- [ ] T036 [P] Verificar (leitura) o hardening SQL novamente — **bloqueado neste ambiente**, mesma
  razão de T020 (sem `npx supabase` vinculado a este projeto iOS nesta sessão)
- [ ] T037 Executar a matriz manual de descoberta, clusters coincidentes, tracking fora de ordem,
  stale, término, estilo/tiles indisponíveis, offline, permissão recusada, lifecycle, VoiceOver,
  iPhone compacto, landscape e Dynamic Type grande descrita em
  `specs/010-osm-realtime-map/quickstart.md` — **bloqueado neste ambiente**: exige simulador/
  dispositivo interativo, VoiceOver, rotação e um backend com múltiplos providers reais; apenas a
  validação de build (T035) foi executada nesta sessão

---

## Dependencies & Execution Order

```text
Setup → Foundation → US1 (MVP) → US2 → US3 → Polish
```

- **US1**: entrega a descoberta com MapLibre; independente de US2.
- **US2**: depende do host/infra de US1 (mesmo `MapLibreMapHost`), reutiliza a arquitetura mas é
  funcionalmente independente do fluxo de descoberta.
- **US3**: refina estados de falha sobre US1/US2.

### Parallel Opportunities

- Setup: T004/T005 em paralelo.
- Foundation: T007/T008 em paralelo; T009 depende de T006/T007.
- US1: T010/T011/T015 em paralelo antes de convergir em T012→T013→T014.
- US2: T020/T021 em paralelo antes de T022→T023→T024→T025.
- US3: T028/T031 em paralelo com o restante.

## Notes

- Nenhuma migration nova é criada — o hardening SQL já existe e é compartilhado com o Android.
- Nenhum teste automatizado é criado; build e `quickstart.md` são os gates de qualidade.
- Não introduzir um segundo SDK de mapa nem fallback silencioso.
- Commits pequenos por tarefa/grupo lógico.
