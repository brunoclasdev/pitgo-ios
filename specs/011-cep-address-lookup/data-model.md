# Data Model: Busca de endereço por CEP (iOS)

## Visão geral

A feature não cria entidade persistida. Ela acrescenta uma tentativa de consulta ao estado em
memória do cadastro empresarial (`007`/`009`) e aplica um resultado validado ao `AddressDraft`
existente. Consulta de CEP e verificação/geocodificação (`009`) são processos diferentes:

```text
CEP digitado ── Buscar CEP ──> PostalCodeLookupState
                                      │
                                      └── .found ──> AddressDraft editável
                                                           │
                                                           └── fluxo existente de verificação e cadastro
```

## Modelos do domínio de consulta

### PostalAddressResult

Resultado canônico aceito do ViaCEP.

```swift
struct PostalAddressResult {
    let postalCode: String       // exatamente 8 dígitos; igual ao CEP solicitado
    let street: String?          // trim; vazio vira nil
    let complement: String?      // trim; vazio vira nil
    let neighborhood: String?    // trim; vazio vira nil
    let city: String             // trim, obrigatório e não vazio
    let state: BrazilianState    // uma das 27 UFs (enum de 007/009)
}
```

Campos administrativos retornados pelo serviço não pertencem ao modelo.

### PostalCodeLookupResult

Resultado fechado produzido pelo Repository:

```swift
enum PostalCodeLookupResult {
    case found(PostalAddressResult)
    case notFound
    case failure(PostalCodeLookupFailure)
}

enum PostalCodeLookupFailure {
    case offline, timeout, serviceUnavailable, unexpectedResponse
}
```

Nenhum `Error` bruto, status, URL ou corpo é armazenado no estado de UI.

### PostalCodeLookupState

Estado renderizável dentro de `EditingContent`:

```swift
enum PostalCodeLookupState {
    case idle
    case loading(attemptID: UInt64, postalCode: String)
    case found(attemptID: UInt64, postalCode: String, appliedFields: Set<CepAddressField>)
    case notFound(attemptID: UInt64, postalCode: String)
    case failure(attemptID: UInt64, postalCode: String, reason: PostalCodeLookupFailure)
}
```

Regras: `attemptID` é monotônico durante a vida do ViewModel; apenas uma tentativa pode estar
`.loading`; estado/resultados só são válidos para o CEP armazenado no próprio estado; `.failure` é
recuperável e não invalida o CEP; `.notFound` cria erro do campo para o mesmo CEP; `appliedFields`
registra quais campos realmente receberam valor não vazio.

### CepAddressField e CepAutofillProvenance

```swift
enum CepAddressField { case street, complement, neighborhood, city, state }

struct CepAutofillProvenance {
    let postalCode: String
    let fields: Set<CepAddressField>
}
```

`CepAutofillProvenance` relaciona o CEP resolvido ao conjunto de campos preenchidos pela resposta. O
conjunto continua associado ao CEP mesmo que a pessoa corrija um dos valores, para que a troca de
CEP não carregue dados do endereço anterior. Campos nunca retornados pelo serviço permanecem
manuais e não são limpos pela proveniência.

## Extensão do estado do cadastro

`EditingContent` (`007`/`009`) passa a conter:

```swift
var postalCodeLookup: PostalCodeLookupState = .idle
var cepAutofillProvenance: CepAutofillProvenance?
// draft, catálogo, verificação, erros, foco e submissão permanecem como já definidos
```

`AddressDraft` não ganha duplicação de valores. Seus campos atuais são a única fonte para a View e
para a validação:

| Campo | Origem possível | Obrigatoriedade |
|---|---|---|
| `postalCode` | pessoa; normalizado para 8 dígitos | obrigatório |
| `street` | ViaCEP ou pessoa | obrigatório |
| `number` | somente pessoa | obrigatório |
| `complement` | ViaCEP ou pessoa | opcional |
| `neighborhood` | ViaCEP ou pessoa | obrigatório |
| `city` | ViaCEP ou pessoa | obrigatório |
| `state` | ViaCEP ou `Picker` | obrigatório |

