# Phase 1 Data Model: Mapa do PitTec sempre centralizado na localização do cliente

Nenhuma entidade de domínio, tabela, RPC ou DTO é criada, removida ou alterada em formato por esta
feature. A mudança de "dado" é apenas de **visibilidade** de um valor que já existe em memória na
ViewModel.

## Localização do Cliente (existente — `DeviceLocationFix`)

Já definida em `Core/Location/Model/DeviceLocationModels.swift`, sem alteração de forma:

| Campo | Tipo | Descrição |
|---|---|---|
| `latitude` | `Double` | Latitude do fix one-shot obtido para a descoberta do PitTec |
| `longitude` | `Double` | Longitude do fix one-shot |
| `horizontalAccuracy` | `Double` | Não usado por esta feature (mantido para outros consumidores) |
| `timestamp` | `Date` | Não usado por esta feature |

**Mudança de acesso**: `PitTecClientViewModel.lastFix` passa de `private var` para
`private(set) var`, no mesmo padrão já usado por `routeContext` na mesma ViewModel — continua
gravável só internamente, agora legível pela View para montar `centerCoordinate`.

**Ciclo de vida**: preenchido em `loadDiscovery()` após um fix bem-sucedido; permanece em memória
durante toda a sessão da tela (reaproveitado por `callPitTec`), incluindo depois da transição para
`.content`/`.terminal` — não é limpo até a View desaparecer (`onDisappear { viewModel.stop() }`,
que não zera `lastFix`, apenas desconecta assinaturas realtime).

## Marcador de PitTec (existente — `PitTecMarker`)

Sem alteração de forma (`markerID`, `latitude`, `longitude`, `accuracyRadiusMeters`, já
anonimizado/aproximado — ver `PitTecModels.swift`). Continua podendo ser uma lista vazia; a lista
vazia deixa de significar "sem mapa" e passa a significar apenas "mapa sem marcador de prestador".

## Estados de UI afetados (existente — `PitTecClientUiState`)

Nenhum caso do `enum` muda de forma. Apenas a interpretação visual de dois casos muda:

| Caso | Antes | Depois |
|---|---|---|
| `.discovering([])` | Tela só-texto (`emptyDiscoveryState`), sem mapa | `PitGoMapView` centralizado no cliente (`viewModel.lastFix`), sem marcador de prestador, mensagem sobreposta |
| `.discovering([marcadores])` | Mapa sem `centerCoordinate`/`showsUserLocation` | Mesmo mapa, agora com `centerCoordinate`/`showsUserLocation: true` |
| `.terminal(snapshot)` com `status == .exhausted` | Tela só-texto (`terminalState`) | `PitGoMapView` centralizado no cliente, mensagem/ações terminais sobrepostas |
| `.terminal(snapshot)` com `status == .completed`/`.cancelled` | Tela só-texto | Inalterado (fora de escopo) |

Nenhuma outra entidade (`PitTecDispatchSnapshot`, `PitTecAppointment`, `PitTecOffer`,
`PitTecProviderIdentity`) é lida ou alterada por esta feature.
