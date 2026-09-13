# Data Model: Busca e despacho de prestadores móveis (iOS)

O PostgreSQL/Supabase é a fonte autoritativa do fluxo (backend compartilhado, inalterado — ver
[research.md §0](research.md)). O client iOS mantém apenas snapshots imutáveis, revisões e estado
transitório de interação. Coordenadas são correntes e substituídas; nenhuma entidade desta feature
representa uma trilha.

## 1. Extensão de catálogo (backend compartilhado, inalterado)

```swift
enum ServiceDispatchKind: String, Decodable { case browse = "BROWSE", mobileSequential = "MOBILE_SEQUENTIAL" }
```

`services.dispatch_kind` já vem decodificado no DTO de `ServiceCatalogRepository` (`009`). O iOS
nunca decide pelo texto do nome do serviço — somente por este campo e pelo UUID.

## 2. Posição corrente de discovery (backend compartilhado, inalterado)

`provider_discovery_locations` — mesma tabela/regras do Android: uma linha por provider,
`geography(Point,4326)`, `accuracy_m <= 100`, janela de captura, `version` crescente,
`tracker_instance_id`/`tracker_sequence`. Elegibilidade efetiva (`active` + `available` +
`location_mode = MOBILE` + oferta ativa + posição recente + ausência de appointment ativo) é
inteiramente derivada no servidor.

## 3. Busca persistente (backend compartilhado, inalterado)

`service_searches` com `status` (`ServiceSearchStatus`), `current_radius_m`
(10000/25000/50000), `current_candidate_id`, `current_appointment_id`, `revision`. Índice parcial
único garante uma busca ativa por `(client, service)`.

```swift
enum ServiceSearchStatus: String, Decodable {
    case searching = "SEARCHING", optionFound = "OPTION_FOUND"
    case awaitingProvider = "AWAITING_PROVIDER", accepted = "ACCEPTED"
    case inProgress = "IN_PROGRESS", cancelled = "CANCELLED"
    case completed = "COMPLETED", exhausted = "EXHAUSTED"
}
```

## 4. Candidato/proposta (backend compartilhado, inalterado)

`private.dispatch_candidates` — nunca acessado diretamente pelo client; apenas via snapshot RPC.

```swift
enum CandidateOutcome: String, Decodable {
    case presented = "PRESENTED", clientDismissed = "CLIENT_DISMISSED"
    case requested = "REQUESTED", providerRejected = "PROVIDER_REJECTED"
    case proposalExpired = "PROPOSAL_EXPIRED", invalidated = "INVALIDATED"
    case accepted = "ACCEPTED", providerCancelled = "PROVIDER_CANCELLED"
}
```

## 5. Solicitação/appointment estendido (backend compartilhado, inalterado)

`appointments` ganha (já aplicado) `dispatch_search_id`, `dispatch_candidate_id`, `service_id`,
`provider_service_id`, `price_snapshot`, `is_free_snapshot`, `response_deadline`, `revision`,
`cancelled_by`, `cancellation_reason`, `cancelled_at`.

```swift
enum AppointmentStatus: String, Decodable {
    case pending = "PENDING", accepted = "ACCEPTED", inProgress = "IN_PROGRESS"
    case providerRejected = "PROVIDER_REJECTED", expired = "EXPIRED"
    case completed = "COMPLETED", cancelled = "CANCELLED"
}

enum CancelledBy: String, Decodable { case client = "CLIENT", provider = "PROVIDER" }
```

## 6. Transições autoritativas (backend compartilhado, inalterado)

```text
SEARCHING → OPTION_FOUND (candidato elegível) | EXHAUSTED (esgotou 10/25/50 km)
OPTION_FOUND → SEARCHING (Próximo → CLIENT_DISMISSED, ou candidato INVALIDATED) | AWAITING_PROVIDER (Solicitar → PENDING)
AWAITING_PROVIDER → ACCEPTED (aceite) | SEARCHING (recusa → PROVIDER_REJECTED, ou deadline → EXPIRED)
ACCEPTED → IN_PROGRESS (iniciar) | CANCELLED terminal (cliente) | SEARCHING (provider cancela → PROVIDER_CANCELLED)
IN_PROGRESS → COMPLETED terminal | CANCELLED terminal (cliente) | SEARCHING (provider cancela → PROVIDER_CANCELLED)
```

