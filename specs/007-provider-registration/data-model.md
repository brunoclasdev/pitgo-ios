# Data Model: Cadastro de empresa prestadora (iOS)

## Visão geral

O agregado de cadastro é identificado pela própria conta autenticada. Uma confirmação cria ou
reconhece exatamente um `Provider`, exatamente um `Address` inicial e uma ou mais
`ProviderService`. `ServiceCategory` e `CatalogService` são catálogo somente leitura. Nenhum ID de
proprietário é originado no formulário. Schema idêntico ao já aplicado para o Android — ver
[contracts/supabase-provider-registration.md](contracts/supabase-provider-registration.md).

```text
Profile/Auth user (1) ── (0..1) Provider (1) ── (1) Address
                                  │
                                  └── (1..N) ProviderService (N..1) CatalogService
                                                                  │
                                                                  └── (N..1) ServiceCategory
```

## Entidades persistidas (backend compartilhado, inalterado)

### Provider (`public.providers`)

| Campo | Tipo | Regra |
|---|---|---|
| `id` | UUID | PK; FK `auth.users(id)` com cascade; sempre `auth.uid()` |
| `name` | text | obrigatório, trim, não vazio |
| `description` | text nullable | trim; vazio vira null |
| `email` | text | obrigatório, lowercase + trim, formato de e-mail |
| `phone` | text | obrigatório, 10 ou 11 dígitos, DDD brasileiro válido |
| `cnpj` | text | obrigatório, uppercase, 12 caracteres alfanuméricos + 2 DVs numéricos, DV válido |

Invariantes: uma conta possui no máximo um provider (mesmo `id` da conta); `email`/`cnpj` únicos
após normalização; e-mail comercial pode diferir de `profiles.email`; o client não envia `id`.

### Address (`public.addresses`)

| Campo | Tipo | Regra |
|---|---|---|
| `id` | UUID | PK gerada no banco |
| `provider_id` | UUID | FK `providers(id)` cascade; derivada pelo banco; único nesta feature |
| `street` | text | obrigatório |
| `number` | text | obrigatório; aceita `s/n`, bloco, lote |
| `neighbornhood` | text | obrigatório; grafia física legada preservada no banco |
| `zip_code` | text | exatamente 8 dígitos |
| `city` | text | obrigatório |
| `state` | text | uma das 27 siglas de UF, maiúscula |
| `country` | text | constante `"BR"`; UI exibe "Brasil" |
| `complement` | text nullable | vazio vira null |
| `latitude` | numeric nullable | presente junto com longitude; -90 a 90 |
| `longitude` | numeric nullable | presente junto com latitude; -180 a 180 |

No domínio Swift a propriedade chama `neighborhood`; o `CodingKeys` é a única fronteira que conhece
`neighbornhood` (mesma estratégia de `Profile.isActive`↔`active`).

### ServiceCategory (`public.service_categories`) / CatalogService (`public.services`)

Catálogo somente leitura, nomes únicos case-insensitive (categoria globalmente, serviço por
categoria). Esta feature apenas consulta; nome livre informado pelo usuário não é aceito.

### ProviderService (`public.provider_services`)

| Campo | Tipo | Regra |
|---|---|---|
| `provider_id` | UUID | FK `providers(id)` cascade; derivada por `auth.uid()` |
| `service_id` | UUID | FK `services(id)` restrict |
| `price` | numeric | escala máxima 2; zero somente após comando gratuito; senão > 0 |
| `duration_minutes` | integer | 1 a 10.080 |
| `description` | text nullable | descrição comercial; vazio vira null |

Invariantes: UNIQUE `(provider_id, service_id)`; ao menos uma associação no agregado concluído;
`price = 0` é a representação persistida de gratuidade (`isFree` existe só no payload de comando,
não é uma coluna); descrição comercial não altera `services.description`.

## Modelos do fluxo iOS

### ProviderRegistrationDraft

```swift
struct ProviderRegistrationDraft {
    var company: CompanyDraft
    var address: AddressDraft
    var offers: [OfferDraft]
}
```

Vive somente em memória do `ProviderRegistrationViewModel`; nunca contém `providerID`/`userID`.

### CompanyDraft

```swift
struct CompanyDraft {
    var name: String = ""
    var description: String = ""
    var email: String            // baseline inicial: AccountSnapshot.authEmail
    var phone: String = ""
    var cnpj: String = ""
}
```

### AddressDraft

```swift
struct AddressDraft {
    var street: String = ""
    var number: String = ""
    var neighborhood: String = ""
    var postalCode: String = ""
    var city: String = ""
    var state: BrazilianState?
    var complement: String = ""
    var latitude: String = ""
    var longitude: String = ""
    // país não é editável; o comando sempre contém "BR"
}
```

### OfferDraft

```swift
struct OfferDraft: Identifiable {
    let id = UUID()          // localID estável apenas para UI/erro/foco — nunca reindexado
    var categoryID: UUID?
    var serviceID: UUID?
    var isFree: Bool = false
    var priceInput: String = ""
    var durationInput: String = ""
    var description: String = ""
}
```

Regras de edição (idênticas ao Android):

