# Data Model: Sessão autenticada e cadastro de veículos (iOS)

## Overview

O modelo separa identidade autenticada, dados autorizados da conta, veículos e estado transitório de
UI. UUIDs são `UUID` nativo do Swift, mapeado para `uuid` no PostgreSQL via `Codable`. Nenhum modelo
de UI contém token; senha e rascunho de veículo vivem somente em memória enquanto sua View existe.
Schema, triggers, RPCs e RLS são os mesmos já aplicados e documentados em
[contracts/supabase.md](contracts/supabase.md) — nenhuma tabela ou coluna nova é criada por esta
feature iOS.

## 1. AppSessionState

Estado raiz mutuamente exclusivo, mantido por `SessionStore` (`@Observable`, `@MainActor`).

```swift
enum AppSessionState {
    case initializing
    case verifying
    case unauthenticated(reason: UnauthenticatedReason?)
    case offlineVerification
    case profileBlocked(ProfileBlockedReason)
    case authenticated(AccountSnapshot)
}

enum ProfileBlockedReason { case missing, inactive, inconsistent }
```

| Variante | Dados | Significado |
|---|---|---|
| `.initializing` | nenhum | SDK Auth ainda está carregando a sessão local |
| `.verifying` | nenhum dado renderizável | operação de validação/bootstrap em andamento |
| `.unauthenticated` | motivo opcional tipado | não há sessão válida; só o fluxo público pode aparecer |
| `.offlineVerification` | nenhum dado renderizável | sessão local preservada, mas rede impediu validação |
| `.profileBlocked` | `.missing`/`.inactive`/`.inconsistent` | identidade válida sem perfil autorizado para Home |
| `.authenticated` | `AccountSnapshot` | identidade, perfil e seleção de veículo validados |

### Transitions

```text
App start -> initializing
initializing -> unauthenticated                  (nenhuma sessão)
initializing -> verifying                        (sessão armazenada encontrada)
verifying -> authenticated                       (identidade + perfil válidos)
verifying -> offlineVerification                 (rede/timeout; sessão preservada)
verifying -> profileBlocked                      (perfil ausente/inativo/inconsistente)
verifying -> unauthenticated                     (sessão inválida/expirada)
offlineVerification -> verifying                 (retry)
profileBlocked -> verifying                      (retry)
profileBlocked -> unauthenticated                (Sair)
unauthenticated -> verifying                     (login ou cadastro concluído)
authenticated -> verifying                       (refresh explícito/bootstrap)
authenticated -> offlineVerification             (refresh expirado sem rede)
authenticated -> unauthenticated                 (logout, revogação ou sessão inválida)
```

Invariante: somente `.authenticated` entrega perfil ou veículo à UI. Toda saída dessa variante
remove imediatamente o snapshot anterior (`SessionStore` zera a propriedade observável).

## 2. AccountSnapshot

```swift
struct AccountSnapshot {
    let userID: UUID          // exclusivamente da sessão Supabase
    let authEmail: String     // e-mail retornado pela identidade validada
    let profile: Profile
    let primaryVehicle: Vehicle?
}
```

Validações (aplicadas por `AccountRepository` antes de emitir `.authenticated`):

- `profile.id == userID`;
- `profile.email` corresponde a `authEmail` sem diferença de caixa;
- nome, e-mail e telefone do perfil são não vazios;
- exatamente um entre CPF e CNPJ existe;
- `profile.isActive == true`;
- se houver veículo, `vehicle.userID == userID`, `active == true` e `isPrimary == true`.

## 3. Profile

Mesma projeção de `public.profiles` já usada por `005`, ampliada com `avatarURL`:

```swift
struct Profile: Decodable {
    let id: UUID
    let name: String
    let email: String
    let phone: String
    let cpf: String?
    let cnpj: String?
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, name, email, phone, cpf, cnpj
        case avatarURL = "avatar_url"
        case isActive = "active"
    }
    let isActive: Bool

    var displayName: String { name.trimmingCharacters(in: .whitespaces) }
    var initials: String { /* primeiras letras de até duas palavras significativas, maiúsculas */ }
}
```

CPF/CNPJ não são exibidos nas telas desta feature.

## 4. Vehicle

Mapeia `public.vehicles` (schema já aplicado, ver `contracts/supabase.md`).

```swift
struct Vehicle: Decodable, Identifiable {
    let id: UUID
    let userID: UUID           // sempre auth.uid(); nunca vem do formulário
    let brand: String
    let model: String
    let version: String?
    let manufactureYear: Int?
    let modelYear: Int?
    let plate: String?          // canônica, 7 caracteres, legado ou Mercosul
    let renavam: String?        // exatamente 11 dígitos, preserva zeros
    let chassis: String?        // 17 caracteres VIN maiúsculo, sem I/O/Q
    let color: String?
    let fuelType: String?
    let transmission: String?
    let engine: String?
    let mileage: Int?
    let isPrimary: Bool         // controlado exclusivamente pelos RPCs
    let active: Bool            // true na criação; inativo nunca é selecionável
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case brand, model, version
        case manufactureYear = "manufacture_year"
        case modelYear = "model_year"
        case plate, renavam, chassis, color
        case fuelType = "fuel_type"
        case transmission, engine, mileage
        case isPrimary = "is_primary"
        case active
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
```

### Database invariants (inalteradas, já aplicadas)

- placa, Renavam e chassi são únicos quando não nulos;
- `is_primary` implica `active`;
- no máximo um veículo principal por usuário;
- após qualquer criação concluída para uma conta com veículos, exatamente um veículo ativo é
  principal;
- marca/modelo não podem ser vazios após trim;
- intervalos e formatos são repetidos nos RPCs/constraints.

