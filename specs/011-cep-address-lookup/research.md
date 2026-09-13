# Research: Busca de endereço por CEP (iOS)

## 1. Fronteira da integração

**Decision**: criar `ViaCepAddressLookupRepository` dentro da feature `ProviderRegistration`. Ele
possui uma única `URLSession` process-scoped (`URLSession(configuration: .ephemeral)` — sem cache de
disco, sem cookies compartilhados), sem autenticação, logging ou retry automático. O Repository de
cadastro Supabase (`007`/`009`) permanece inalterado.

**Rationale**: ViaCEP é uma fonte externa pública, diferente do Supabase. Um cliente dedicado evita
herdar headers de sessão e mantém o contrato de privacidade de transmitir somente o CEP.
`URLSession` é o cliente HTTP nativo do iOS — nenhum Swift Package é necessário para um único
endpoint GET/JSON, diferente do Android que reutiliza Ktor OkHttp já instalado.

**Alternatives considered**: reutilizar o cliente `supabase-swift` (rejeitado, mistura base
URL/contexto autenticado); Alamofire ou outro cliente HTTP de terceiros (rejeitado, `URLSession`
nativo já resolve um único GET sem dependência); Supabase Edge Function como proxy (rejeitado, cria
backend/operação sem necessidade atual); DataSource/Use Case/DTOs públicos separados (rejeitados,
um único endpoint não justifica novas camadas).

## 2. Dependências e decodificação

**Decision**: usar `URLSession.shared`-equivalente dedicado + `JSONDecoder` nativo (`Codable`). O
DTO fica `private` no mesmo arquivo do Repository. Como o ViaCEP retorna `erro` ora como `Bool` ora
como `String` (`"true"`), o `Decodable` implementa `init(from:)` customizado para aceitar ambas as
representações via `try? decoder.decode(Bool.self)` com fallback para `String`.

**Rationale**: `Codable`/`JSONDecoder` são nativos do Foundation — nenhuma dependência nova é
necessária (equivalente Swift ao `kotlinx.serialization` já usado no Android, mas sem precisar
adicionar nada ao projeto iOS, que já usa `Codable` desde `005`).

**Alternatives considered**: parser manual por strings/regex (rejeitado, frágil); aceitar campos
desconhecidos como erro de decodificação (rejeitado — a API retorna vários campos fora do escopo,
`JSONDecoder` já ignora chaves não mapeadas por padrão em `struct` `Decodable` comuns).

## 3. Contrato HTTP e validação da resposta

**Decision**: chamar apenas `GET https://viacep.com.br/ws/{cep}/json/`, com header `Accept:
application/json`, host fixo e exatamente oito dígitos no path. `URLSession` não segue redirect por
padrão de forma diferente do necessário aqui; o Repository inspeciona `HTTPURLResponse.statusCode`
e o corpo diretamente. Um resultado é aceito somente quando: `erro` não representa `true`; o CEP
retornado, normalizado, é igual ao solicitado; `localidade` não está vazia; `uf` pertence às 27
siglas brasileiras (mesma allowlist de `007`/`009`).

Rua, complemento e bairro podem vir vazios. `erro=true` é `.notFound`; resposta incompatível ou
malformada é `.unexpectedResponse`. Campos administrativos (unidade, região, IBGE, GIA, DDD, SIAFI)
são ignorados.

**Rationale**: idêntico ao racional do Android — a documentação oficial usa HTTP 200 com `erro=true`
para CEP válido inexistente; conferir CEP/cidade/UF impede que uma resposta parcial ou trocada
substitua o rascunho silenciosamente.

**Alternatives considered**: idênticas ao Android — confiar em todo HTTP 200 (rejeitado, CEP
inexistente também retorna 200); exigir rua e bairro (rejeitado, CEPs genéricos podem omiti-los).

## 4. Timeout e classificação de falhas

**Decision**: configurar `URLSessionConfiguration.timeoutIntervalForRequest = 2.5` e
`timeoutIntervalForResource = 2.5` (não há distinção nativa connect/socket tão granular quanto o
Ktor no `URLSessionConfiguration` padrão — o timeout de recurso cobre o equivalente). O Repository
relança `CancellationError` (Swift Concurrency) e mapeia o restante sem expor `Error`/corpo bruto:

| Sinal | Resultado de domínio |
|---|---|
| `URLError.timedOut` | `.timeout` |
| `URLError.notConnectedToInternet`/`.cannotFindHost`/`.cannotConnectToHost` | `.offline` |
| HTTP 429, 5xx | `.serviceUnavailable` |
| outro status/JSON/contrato inválido | `.unexpectedResponse` |

Não há retry automático — a tentativa seguinte é sempre uma ação explícita da pessoa (`Task` nova
disparada pelo botão).

