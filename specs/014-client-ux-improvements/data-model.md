# Data Model: Melhoria de UX das telas do cliente (iOS)

Esta feature é majoritariamente de apresentação (estados de UI, navegação, mapa). Só uma entidade
persistida é realmente nova para o client iOS consumir (`ClientAddress`, backend compartilhado); as
demais já existem em specs anteriores e são apenas referenciadas/exibidas de forma diferente. Uma
preferência local nova (`AppearanceMode`) também é adicionada, sem backend.

## 1. `ClientAddress` (backend compartilhado, já existe)

```swift
struct ClientAddress: Codable {
    let street: String
    let number: String
    let neighborhood: String
    let zipCode: String
    let city: String
    let state: BrazilianState   // enum de 007/009
    let country: String = "BR"
    let complement: String?
    let latitude: Decimal?
    let longitude: Decimal?
}
```

Sem relação com `public.addresses` (endereço público/geocoded do prestador em modo `FIXED`, `007`/
`009`) — conceitos e ciclos de vida diferentes. Um cliente tem no máximo um endereço (upsert por
`clientID`); ausência de linha = "endereço não cadastrado" (estado já coberto pela Home desde `006`).
RLS restringe cada cliente à própria linha; toda leitura/escrita passa pelas RPCs
`get_my_client_address`/`upsert_my_client_address` (ver `contracts/client-address-rpcs.md`).

### Estados de UI

```swift
enum ClientAddressUiState {
    case loading
    case empty          // sem endereço cadastrado
    case content(ClientAddress)
    case saving
    case failure(reason: String)
}
```

## 2. `AppearanceMode` (novo, local)

```swift
enum AppearanceMode: String, CaseIterable { case light, dark, system }
```

Preferência local persistida via `@AppStorage` (`AppearancePreferences`), sem backend. `.system` é o
padrão até a primeira escolha manual. Consumida por `pitgoApp.swift` para decidir o
`ColorScheme?` passado a `.preferredColorScheme(_:)` na raiz (`nil` para `.system` → segue o tema do
dispositivo).

## 3. `ClientCurrentLocation` (backend compartilhado, já existe)

Leitura pontual de GPS do cliente (via `DeviceLocationRepository`, `009`), capturada ao abrir/
reabrir `AppointmentTrackingView`. Persistida numa tabela mínima e efêmera para que o provider
também a veja no próprio mapa (US3) — espelha `provider_current_locations` (`009`), sem campos de
lease/tracker (leitura única por abertura de tela, não um stream contínuo disputado).

```swift
struct ClientCurrentLocation: Codable {
    let latitude: Decimal    // -90...90
    let longitude: Decimal   // -180...180
    let accuracyMeters: Double  // > 0 e <= 5000 (mais permissivo que os 100m do provider — aqui o
                                  // objetivo é centralizar o mapa, não guiar uma busca)
    let capturedAt: Date
    let publishedAt: Date   // definido pelo servidor
}
```

Só existe enquanto o atendimento estiver `ACCEPTED`/`IN_PROGRESS`; apagada ao chegar a um estado
terminal (mesmo padrão de `provider_current_locations`/`provider_discovery_locations`, `009`/`013`).
RLS restringe escrita ao cliente dono do atendimento e leitura aos dois participantes, via RPCs
`SECURITY DEFINER` (ver `contracts/client-location-rpcs.md`).

## 4. Entidades existentes referenciadas (sem alteração de schema)

- **`MobileDispatchSnapshot`/`DispatchAppointment`/`CandidateProposal`** (`013`): status, preço,
  deadline, revisão — consumidos pelas correções de FR-002/FR-003 (loading inline, formatação de
  distância) sem mudança de estrutura.
- **`ProviderCurrentLocation`** (`009`, canal `appointment-location:<id>`): posição em tempo real do
  provider durante um atendimento aceito; consumida pelo mapa do cliente (já existente desde `009`/
  `010`) e pelo novo mapa do provider (item novo desta feature), sem mudança de schema.
- **`Vehicle`/veículo padrão** (`006`): já modelado; esta feature só adiciona navegação a partir de
  Home/Perfil, sem novos campos.
- **`ProviderTrackingState`/`MobileDispatchSnapshot`**: usados pela especificação do botão voltar
  (FR-017/FR-018); o campo `revision` já existente passa a ser comparado explicitamente para decidir
  se a navegação automática deve disparar novamente.

## 5. Relações

```text
Client (auth.uid()) 1 ── 0..1 ClientAddress
Client 1 ── 0..1 AppearanceMode (local, @AppStorage)
Client 1 ── 0..1 Vehicle padrão (já existente, 006)
Appointment (já existente, 009/013) 1 ── 0..1 ClientCurrentLocation (backend compartilhado, efêmera)
Appointment 1 ── 0..1 ProviderCurrentLocation (já existente, tempo real)
```

Nenhuma tabela nova é criada por esta feature iOS — `client_addresses` e `client_current_locations`
já existem e são compartilhadas; nenhuma alteração em tabelas/RLS/RPCs de `009`/`011`/`013` além da
leitura já autorizada de `ProviderCurrentLocation` pelo novo mapa do provider (mesma autorização de
participante do atendimento já existente).