## 5. VehicleDraft

Entrada imutável normalizada, criada somente no submit do formulário; nunca persistida localmente.

```swift
struct VehicleDraft {
    var brand: String
    var model: String
    var version: String?
    var manufactureYear: Int?
    var modelYear: Int?
    var plate: String?
    var renavam: String?
    var chassis: String?
    var color: String?
    var fuelType: String?
    var transmission: String?
    var engine: String?
    var mileage: Int?
    var makePrimary: Bool       // ignorado como false se for o primeiro veículo (regra do RPC)
}
```

Não contém `id`, `userID`, `active`, `isPrimary`, timestamps ou qualquer valor de sessão. O
Repository converte o draft nos parâmetros exatos do RPC (ver `contracts/supabase.md`). O rascunho
não usa `@AppStorage`/`SwiftData`; expiração da sessão substitui o estado por valores vazios e remove
a rota (ver `research.md §6`).

### Local field errors

```swift
enum VehicleField {
    case brand, model, version, manufactureYear, modelYear
    case plate, renavam, chassis, color, fuelType, transmission, engine, mileage
}

enum VehicleFieldError { case required, invalidFormat, outOfRange, unavailable }
```

O primeiro erro segue a ordem visual e recebe `@FocusState`. Conflitos remotos marcam somente placa,
Renavam ou chassi quando a constraint allowlisted identificar o campo.

## 6. VehicleOnboardingPending

Preferência local simples em `UserDefaults`, representada como `Set<String>` de UUIDs (chave
`"pitgo.pendingVehicleOnboarding"`).

```swift
struct VehicleOnboardingStore {
    func markPending(_ userID: UUID)
    func isPending(_ userID: UUID) -> Bool
    func resolve(_ userID: UUID)
}
```

| Operação | Efeito |
|---|---|
| `markPending(userID)` | adiciona o UUID depois de perfil criado e antes do sucesso do cadastro |
| `isPending(userID)` | decide convite versus Home após sessão validada |
| `resolve(userID)` | remove o UUID antes de navegar por qualquer escolha explícita |

Não armazena escolha, veículo, documento, senha ou token. Logout não remove a pendência; ela precisa
ser reapresentada quando a mesma conta voltar. Apagar o app/dados locais pode remover a preferência,
o que está fora da garantia de simples encerramento/reabertura.

## 7. Screen states

### LoginUiState

```swift
struct LoginUiState {
    var email: String = ""
    var password: String = ""       // memória apenas
    var fieldErrors: LoginFieldErrors = .init()
    var submission: LoginSubmissionState = .editing
}

enum LoginSubmissionState {
    case editing
    case submitting
    case failure(LoginFailureReason)
}

enum LoginFailureReason { case invalidCredentials, offline, timeout, rateLimited, service, unknown }
```

Senha não é salva e é limpa após falha remota ou saída da View.

### HomeUiState

```swift
enum HomeUiState {
    case loading
    case content(AccountSnapshot, services: [ServiceCategory])
    case noVehicle(Profile, services: [ServiceCategory])
    case failure(HomeFailureReason)
}
```

`.content` e `.noVehicle` só são construídos a partir de `AppSessionState.authenticated`.

### GarageUiState

```swift
enum GarageUiState {
    case loading
    case empty
    case content([Vehicle], changingPrimaryVehicleID: UUID?)
    case failure(GarageFailureReason)
}
```

Lista contém somente veículos ativos do usuário atual. Durante troca de principal, toques
concorrentes são ignorados; sucesso atualiza a lista de forma que exatamente um item fique
selecionado.

### VehicleFormUiState

```swift
struct VehicleFormUiState {
    var draft: VehicleDraft
    var fieldErrors: [VehicleField: VehicleFieldError]
    var existingVehicleCount: Int   // decide visibilidade da opção "Tornar principal"
    var submission: VehicleFormSubmissionState
    var origin: VehicleFormOrigin   // .onboarding ou .garage
}

enum VehicleFormOrigin { case onboarding, garage }
enum VehicleFormSubmissionState { case editing, submitting, success, failure(VehicleFormFailureReason) }
```

`isInputEnabled` é derivado de `submission` (computed property).

### SessionGateUiState

Derivado diretamente de `AppSessionState` (não é um `struct` próprio — a `View` faz `switch` direto
no estado do `SessionStore`):

- `.initializing`/`.verifying`: progresso sem ações;
- `.offlineVerification`: mensagem + `Tentar novamente`;
- `.profileBlocked`: mensagem + `Tentar novamente` + `Sair`.

## 8. Relationships

```text
auth.users (1) ───── (1) profiles
                         │
                         └──── (0..N) vehicles

AppSessionState.authenticated
  └── AccountSnapshot
       ├── Profile (exatamente 1)
       └── primaryVehicle (0..1 Vehicle ativo)

VehicleOnboardingPending (UserDefaults)
  └── referencia apenas userID; sem foreign key no banco
```

## 9. Sensitive-data lifecycle

- senha: memória da `LoginView`/`SignUpView` até conclusão/falha/saída; nunca persistida ou logada;
- token de sessão: gerido exclusivamente pelo `supabase-swift` (Keychain) e removido localmente no
  logout; ver `research.md §9` para a verificação de acessibilidade do item;
- CPF/CNPJ: carregados somente quando necessários à consistência do perfil; nunca renderizados ou
  registrados nesta feature;
- Renavam/chassi: rascunho apenas em memória e parâmetros de RPC; mensagens usam apenas o nome do
  campo;
- logout/troca/expiração: remove `AccountSnapshot`, estados Home/Garagem e rascunho antes de mostrar
  outro fluxo.