Cada mutation compara `expectedRevision`; replay retorna o snapshot atual; comando stale retorna
`.staleRevision` sem alterar dados — tudo já implementado no servidor.

## 7. Snapshot de domínio iOS

```swift
struct MobileDispatchSnapshot: Decodable {
    let serverNow: Date
    let searchID: UUID
    let serviceID: UUID
    let serviceName: String
    let status: ServiceSearchStatus
    let revision: Int64
    let radiusMeters: Int
    let candidate: CandidateProposal?
    let appointment: DispatchAppointment?
    let allowedActions: Set<DispatchAction>   // .next, .request, .cancel, .accept, .reject, ...
    let notice: DispatchNotice?   // recusa/expiração/skip anterior, sem dados privados
}

struct CandidateProposal: Decodable {
    let candidateID: UUID
    let providerName: String
    let locality: String            // cidade/UF pública aproximada
    let coordinate: MapCoordinate?  // posição corrente autorizada; nil se inválida/stale
    let distanceMeters: Double
    let displayedPrice: Decimal
    let isFree: Bool
    let mode: ProviderLocationMode  // sempre .mobile
}

struct DispatchAppointment: Decodable {
    let appointmentID: UUID
    let status: AppointmentStatus
    let priceSnapshot: Decimal      // preço congelado
    let isFreeSnapshot: Bool
    let responseDeadline: Date?
    let revision: Int64
    let cancellation: DispatchCancellation?   // sanitizado: autor + motivo, sem detalhe técnico
}
```

Coordenada inválida/stale invalida a proposta (`coordinate == nil`); o countdown deriva de
`responseDeadline` + a diferença entre `serverNow` e o relógio local do dispositivo — zero dispara
um novo pedido de snapshot, nunca uma transição local inventada.

### Estados de tela do cliente

```swift
enum ClientMobileDispatchUiState {
    case restoring
    case locationRequired(reason: LocationRequiredReason)
    case content(MobileDispatchSnapshot, pendingAction: PendingDispatchAction?, connectionState: ConnectivityState, mapSurfaceState: MapSurfaceState)
    case empty(MobileDispatchSnapshot)
    case terminal(MobileDispatchSnapshot)
    case sessionExpired
}
```

### Estados do provider

```swift
enum ProviderDispatchUiState {
    case noIncoming
    case incoming(MobileDispatchSnapshot, remainingDisplay: String, pendingAction: PendingDispatchAction?)
    case reserved(MobileDispatchSnapshot)
    case sessionExpired
    case failure(lastConfirmed: MobileDispatchSnapshot?)
}
```

`PendingDispatchAction` contém o tipo de ação, o candidato/appointment/revisão esperada e bloqueia
toques duplicados (guarda síncrona antes de criar a `Task`). Uma falha recuperável preserva o
último snapshot confirmado.

## 8. Publicação processual iOS

```swift
enum ProviderTrackingState {
    case stopped(reason: TrackingStopReason?)
    case starting
    case publishing(lastPublishedAt: Date)
    case degraded(reason: TrackingDegradedReason, lastPublishedAt: Date?)
    case stopping
}

enum ProviderTrackingTarget {
    case discovery
    case appointment(appointmentID: UUID)
}
```

O backend, não um parâmetro do client, decide o appointment vigente do provider. `target` serve
apenas para a UI local; ownership continua derivada da sessão. Uma preferência técnica leve
(`UserDefaults`) pode reter apenas `accountID`, `trackerInstanceID` e sequência para retomada do
mesmo processo/conta — nunca coordenada, busca, proposta, appointment ou token. Troca de conta/
logout limpa essa preferência.

## 9. Relações (backend compartilhado, inalterado)

```text
Service 1 ── dispatchKind
Provider 1 ── 0..1 ProviderDiscoveryLocation
Client 1 ── 0..N ServiceSearch (máx. 1 ativa por Service)
ServiceSearch 1 ── N DispatchCandidate
DispatchCandidate 1 ── 0..1 Appointment
Provider 1 ── máx. 1 Appointment PENDING|ACCEPTED|IN_PROGRESS
Appointment 1 ── 0..1 ProviderCurrentLocation (tracking privado, 009)
```

Todas as tabelas novas têm RLS habilitada e nenhum DML direto para o bundle iOS — mesma proteção do
Android, aplicada uma única vez no backend compartilhado.
