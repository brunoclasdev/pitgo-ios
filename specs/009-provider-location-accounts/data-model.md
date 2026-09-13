# Data Model: Contas independentes e localização de prestadores (iOS)

## Relationship overview (backend compartilhado, inalterado)

```text
auth.users 1─1 account_roles
   ├─ CLIENT   1─1 profiles 1─N vehicles
   └─ PROVIDER 1─0..1 providers 1─1 addresses
                            ├─N provider_categories N─1 service_categories
                            └─N provider_services   N─1 services N─1 service_categories

profiles 1─N appointments N─1 providers
appointments 1─0..1 provider_current_locations
```

`providers.id` é o identificador estável da empresa. `providers.account_id` é o owner Auth
substituível. Nunca devem ser confundidos novamente. Todas as tabelas, colunas, constraints e RPCs
abaixo já existem e estão aplicadas no projeto Supabase compartilhado com o Android — ver
[research.md §0](research.md) e `contracts/account-provider-database.md`. Esta seção documenta o
contrato para implementação do client iOS, sem repetir SQL.

## Entidades persistidas (referência — schema já aplicado)

- **AccountRole** (`public.account_roles`): `user_id` PK/FK `auth.users`, `account_type` (`CLIENT`
  ou `PROVIDER`, imutável), `created_at`. Uma identidade Auth tem exatamente um papel.
- **Profile** (`public.profiles`, de `005`): permanece exclusivo de CLIENT.
- **Provider** (`public.providers`, de `007`, estendido): `id` (PK estável), `account_id` (FK única
  do owner Auth), `name`, `description?`, `email`, `phone`, `cnpj`, `location_mode`
  (`FIXED`/`MOBILE`), `active`, `available`.
