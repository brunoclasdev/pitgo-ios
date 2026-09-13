# Data Model: Mapa OSM com MapLibre e atualização em tempo real (iOS)

Esta feature não cria histórico de localização nem altera a origem dos endereços. Os modelos abaixo
definem estado de View e a fronteira entre domínio e MapLibre Native iOS.

## 1. Coordenada e viewport

### `MapCoordinate`

```swift
struct MapCoordinate {
    let latitude: Double   // finito, -90...90
    let longitude: Double  // finito, -180...180
}
```

Coordenada inválida nunca vira feature GeoJSON: na descoberta o item é descartado; no tracking o
evento é rejeitado e não substitui a última posição aceita.

### `MapViewport`

```swift
struct MapViewport {
    var center: MapCoordinate
    var zoom: Double        // dentro do intervalo suportado pelo estilo
    var revision: Int64     // cresce somente em comando programático novo
}
```

Gestos atualizam o viewport, mas a busca só ocorre ao tocar "Buscar nesta área". A `revision` impede
que uma atualização de SwiftUI reaplique a câmera inicial ou repita um comando já consumido.

## 2. Estilo e recursos do mapa

### `ManagedMapStyleConfiguration`

```swift
struct ManagedMapStyleConfiguration {
    let styleURL: URL              // HTTPS absoluta, sem user-info/fragment/placeholder
    let providerName: String       // público, não vazio
    let attribution: String        // inclui crédito OSM e do provedor
    let attributionURL: URL        // HTTPS absoluta
}
```

Lido uma única vez do `Info.plist` (`MAP_STYLE_URL`, `MAP_PROVIDER_NAME`,
`MAP_PROVIDER_ATTRIBUTION`, `MAP_PROVIDER_ATTRIBUTION_URL`), validado em build via Run Script Build
Phase (mesmo mecanismo de `004-configure-supabase`). O Style JSON referencia tiles/sprites/glyphs
gerenciados; um token contido na URL é client-safe e restrito — segredo administrativo é proibido.

### `MapStyleState`

```swift
enum MapStyleState {
    case uninitialized
    case loading(revision: Int64)
    case ready(revision: Int64)
    case failed(revision: Int64)
}
```

Uma nova tentativa incrementa `revision`. Um callback de revisão anterior não pode substituir um
estado mais novo.

### `MapResourceState`

```swift
enum MapResourceState {
    case waiting
    case ready
    case degraded(MapDegradationKind)   // .tile, .glyph, .sprite, .render
    case offline
}

struct MapSurfaceState {
    var style: MapStyleState
    var resources: MapResourceState
}
```

Dados de providers, seleção e posição não são apagados por falha visual.

## 3. Modelo de renderização

### `MapMarkerSpec`

```swift
struct MapMarkerSpec {
    let id: String                  // opaco e estável
    let coordinate: MapCoordinate   // validada
    let kind: MapMarkerKind         // .address, .live, .stale, .coincidentGroup
    let selected: Bool              // altera forma/contorno e label, nunca só cor
    let groupKey: String?           // somente para coordenadas idênticas
    let accessibilityLabel: String  // ação/estado localizado
}
```

O `Coordinator` do `UIViewRepresentable` converte apenas `id`, `kind`, `selected` e `groupKey` em
propriedades GeoJSON (`MLNPointFeature.attributes`). Nome, preço, contato e outros dados
permanecem no estado de domínio (ViewModel), nunca na feature GeoJSON. Um reload de estilo recria
imagens/sources/layers e reaplica o modelo mais recente.

### `MapFeatureSelection`

```swift
enum MapFeatureSelection {
    case single(markerID: String)
    case coincidentGroup(groupKey: String)
    case nearbyCluster(coordinate: MapCoordinate)
    case none
}
```

Um cluster próximo aumenta o zoom. Um grupo coincidente resolve IDs pelo mapa de domínio e abre uma
lista SwiftUI. Nenhuma seleção depende de uma feature antiga após a source ser atualizada.

## 4. Descoberta

### `PublicProvider`

```swift
struct PublicProvider: Identifiable {
    let id: UUID              // providerID opaco do RPC
    let serviceID: UUID       // serviço autoritativo da busca
    let displayName: String
    let mode: ProviderLocationMode   // .fixed, .mobile
    let addressCoordinate: MapCoordinate   // sempre o endereço empresarial
    let distanceMeters: Double?
    let estimatedPrice: Decimal?
}
```