Latitude/longitude não são alteradas pela busca. Aplicar um resultado invalida o
`ProviderAddressVerificationState` (`009`) existente porque o endereço textual mudou.

## Erros de campo

`ProviderFieldError` (`007`) ganha `.postalCodeNotFound`. Os erros existentes continuam tipados.

Regras de exibição: CEP vazio → `.required`; CEP com quantidade inválida → `.invalidPostalCode`; CEP
sintaticamente válido e inexistente → `.postalCodeNotFound`; falha temporária pertence a
`PostalCodeLookupState.failure`, não ao mapa de campos; campo obrigatório vazio → `.required` junto
ao próprio controle; formato/seleção/tamanho/indisponibilidade usam razões distintas; `.textTooLong`
é exibido com o limite específico do campo.

## Transições

| Origem | Evento | Destino | Efeito no draft |
|---|---|---|---|
| idle/found/notFound/failure | `Buscar CEP` válido | loading | nenhum |
| qualquer estado | `Buscar CEP` inválido | estado atual/idle | sem rede; erro e foco no CEP |
| loading | mesmo botão novamente | loading | no-op |
| loading | found compatível | found | aplica 5 campos presentes; nunca altera número |
| loading | `erro=true` | notFound | nenhum; marca CEP não encontrado |
| loading | falha temporária | failure | nenhum; preserva todos os dados |
| loading | resposta incompatível | failure(.unexpectedResponse) | nenhum |
| loading | CEP ou campo derivável editado | idle | cancela/invalida tentativa; preserva edição atual |
| found | CEP alterado | idle | limpa campos da proveniência; preserva número e campos manuais |
| notFound | CEP alterado | idle | remove erro não encontrado |
| failure | retry | loading com novo `attemptID` | preserva CEP e draft |
| qualquer estado | início do submit | não loading | não admite consulta ativa |
| qualquer estado | sessão perdida/trocada | estado raiz `.sessionExpired` (`006`) | cancela `Task` e remove rascunho da UI |

Uma resposta só pode realizar a transição se `attemptID`, CEP capturado, estado `.loading` e CEP
atual forem simultaneamente iguais — impede aplicação tardia inclusive no ciclo A → B → A.

## Aplicação atômica do resultado

Para cada valor não vazio retornado: (1) normalizar/validar a resposta completa; (2) copiar todos os
valores aceitos numa única atualização do `@Observable` state; (3) registrar os campos aplicados em
`CepAutofillProvenance`; (4) remover somente erros que ficaram válidos após a atualização; (5)
invalidar a verificação/geocodificação anterior; (6) focar o primeiro campo obrigatório ainda vazio
ou, se completo, o número. Se qualquer invariante da resposta falhar, nenhum campo é alterado.

## Validação e foco do formulário

Ordem canônica de validação (idêntica à do Android): modalidade → nome → descrição (só limite) →
e-mail → telefone → CNPJ → CEP → rua → número → complemento (só limite) → bairro → cidade → UF →
verificação existente, quando aplicável → existência de oferta → campos de cada oferta na ordem
visual.

No primeiro submit inválido, todos os erros são gravados. Depois disso, editar um campo revalida
somente ele: o erro é substituído ou removido apenas quando a entrada se torna válida. A View deriva
o índice do foco da mesma lista ordenada de linhas que renderiza (`ForEach` sobre um array de
identificadores de linha), rola via `ScrollViewReader`, aguarda a renderização e então solicita foco
via `@FocusState`.

## Lifecycle, segurança e privacidade

- rascunho, tentativa e proveniência ficam somente no ViewModel do destino;
- recriação de View não reinicia a chamada (estado vive no `@Observable` ViewModel);
- não há `UserDefaults`, `SwiftData` ou cache em disco para o rascunho/tentativa;
- a consulta transmite somente o CEP na URL HTTPS;
- não há headers Supabase, cookies, CNPJ, e-mail, número ou endereço parcial;
- CEP, URL, resposta e `Error` bruto não são registrados;
- a consulta não cria nem altera registro no Supabase.
