# Data Model: Criar conta de usuário (iOS)

## Overview

O fluxo mantém um rascunho somente em memória (`SignUpUiState`), produz um `AccountRegistration`
normalizado, cria uma identidade Supabase Auth e garante um único perfil PostgreSQL com o mesmo
UUID — o mesmo schema já documentado e aplicado pelo backend compartilhado com o Android (ver
[research.md §0](research.md)). Senha nunca pertence ao perfil nem a qualquer tipo persistido
(`Codable` salvo em disco, `SwiftData`, `UserDefaults`).

```text
SignUpUiState (draft)
        │ validate + normalize
        ▼
AccountRegistration ── signUp ──► auth.users (id)      [backend compartilhado, inalterado]
                                      │ 1:1, FK + trigger/recovery
                                      ▼
                                public.profiles (id)    [backend compartilhado, inalterado]
```

## PersonType

```swift
enum PersonType: Hashable {
    case individual   // Pessoa física — exige CPF
    case company       // Pessoa jurídica — exige CNPJ
}
```

| Case | UI meaning | Required document | `profiles` representation |
|---|---|---|---|
| `.individual` | Pessoa física | CPF | `cpf` presente; `cnpj` nulo |
| `.company` | Pessoa jurídica | CNPJ | `cnpj` presente; `cpf` nulo |

`PersonType` pertence somente ao modelo de domínio/rascunho local. É inferido a partir do documento
não nulo e não cria uma coluna adicional no banco — idêntico ao Android.

## SignUpDraft

Valores de formulário mantidos por `SignUpViewModel` (`@Observable`) dentro de `SignUpUiState`.

```swift
struct SignUpDraft {
    var personType: PersonType?
    var name: String = ""
    var email: String = ""
    var phone: String = ""       // dígitos puros no estado
    var document: String = ""     // CPF (dígitos) ou CNPJ (alfanumérico maiúsculo), conforme personType
    var password: String = ""     // apenas em memória
    var passwordConfirmation: String = "" // apenas em memória
}
```

| Campo | Regra |
|---|---|
| `personType` | Obrigatório antes do envio |
| `name` | Rótulo é "Nome completo" para `.individual` e "Razão social / nome da empresa" para `.company` |
| `email` | Obrigatório; normalizado só na validação/envio |
| `phone` | Somente dígitos no estado; máximo 11 |
| `document` | Um único campo; dígitos de CPF ou alfanumérico maiúsculo de CNPJ conforme `personType` |
| `password` | No mínimo 8 caracteres; somente memória |
| `passwordConfirmation` | Deve igualar `password`; somente memória |

Alternar `personType` limpa `document` e seu erro, tornando CPF e CNPJ simultâneos irrepresentáveis
— mesma garantia do Android. Nome, e-mail e telefone são preservados. Os campos de senha são
limpos após qualquer falha remota concluída e no sucesso; nunca chegam a um tipo `Codable`
persistido nem a `@SceneStorage`/`@AppStorage`.

## AccountRegistration

Entrada normalizada e validada, passada do ViewModel ao Repository.

```swift
struct AccountRegistration {
    let personType: PersonType
    let name: String     // trim() não vazio; caracteres internos preservados
    let email: String    // trim().lowercased() e localmente válido
    let phone: String    // 10 ou 11 dígitos com DDD brasileiro válido
    let cpf: String?     // exatamente 11 dígitos válidos para .individual; senão nil
    let cnpj: String?    // exatamente 14 caracteres canônicos com DVs válidos para .company; senão nil
    let password: String // no mínimo 8 caracteres; consumida só por Auth/recovery
}
```

Invariante: exatamente um entre `cpf` e `cnpj` é não nulo (garantido pelo `init` do tipo, que aceita
apenas `personType` + `document` normalizado e distribui o valor para o campo correto).

## Auth signup metadata

A requisição de signup carrega somente os valores necessários ao trigger/recuperação, como
`[String: AnyJSON]` (tipo do `supabase-swift` para JSON arbitrário aceito por `data:` em `signUp`):

| Key | Source | Rule |
|---|---|---|
| `name` | nome normalizado | Obrigatório |
| `phone` | telefone normalizado | Obrigatório |
| `cpf` | CPF | Presente somente para pessoa física |
| `cnpj` | CNPJ | Presente somente para pessoa jurídica |

E-mail vem de `auth.users.email` (gerenciado pelo próprio `signUp(email:password:...)`); senha e
`active` nunca são metadata. A metadata de usuário é entrada não confiável e não pode ser usada em
RLS — os CHECKs do banco continuam a autoridade final (compartilhados, inalterados).

## Profile (`public.profiles`)

Schema idêntico ao já aplicado para o Android — nenhuma coluna, constraint, trigger ou policy nova.
Ver [contracts/profiles-schema.md](contracts/profiles-schema.md) para a tabela completa de colunas e
constraints nomeadas. Resumo:

| Column | Tipo Postgres | Null | Default |
|---|---|---:|---|
| `id` | `uuid` | Não | — (FK `auth.users(id)`) |
| `name` | `text` | Não | — |
| `email` | `text` | Não | — |
| `phone` | `text` | Não | — |
| `cpf` | `text` | Sim | `null` |
| `cnpj` | `text` | Sim | `null` |
| `active` | `boolean` | Não | `true` |

