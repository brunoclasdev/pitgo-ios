# Data Model: Experiência mockada de UI do PitTec (iOS)

## Overview

Todos os tipos abaixo são `struct`/`enum` Swift imutáveis mantidos somente em memória. Não há DTO,
tabela, migration, arquivo, cache ou mapeamento de rede. Cliente e prestador possuem instâncias
independentes; nomes iguais nas fixtures não representam pessoas sincronizadas.

## Value objects

### `MockParticipant`

```swift
struct MockParticipant {
    let id: String            // estável e não vazio dentro da fixture
    let displayName: String
    let role: MockParticipantRole   // .client, .pittec
}
```

### `DistancePerimeter`

```swift
struct DistancePerimeter {
    let kilometers: Int   // positivo e múltiplo de 5
    var bandCount: Int { kilometers / 5 }
    var nextBand: DistancePerimeter { DistancePerimeter(kilometers: kilometers + 5) }
}
```

### `ServiceEstimate`

```swift
struct ServiceEstimate {
    let perimeter: DistancePerimeter
    let fixedCents: Int = 5000
    let bandUnitCents: Int = 1000
    var bandCount: Int { perimeter.kilometers / 5 }
    var distanceAdditionalCents: Int { bandUnitCents * bandCount }
    var totalCents: Int { fixedCents + distanceAdditionalCents }
}
```

Invariantes: todos os valores são não negativos e calculados, nunca recebidos como texto;
formatação em reais/duas casas ocorre somente na UI com `Locale(identifier: "pt_BR")`; 5km =
6.000 centavos; 10km = 7.000; 15km = 8.000.

### `MockLocationSnapshot`

```swift
struct MockLocationSnapshot {
    let coordinate: MapCoordinate
    let capturedAt: Date                    // horário legível
    let capturedAtMonotonic: Duration        // ContinuousClock.Instant, para idade/stale
    let source: MockLocationSource           // .device (Home provider), .fixture, .simulatedStep
    let revision: Int64
}
```

Derivado: `isStale = (continuousClock.now - capturedAtMonotonic) > .seconds(35)`.

## Fixture entities

### `MockPitTecCandidate`

```swift
struct MockPitTecCandidate {
    let participant: MockParticipant   // role sempre .pittec
    let perimeter: DistancePerimeter
    let initialCoordinate: MapCoordinate
    let response: MockCandidateResponse   // .accept, .decline
    let responseDelay: Duration            // positivo, finito, determinístico
}
```

### `PitTecMockScenario`

```swift
struct PitTecMockScenario {
    let id: String
    let client: MockParticipant            // role .client
    let clientCoordinate: MapCoordinate
    let candidates: [MockPitTecCandidate]  // ordenados por faixa/tentativa; IDs únicos
    let movementPath: [MapCoordinate]      // ao menos 2 pontos quando houver aceite
}
```

Fixtures mínimas: `.progressiveSuccess` (recusado em 5km, recusado em 10km, aceito em 15km — R$60/
70/80 e expansão automática); `.noProvider` (todos recusam, lista termina — vazio e retry);
`.providerIncoming` (uma solicitação em 10km, só para o fluxo independente do provider — total
R$70,00). Coordenadas são deslocamentos determinísticos ao redor da âncora do mapa (posição atual
já exibida para a fixture cliente; fix real inicial como origem para a fixture provider).

## Runtime entities

### `MockSearch`

```swift
struct MockSearch {
    let id: String
    let scenarioID: String
    var currentPerimeter: DistancePerimeter   // nunca diminui
    var candidateIndex: Int
    var rejectedCandidateIDs: Set<String>     // candidato rejeitado nunca retorna
    var estimate: ServiceEstimate             // recalculada ao mudar de faixa
    var feedback: MockSearchFeedback          // .searching, .awaitingResponse, .declinedContinuing, .found, .notFound
    var revision: Int64                       // cresce em cada transição aceita
    var confirmed: Bool                       // true uma única vez antes da busca
}
```

Invariantes: só existe uma busca ativa por ViewModel; `confirmed == true` antes de qualquer consulta
simulada; um candidato em `rejectedCandidateIDs` não pode ser candidato atual; a faixa só aumenta
quando não existe outro candidato não tentado na faixa atual; `.notFound`/`.found` são terminais.

### `MockServiceRequest`

```swift
struct MockServiceRequest {
    let id: String
    let client: MockParticipant
    let clientCoordinate: MapCoordinate
    let estimate: ServiceEstimate
    let approximateDistanceMeters: Int
    let createdAt: Date
    var revision: Int64                // chave idempotente do alerta/resposta
    var pulseConsumed: Bool            // impede replay por recriação de View/navegação
}
```