- **ServiceCategory**/**Service** (`public.service_categories`/`public.services`, de `007`):
  catálogo somente leitura, agora com `active`.
- **ProviderCategory** (`public.provider_categories`): PK composta `(provider_id, category_id)`,
  derivada pela RPC a partir dos serviços escolhidos.
- **ProviderService** (`public.provider_services`, de `007`): inalterado, agora validado contra
  `provider_categories`.
- **Address** (`public.addresses`, de `007`, estendido): campos texto BR + `latitude`/`longitude` +
  `location geography(Point,4326)` + `geocode_place_id` + `geocoded_at` + `geocode_valid_until` +
  `location_verified_at` + `divergence_distance_m?` + `divergence_confirmed_at?`.
- **GeocodeVerification** (`private.provider_geocode_verifications`): prova efêmera de 15 minutos
  criada só pela Edge Function; nunca contém a coordenada bruta do dispositivo.
- **ProviderOwnershipTransfer** (`private.provider_ownership_transfers`): token hash SHA-256, janela
  de 15 minutos, estados `PENDING`/`CLAIMED`/`CANCELLED`/`EXPIRED`.
- **Appointment** (`public.appointments`): âncora mínima de autorização, estados `PENDING` →
  `ACCEPTED` → `IN_PROGRESS` → `COMPLETED`/`CANCELLED`. Sem UI/RPC de despacho nesta feature.
- **ProviderCurrentLocation** (`public.provider_current_locations`): uma linha por atendimento, sem
  histórico; `version` monotônica, `tracker_instance_id`/`tracker_sequence` para arbitragem.
- **ServiceMapResult**: projeção pública não persistida, retornada pela RPC de descoberta.

## Modelos Swift do client

### AccountContext (mapeia `get_my_account_context()`)

```swift
struct AccountContext: Decodable {
    let accountType: AccountType
    let clientState: ClientState?
    let providerState: ProviderState?
    let providerID: UUID?
    let legacyProviderMigrationAvailable: Bool

    enum CodingKeys: String, CodingKey {
        case accountType = "account_type"
        case clientState = "client_state"
        case providerState = "provider_state"
        case providerID = "provider_id"
        case legacyProviderMigrationAvailable = "legacy_provider_migration_available"
    }
}

enum AccountType: String, Decodable { case client = "CLIENT", provider = "PROVIDER" }
enum ClientState: String, Decodable { case ready = "READY" }
enum ProviderState: String, Decodable { case onboarding = "ONBOARDING", ready = "READY", incomplete = "INCOMPLETE" }
```

### AppSessionState (extensão de `006`)

```swift
enum AppSessionState {
    case initializing
    case verifying
    case unauthenticated(reason: UnauthenticatedReason?)
    case offlineVerification
    case blocked(reason: BlockedReason)
    case authenticatedClient(AccountSnapshot)
    case authenticatedProviderOnboarding(AuthIdentity)
    case authenticatedProviderReady(ProviderSnapshot)
}
```

Qualquer mudança de usuário, papel ausente, CLIENT sem perfil válido, PROVIDER com perfil
contradizente ou Provider inconsistente limpa o estado visível de feature e bloqueia rotas
protegidas — mesma regra do Android.

### ProviderAddressVerification

```swift
enum ProviderAddressVerificationState {
    case unverified
    case geocoding
    case awaitingPrecisePermission
    case locating
    case matched(distanceMeters: Double)          // <= 500
    case diverged(distanceMeters: Double)          // > 500, aguardando confirmação
    case confirmedDivergence(distanceMeters: Double)
    case failure(reason: GeocodingFailureReason)
}
```

Editar qualquer campo do endereço retorna a `.unverified`. Somente `.matched`/
`.confirmedDivergence` com prova não expirada habilita o submit — mesma regra do Android.

### ProviderRegistrationUiState (extensão de `007`)

```swift
enum ProviderRegistrationUiState {
    case loadingCatalog
    case editing(EditingContent)         // + locationMode obrigatório, + verification state
    case verifyingLocation
    case submitting
    case failure(reason: ProviderRegistrationFailureReason, recoverable: Bool)
    case success(ProviderSummary)
    case alreadyRegistered(ProviderSummary)
    case sessionBlocked
}
```

O rascunho existe só na memória do ViewModel. Duplo submit é ignorado. A conta Auth pode permanecer
`.authenticatedProviderOnboarding` após falha, mas nenhum agregado parcial é tratado como sucesso.

### ServiceMapUiState

```swift
enum ServiceMapUiState {
    case loading
    case content(results: [ServiceMapResult], viewport: MapViewport, locationMode: ClientLocationMode)
    case empty
    case offline
    case failure(reason: ServiceMapFailureReason)
}

struct ServiceMapResult: Decodable, Identifiable {
    let id: UUID              // provider_id opaco, id de negócio
    let displayName: String
    let locationMode: ProviderLocationMode   // .fixed, .mobile
    let latitude: Double
    let longitude: Double
    let serviceSummary: String
    let minimumPrice: Decimal?
    let distanceMeters: Double?
}
```

Cada requisição tem uma geração (`UInt64` incremental); respostas de um serviço/viewport antigo são
descartadas. A localização do cliente vive só em memória; negação usa região manual/pan.

### ProviderTrackingState

```swift
enum ProviderTrackingState {
    case stopped
    case starting
    case active(lastPublishedAt: Date)
    case degraded(reason: TrackingDegradedReason)
    case stopping
}
```

Condições de parada: atendimento terminal, provider fixo/inativo/indisponível, perda/troca de
sessão, perda de permissão, serviço de localização desligado, conflito de publisher ou parada
explícita. Encerramento do processo não reinicia silenciosamente; a linha do servidor fica stale.

### AppointmentMarkerState

```swift
enum AppointmentMarkerState {
    case unavailable
    case live(location: CLLocationCoordinate2D, version: Int64, updatedAt: Date)
    case stale(location: CLLocationCoordinate2D, version: Int64, updatedAt: Date)
    case ended
}
```

Broadcast e snapshot mesclam por `version`; um timer local transiciona `.live` para `.stale` em 30
segundos mesmo sem outro evento de rede.

## Invariantes de segurança (herdadas do backend compartilhado)

- owner de provider é sempre `providers.account_id`, nunca um campo editável no client;
- `ServiceMapResult` nunca contém UUID de conta, CNPJ, e-mail, telefone, endereço textual, ponto do
  cliente ou ponto móvel corrente;
- coordenada de dispositivo nunca é persistida — só a coordenada geocodificada do endereço;
- desafio de migração de propriedade vive só em memória de processo, nunca em `UserDefaults`/
  `Keychain`/rota/log;
- nenhuma tabela mantém histórico de deslocamento — apenas a posição atual aplicável.
