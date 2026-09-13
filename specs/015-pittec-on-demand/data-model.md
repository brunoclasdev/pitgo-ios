# Data Model: PitTec sob demanda (iOS)

Todas as tabelas, colunas, constraints e RPCs abaixo já existem e estão aplicadas no backend
compartilhado com o Android (ver [research.md §0](research.md)). Este documento traduz o contrato
para tipos Swift consumidos pelo client iOS — nenhum schema é criado ou alterado aqui.

## Relationship overview (backend compartilhado, inalterado)

```text
auth.users
  ├── providers ── provider_services ── services ── service_categories
  │       └── provider_discovery_locations
  └── service_searches ── dispatch_candidates
               └── appointments
                      ├── provider_current_locations
                      ├── client_current_locations
                      └── appointment_route_snapshots
```

## Extensões de entidades existentes (backend compartilhado, inalterado)

- **`services.dispatch_kind`**: `enum ServiceDispatchKind` (`009`/`013`) ganha o caso
  `.pittecAutoSequential`, preservando `.browse` e `.mobileSequential`.
- **`providers.location_mode`**: `enum ProviderLocationMode` (`009`) ganha o caso `.pittec`; novo
  campo opcional `pendingLocationMode: ProviderLocationMode?` (aplicado atomicamente pelo backend na
  transição terminal, nenhuma ação do client além de exibir a pendência).
- **`appointments`**: ganha `arrivedAt: Date?` (definido uma vez pela RPC "Cheguei") e
  `offerExpiresAt: Date?` (exatamente 60s após a oferta).

## Nova entidade consumida: `AppointmentRouteSnapshot`

```swift
struct AppointmentRouteSnapshot: Decodable {
    let appointmentID: UUID
    let providerLocationRevision: Int64
    let geometry: GeoJSONLineString   // [[lon, lat], ...]
    let distanceMeters: Int
    let generatedAt: Date
    let providerName: String   // identificador do provedor de roteamento, não segredo
}

struct GeoJSONLineString: Decodable {
    let type: String   // "LineString"
    let coordinates: [[Double]]   // [longitude, latitude]
}
```

Uma linha por atendimento, sobrescrita quando o provider se move ao menos 50m e o snapshot anterior
tem ao menos 15s (regra aplicada pela Edge Function, inalterada). Removida em transição terminal.

## Projeções derivadas (não persistidas)

### `NearbyPitTecMarker`

```swift
struct NearbyPitTecMarker: Decodable, Identifiable {
    let id: String            // marker_id opaco, por resposta/janela de tempo
    let latitude: Double      // aproximado pelo servidor (grade ~500m)
    let longitude: Double
    let accuracyRadiusMeters: Int
}
```

Nenhuma identidade de provider, ponto exato, preço ou contato direto é exposta.

### `PitTecDispatchSnapshot`

```swift
struct PitTecDispatchSnapshot: Decodable {
    let searchID: UUID
    let appointmentID: UUID?
    let dispatchKind: ServiceDispatchKind   // sempre .pittecAutoSequential aqui
    let status: PitTecDispatchStatus
    let revision: Int64
    let offerExpiresAt: Date?               // somente enquanto oferecido a este provider
    let availableActions: Set<PitTecAction> // .cancel, .accept, .reject, .arrive, .complete
    let approximateDistance: String?        // só para o provider ofertado; banda genérica ou cidade/UF salva
    let participant: PitTecParticipantInfo? // só a partir de ACCEPTED
}

enum PitTecDispatchStatus: String, Decodable {
    case searching = "SEARCHING", awaitingProvider = "AWAITING_PROVIDER"
    case accepted = "ACCEPTED", inProgress = "IN_PROGRESS"
    case completed = "COMPLETED", cancelled = "CANCELLED"
    case expired = "EXPIRED", noProvider = "NO_PROVIDER"
}

enum PitTecAction: String, Decodable { case cancel, accept, reject, arrive, complete }
```

Nenhuma coordenada exata aparece no snapshot em si — coordenadas seguem exclusivamente o contrato
de localização por participante (`009`/`013`/`014`).

### `RouteSnapshot` (estado de UI, combina backend + fallback local)

```swift
enum RouteState {
    case route(distanceMeters: Int, coordinates: [CLLocationCoordinate2D], revision: Int64, generatedAt: Date)
    case estimatedDirect(distanceMeters: Int, coordinates: [CLLocationCoordinate2D])   // calculado localmente (haversine)
    case unavailable
}
```

`.estimatedDirect` é calculado em memória pelo app iOS (haversine) e nunca persistido — mesmo
racional do `ESTIMATED_DIRECT` do Android.

## Authorization matrix (backend compartilhado, inalterado)

| Resource/action | Cliente solicitante | Provider designado | Outra conta autenticada |
|---|---:|---:|---:|
| descoberta aproximada PitTec | sim | não | não |
| ponto exato da solicitação antes do aceite | sem leitura direta | não | não |
| responder oferta pendente | não | sim | não |
| posições exatas dos participantes após aceite | sim | sim | não |
| gerar/ler rota | sim | sim | não |
| marcar chegada/conclusão | não | sim | não |
| cancelar atendimento aceito com motivo | sim | sim | não |

## Estados de UI iOS

### `PitTecClientUiState`

```swift
enum PitTecClientUiState {
    case locationRequired(reason: LocationRequiredReason)
    case discovery(markers: [NearbyPitTecMarker], loadState: DiscoveryLoadState)
    case searching(PitTecDispatchSnapshot)
    case awaitingProvider(PitTecDispatchSnapshot)
    case accepted(PitTecDispatchSnapshot, route: RouteState)
    case inProgress(PitTecDispatchSnapshot, route: RouteState)
    case terminal(PitTecDispatchSnapshot)
    case sessionExpired
}
```

### `PitTecProviderUiState`

```swift
enum PitTecProviderUiState {
    case unavailable
    case available
    case incoming(PitTecDispatchSnapshot, remainingDisplay: String)
    case reserved(PitTecDispatchSnapshot, route: RouteState)   // ACCEPTED ou IN_PROGRESS
    case sessionExpired
}
```

Ambas seguem o mesmo padrão de `PendingDispatchAction` (`013`) para bloquear toques duplicados
durante uma mutation em andamento.