Nenhum campo de tipo de pessoa, timestamp, endereço, entidade de empresa ou atividade editável é
adicionado — igual ao Android.

## DTOs (Codable)

### ProfileInsertDTO

```swift
struct ProfileInsertDTO: Encodable {
    let id: UUID
    let name: String
    let email: String
    let phone: String
    let cpf: String?
    let cnpj: String?
    // `active` é omitido; o default do banco permanece autoritativo.
}
```

### ProfileDTO

```swift
struct ProfileDTO: Decodable {
    let id: UUID
    let name: String
    let email: String
    let phone: String
    let cpf: String?
    let cnpj: String?

    enum CodingKeys: String, CodingKey {
        case id, name, email, phone, cpf, cnpj
        case isActive = "active"
    }
    let isActive: Bool
}
```

`CodingKeys` mapeia a propriedade Swift `isActive` para a coluna real `active`, mesmo racional do
`@SerialName` do Android. Usado somente para confirmar um perfil consistente; nenhum modelo de perfil
de UI é introduzido nesta feature.

## Validation results

```swift
struct SignUpFieldErrors {
    var personType: SignUpFieldError?
    var name: SignUpFieldError?
    var email: SignUpFieldError?
    var phone: SignUpFieldError?
    var document: SignUpFieldError?
    var password: SignUpFieldError?
    var passwordConfirmation: SignUpFieldError?
}
```

`SignUpFieldError` é um `enum` de casos tipados (sem string renderizada nem exceção crua de
backend). A ordem de validação para foco segue a ordem visual: tipo de pessoa → nome → e-mail →
telefone → documento → senha → confirmação. Todos os erros aplicáveis são calculados em uma única
passada; `FocusRequest(field: SignUpField, requestID: Int)` aponta para o primeiro e incrementa
`requestID` a cada envio inválido, para que `@FocusState` sempre reaja mesmo que o campo alvo não
mude entre duas tentativas.

## RegistrationResult

Saída de domínio do Repository, retornada por valor (não lançada como `Error`):

```swift
enum RegistrationResult {
    case success(userID: UUID)
    case emailUnavailable
    case documentUnavailable
    case invalidServerInput
    case rateLimited
    case offline
    case serviceUnavailable
    case profileRecoveryRequired
    case environmentMisconfigured
    case unknown
}
```

| Result | Meaning | UI behavior |
|---|---|---|
| `.success` | Sessão e perfil do mesmo ID confirmados | Define Success; navega para Home |
| `.emailUnavailable` | Conflito estável de e-mail em Auth/DB | Erro no campo e-mail, texto neutro |
| `.documentUnavailable` | Conflito de unique CPF/CNPJ allowlisted | Erro no campo documento, texto neutro |
| `.invalidServerInput` | Backend rejeitou contrato/senha fraca | Erro de campo/banner; sem detalhe técnico |
| `.rateLimited` | Auth/API com throttling | Pedir para aguardar antes de nova tentativa |
| `.offline` | Rede indisponível | Preserva campos não sensíveis; permite retry |
| `.serviceUnavailable` | Timeout ou erro 5xx/config | Preserva campos não sensíveis; permite retry |
| `.profileRecoveryRequired` | Sessão existe mas perfil não confirmado | Mantém Home bloqueada; retry de recuperação |
| `.environmentMisconfigured` | Signup não produziu sessão imediata | Bloqueia Home; mensagem genérica de configuração |
| `.unknown` | Falha não mapeada, sanitizada | Mensagem genérica de retry |

Exceções brutas do SDK e suas mensagens/detalhes nunca cruzam a fronteira do Repository.

## SignUpUiState

```swift
struct SignUpUiState {
    var draft: SignUpDraft
    var fieldErrors: SignUpFieldErrors
    var focusRequest: FocusRequest?
    var submission: SignUpSubmissionState
}

enum SignUpSubmissionState {
    case editing
    case submitting(SignUpStage)
    case failure(reason: RegistrationResult, profilePending: Bool)
    case success
}

enum SignUpStage {
    case creatingAccount
    case ensuringProfile
    case recoveringProfile
}
```

Propriedades derivadas (computed properties na `struct` ou em uma extensão) incluem `hasDraft`,
`isInputEnabled` (`false` durante qualquer `.submitting`), rótulo dinâmico de nome/documento e
tipo de teclado/comprimento máximo do documento atual — mesmo conjunto de derivações do Android.

## State transitions

```text
editing ── envio inválido ─────────────► failure(.invalidServerInput*, false) ── editar ─► editing
   │        (*validação local, não remota)
   └── envio válido ─► submitting(.creatingAccount)
                           │
                           ├── falha Auth ─► failure(reason, false) ─► editing/retry
                           │
                           └── sessão ok ─► submitting(.ensuringProfile)
                                              │
                                              ├── perfil confirmado ─► success
                                              └── parcial/ambíguo ─► failure(reason, profilePending: true)
                                                                            │
                                                                            └── retry
                                                                                ▼
                                                               submitting(.recoveringProfile)
```

Envios durante qualquer `submitting` são no-ops (guarda síncrona antes de criar a `Task`). A
navegação para Home ocorre somente a partir de `.success`. O botão/gesto de voltar pede confirmação
quando `hasDraft` é verdadeiro e fica bloqueado enquanto uma operação potencialmente já commitada no
servidor está sendo finalizada.