Uma solicitação admite exatamente uma resposta local: `.accept` ou `.decline`.

### `ParticipantConfirmation`

```swift
struct ParticipantConfirmation {
    let kind: MockConfirmationKind        // .meeting, .completion
    var localConfirmedAt: Date?           // preenchido uma vez pela ação do perfil atual
    var counterpartConfirmedAt: Date?     // preenchido uma vez, 3s depois, pela simulação
    var revision: Int64                   // impede aplicação de Task obsoleta
    var waitingForCounterpart: Bool { localConfirmedAt != nil && counterpartConfirmedAt == nil }
    var isComplete: Bool { localConfirmedAt != nil && counterpartConfirmedAt != nil }
}
```

### `MockAppointment`

```swift
struct MockAppointment {
    let id: String
    let client: MockParticipant
    let provider: MockParticipant
    let estimate: ServiceEstimate                 // congelada na faixa do candidato aceito
    var clientLocation: MockLocationSnapshot
    var providerLocation: MockLocationSnapshot
    var movementPath: [MapCoordinate]
    var nextStepIndex: Int
    var remainingDistanceMeters: Int              // recalculada localmente; mínimo zero
    var status: MockAppointmentStatus
    var meetingConfirmation: ParticipantConfirmation?
    var completionConfirmation: ParticipantConfirmation?
    let acceptedAt: Date
    var startedAt: Date?                          // só após confirmação bilateral de encontro
    var completedAt: Date?                        // só após confirmação bilateral de conclusão
    var revision: Int64                           // cresce em posição e transições
}

enum MockAppointmentStatus {
    case travelling
    case awaitingMeetingConfirmation
    case inProgress
    case awaitingCompletionConfirmation
    case completed
}
```

## UI state roots

### `PitTecClientMockUiState`

```swift
enum PitTecClientMockStage {
    case discovery
    case estimating
    case awaitingClientConfirmation(ServiceEstimate)
    case searching(MockSearch)
    case tracking(MockAppointment)
    case completed(MockAppointment)
    case noProvider(lastSearch: MockSearch)
}
```

### `ProviderLocationGate`

```swift
enum ProviderLocationGate {
    case checkingPermission, permissionRequired, approximateOnly
    case servicesDisabled, locating
    case ready(MockLocationSnapshot)
    case unavailable
}
```

Somente `.ready` permite compor o mapa e apresentar solicitações.

### `PitTecProviderMockUiState`

```swift
enum PitTecProviderMockStage {
    case available
    case incomingRequest(MockServiceRequest)
    case tracking(MockAppointment)
    case completed(MockAppointment)
}

enum PitTecProviderTab { case map, rideData, values, profile }
```

Trocar de aba não altera `stage` nem cria outro atendimento.

## State transitions

### Client

```text
.discovery
  -> .estimating
  -> .awaitingClientConfirmation
     -> .discovery                          (voltar/cancelar)
     -> .searching                          (confirmar uma vez)
        -> .searching/.declinedContinuing   (recusa; próximo candidato/faixa)
        -> .noProvider                      (fixtures esgotadas)
        -> .tracking/.travelling             (aceite)
           -> .awaitingMeetingConfirmation
           -> .inProgress                    (+3s contraparte)
           -> .awaitingCompletionConfirmation
           -> .completed                     (+3s contraparte)
```

### Provider

```text
LOCATION BLOCKED -> .available              (permissão + serviços + fix real)
.available -> .incomingRequest              (evento mock único/replay explícito)
.incomingRequest -> .available              (recusar uma vez)
.incomingRequest -> .tracking/.travelling   (aceitar uma vez)
.tracking -> .awaitingMeetingConfirmation -> .inProgress
.inProgress -> .awaitingCompletionConfirmation -> .completed
.completed -> .available                    (voltar ao mapa; último atendimento preservado)
```

## Idempotency and cancellation rules

- Toda ação compara estado atual e revisão; ação inválida ou repetida é no-op.
- Confirmar busca desabilita imediatamente o botão antes de iniciar qualquer delay.
- Aceitar/recusar remove a possibilidade da outra resposta na mesma atualização atômica de estado.
- Cada confirmação local registra timestamp uma única vez e agenda no máximo uma `Task` de
  contraparte.
- `Task`s capturam `appointmentID + revision`; antes de aplicar, revalidam ID, status e ausência da
  confirmação esperada.
- Finalização cancela `Task`s de movimento/stale e impede novas revisões de localização.
- A desalocação do ViewModel cancela todas as `Task`s; nenhum dado é salvo.