**Rationale**: idêntico ao racional do Android — o teto de ~2,5s deixa margem para um resultado ou
mensagem antes dos 3 segundos do critério de sucesso; evitar retry automático reduz chamadas
duplicadas e respeita o alerta do ViaCEP contra uso massivo.

## 5. Estado, concorrência e lifecycle

**Decision**: adicionar `PostalCodeLookupState` imutável a `EditingContent` (`007`/`009`). O
ViewModel mantém uma única `Task<Void, Never>?` (`postalCodeLookupTask`) em vez do `Job` Kotlin.
Cada tentativa recebe um `attemptID` monotônico (`UInt64`, incrementado localmente) e o CEP
capturado no momento do disparo. O resultado só é aplicado se o estado ainda for `.loading` com o
mesmo `attemptID`/CEP e o rascunho ainda contiver esse CEP. Alterar o CEP, iniciar submissão ou
perder/trocar sessão cancela a `Task` (`.cancel()`) e invalida a geração (comparação de `attemptID`
descarta o resultado tardio mesmo que a `Task` não seja cancelada a tempo).

Toques repetidos durante `.loading` são ignorados (guarda síncrona antes de criar a `Task`). A
submissão final é desabilitada/guardada durante a consulta, e a consulta é desabilitada durante
`.submitting` — as duas máquinas de estado permanecem independentes.

**Rationale**: idêntico ao racional do Android — apenas cancelar a `Task` não protege contra um
resultado já entregue (a `Task` pode terminar entre a checagem de cancelamento e a escrita do
estado); o par `attemptID`+CEP evita preenchimento tardio mesmo no ciclo A → B → A. O
`ProviderRegistrationViewModel` (`@Observable`) já sobrevive à recriação de View e não exige
persistência adicional.

**Alternatives considered**: idênticas ao Android — debounce/busca automática (rejeitado pela
clarificação da feature); persistir estado em `UserDefaults`/`SwiftData` (rejeitado, mesma razão do
Android — a necessidade é sobreviver à recriação de View com o destino vivo, não à reabertura do
app); múltiplas `Task`s concorrentes (rejeitadas por risco de overwrite e uso desnecessário da API).

## 6. Aplicação dos dados e proveniência

**Decision**: idêntico ao racional do Android — sucesso atualiza o `AddressDraft` atomicamente.
Valores não vazios de rua, complemento, bairro, cidade e UF substituem os respectivos campos e são
registrados em `CepAutofillProvenance`. Campos omitidos preservam o valor manual atual e não entram
na proveniência. Número nunca é alterado.

Se o CEP mudar após sucesso, os campos registrados como derivados são limpos e o número é
preservado. Toda aplicação ou edição relevante invalida a `ProviderAddressVerificationState` (`009`)
existente.

**Rationale**: idêntico ao Android — o conjunto por campo diferencia valor realmente fornecido pelo
ViaCEP de campo genérico preenchido manualmente.

## 7. Falhas recuperáveis e preenchimento manual

**Decision**: idêntico ao racional do Android — `.notFound` adiciona `.postalCodeNotFound` ao campo
CEP e bloqueia conclusão enquanto o valor não mudar. Offline, timeout, indisponibilidade e resposta
inesperada aparecem no `PostalCodeLookupState`, com retry, mas não marcam um CEP sintaticamente
válido como incorreto e não impedem conclusão manual quando o restante do formulário estiver válido.

## 8. Erros de formulário, foco e acessibilidade

**Decision**: estender a validação de `007`/`009` para: (1) validar na ordem visual, começando por
modalidade e seguindo todos os campos/ofertas; (2) após a primeira validação, revalidar somente o
campo editado e remover seu erro apenas quando ele ficar válido; (3) derivar o índice do primeiro
erro da mesma lista ordenada de linhas renderizada pela `List` SwiftUI (`ForEach` sobre um array
único de "linhas de formulário", não uma constante fixa de offset para ofertas), usando
`ScrollViewReader.scrollTo(id:)` seguido de `@FocusState` para o campo alvo. Textos de limite máximo
(`textTooLong`) passam a mostrar o limite específico do campo. Modalidade, grupos e seletores também
recebem erro visual, texto e semântica (`.accessibilityLabel` combinando rótulo + erro). O conjunto
CEP/botão usa `.accessibilityAddTraits(.updatesFrequently)` (Live Region); `TextField`s mantêm
indicação de erro visual + texto de apoio + `.accessibilityLabel` com o motivo.

**Rationale**: idêntico ao racional do Android — uma lista ordenada única mantém renderização e foco
alinhados mesmo com linhas condicionais (número variável de ofertas).

**Alternatives considered**: idênticas ao Android — validar tudo desde o início da digitação
(rejeitado, feedback prematuro); banner geral sem indicação por campo (rejeitado, não orienta);
offset fixo para o início das ofertas (rejeitado, frágil com linhas condicionais).