- mudar `categoryID` limpa `serviceID`;
- marcar `isFree` desabilita o campo visual de preço e produz preço zero;
- remover uma oferta não afeta o `id` das demais (identidade estável de `struct Identifiable`);
- a lista pode ficar vazia durante a edição, mas não pode ser confirmada vazia;
- nenhum limite de quantidade é aplicado pelo app;
- o mesmo `serviceID` não pode aparecer em duas ofertas.

### ProviderRegistrationCommand

Resultado imutável da validação local — passado ao Repository:

```swift
struct ProviderRegistrationCommand {
    let company: NormalizedCompany   // name, description?, email (lowercase), phone (dígitos), cnpj (maiúsculo)
    let address: NormalizedAddress   // strings trimmed, state/country canônicos, latitude/longitude: Decimal? pareados
    let offers: [NormalizedOffer]    // serviceID, price: Decimal, durationMinutes: Int, description?, isFree
}
```

Nenhum ID de owner, provider, endereço ou categoria é incluído.

### ProviderSummary

```swift
struct ProviderSummary {
    let provider: Provider
    let address: Address
    let offers: [ProviderOfferSummary]
}

struct ProviderOfferSummary {
    let serviceName: String
    let categoryName: String
    let price: Decimal
    let durationMinutes: Int
    let description: String?
    // IDs internos permanecem no data layer, não na struct de apresentação
}
```

A UI nunca mostra CNPJ completo; usa forma mascarada (mesma máscara visual do formulário, aplicada
somente à exibição).

## Tipos de estado

### Estado raiz

```swift
enum ProviderRegistrationUiState {
    case loading
    case startupFailure(reason: ProviderStartupFailureReason)
    case editing(EditingContent)
    case alreadyRegistered(ProviderSummary)
    case success(ProviderSummary)
    case sessionExpired
}

struct EditingContent {
    var draft: ProviderRegistrationDraft
    var categories: LoadState<[ServiceCategory]>
    var servicesByCategory: [UUID: LoadState<[CatalogService]>]   // chave: categoryID
    var fieldErrors: [ProviderField: ProviderFieldError]
    var focusRequest: FocusRequest?    // contador monotônico
    var submission: EditingSubmission
}

enum LoadState<T> { case loading, empty, content(T), failure(reason: String) }
enum EditingSubmission { case idle, submitting, failure(reason: ProviderFailureReason) }
```

Campos de oferta em erro são identificados por `ProviderField.offer(localID: UUID, field:
OfferField)`, nunca por índice — assim remoção/reordenação não move erro ou foco para outra oferta.

## Transições

| Origem | Evento | Destino | Observação |
|---|---|---|---|
| `.loading` | provider completo encontrado | `.alreadyRegistered` | nenhum rascunho é criado |
| `.loading` | provider ausente + catálogo responde | `.editing` | e-mail recebe `authEmail`, primeira oferta vazia |
| `.loading` | catálogo vazio/falha | `.editing` | `LoadState` explícito; formulário editável, submit bloqueado |
| `.loading` | falha própria | `.startupFailure` | oferece retry |
| `.editing` | editar/adicionar/remover | `.editing` | limpa apenas erros afetados |
| `.editing` | selecionar categoria | `.editing` | limpa serviço e carrega/cacheia lista da categoria |
| `.editing` | submit inválido | `.editing` | todos os erros + foco no primeiro em ordem visual |
| `.editing`/falha | submit válido | `.editing(.submitting)` | controles e Voltar destrutivo bloqueados |
| submitting | `CREATED` | `.success` | rascunho é removido da memória |
| submitting | `ALREADY_REGISTERED` | `.alreadyRegistered` | cobre corrida e resposta perdida |
| submitting | conflito conhecido | `.editing` | preserva rascunho e marca e-mail/CNPJ/oferta |
| submitting | offline/timeout/5xx | `.editing(.failure)` | preserva rascunho em memória e permite retry |
| qualquer estado | sessão ausente/trocada | `.sessionExpired` | cancela `Task`s e zera rascunho/cache/PII |

Resultados assíncronos só podem atualizar a View se o `userID` observado ainda for o mesmo capturado
no bootstrap (mesma guarda de `006`).

## Ordem de validação e foco

1. nome, e-mail, telefone, CNPJ e descrição;
2. CEP, rua, número, complemento, bairro, cidade, UF, latitude e longitude;
3. existência de ao menos uma oferta;
4. para cada oferta na ordem visual: categoria, serviço, gratuidade/preço, duração e descrição;
5. duplicidade de serviço entre ofertas.

A descrição opcional não gera erro quando vazia. Categoria/serviço removidos do catálogo geram
`.unavailable`, não aceitam texto livre e precisam de nova seleção.

## Invariantes de segurança

- owner é sempre `auth.uid()` no PostgreSQL;
- nenhum comando contém owner/provider ID;
- CNPJ, payload, IDs internos e `Error` bruto não são registrados;
- o rascunho não usa `UserDefaults`, `SwiftData` ou arquivo;
- troca/expiração de sessão limpa imediatamente o estado visível;
- DML direto pelo papel `authenticated` permanece revogado; somente a RPC cria o agregado.