CNPJ, e-mail, telefone e localização móvel privada não pertencem a este modelo.

### `ServiceMapUiState`

```swift
enum ServiceMapUiState {
    case invalidService
    case content(ServiceMapContent)
}

struct ServiceMapContent {
    let serviceID: UUID
    var viewport: MapViewport
    var displayMode: MapDisplayMode          // .map, .list
    var dataState: DiscoveryDataState
    var surfaceState: MapSurfaceState
    var clientLocationState: ClientLocationState
    var providers: [PublicProvider]
    var coincidentGroups: [String: [UUID]]
    var selectedProviderID: UUID?
    var selectedGroupKey: String?
    var searchGeneration: UInt64
    var styleReloadRevision: Int64
}

enum DiscoveryDataState { case loading, ready, empty, offline, failure(reason: String), sessionExpired }
enum ClientLocationState { case notRequested, resolving, inUse, denied, unavailable }
```

Invariantes: provider selecionado pertence à lista atual; cada provider aparece uma vez na lista e
em exatamente um marcador/grupo; uma nova geração ignora respostas antigas; Mapa e Lista usam a
mesma coleção/seleção; FIXED e MOBILE usam o endereço empresarial na descoberta.

## 5. Tracking privado

### `LocationRevision`

```swift
struct LocationRevision: Comparable {
    let publishedAt: Date   // chave primária de ordenação (servidor)
    let version: Int64      // desempate

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.publishedAt != rhs.publishedAt
            ? lhs.publishedAt < rhs.publishedAt
            : lhs.version < rhs.version
    }
}
```

`capturedAt` do dispositivo nunca ordena o stream. Uma reinserção com `version = 1` é aceita quando
publicada depois do tombstone.

### `AppointmentProviderLocation`

```swift
struct AppointmentProviderLocation {
    let coordinate: MapCoordinate     // válida e privada
    let accuracyMeters: Double        // finita e positiva
    let capturedAt: Date              // informativa
    let publishedAt: Date             // server-side, exibida ao usuário
    let revision: LocationRevision
}
```

### `AppointmentLocationEvent`

```swift
enum AppointmentLocationEvent {
    case snapshot(AppointmentProviderLocation?)
    case upsert(AppointmentProviderLocation)
    case removed(LocationRevision)
    case ended(TerminalAppointmentStatus)   // .completed, .cancelled
    case sessionExpired
    case offline
    case failure
}
```

`.removed` grava um tombstone. `.upsert` só é aplicado se sua revisão for estritamente posterior.
`.snapshot(nil)` explícito não apaga um broadcast mais novo recebido durante a consulta.

### `TrackingDataState`

```swift
enum TrackingDataState {
    case loading
    case empty
    case live(AppointmentProviderLocation)
    case stale(AppointmentProviderLocation, lastUpdatedLabel: String)
    case ended
    case offline(lastLocation: AppointmentProviderLocation?)
    case sessionExpired
    case failure(lastLocation: AppointmentProviderLocation?)
}
```

Transições: posição nova com idade `<=30s` → `.live`; relógio ultrapassa 30s → `.stale`, mantendo
marcador e horário; `.removed` → `.empty` com tombstone interno; erro/offline com posição anterior →
`.stale`/degradado; `.ended`/`sessionExpired` → limpa coordenada antes de qualquer callback tardio
de estilo; View oculta → cancela assinatura/timer e limpa a posição privada; View visível → uma
assinatura nova seguida de snapshot.

## 6. Solicitação e relações

`RequestServiceSelection` contém apenas `serviceID` e `providerID`; o serviço é resolvido no
catálogo real. O callback permanece mockado nesta feature (`003`).

```text
ManagedMapStyleConfiguration ──> 1 MapLibreMapHost ──> discovery + tracking
Service ── discovery RPC ──> 0..200 PublicProvider ──> address MLNShapeSource
Appointment ── current location ──> 0..1 tracking MLNPointFeature
```

Viewport, seleção, estado de estilo e última posição visível são memória de View/processo. MapLibre
usa cache padrão interno do SDK; não há região offline. PostgreSQL mantém no máximo uma posição
corrente por atendimento e nenhuma trilha (backend compartilhado, inalterado).
