# Contract: Supabase — cadastro de empresa prestadora (shared backend)

## Status: already implemented and deployed

Este contrato descreve o schema e a RPC **já criados e conciliados** pela feature Android
equivalente (`supabase/migrations/20260820000000_provider_registration.sql`), no mesmo projeto
Supabase compartilhado. Nenhuma migration nova é criada por esta feature iOS (ver
[research.md §0](../research.md)). Documento existe para que
`ProviderRegistrationRepository` seja implementado contra o contrato exato já ativo.

## Escopo

Leituras autenticadas do catálogo/agregado próprio e a única mutação usada pela feature. Não
autoriza criação/edição de categoria/serviço, edição posterior da empresa, múltiplos endereços ou
escrita direta nas tabelas — em nenhuma plataforma.

## Pré-condições de schema (inalteradas, já aplicadas)

- `providers.id` é UUID PK/FK de `auth.users.id`; a RPC ainda exige profile ativo antes de criar o
  provider, então a regra "só empresa com profile" continua valendo sem a FK apontar para
  `profiles.id`;
- `addresses.provider_id` referencia `providers.id` e é único no cadastro inicial;
- `services.category_id` referencia `service_categories.id`;
- `service_categories` tem nome único case-insensitive e `services` tem nome único
  case-insensitive por categoria;
- `provider_services(provider_id, service_id)` é único;
- a coluna física de bairro é `addresses.neighbornhood` (grafia legada preservada
  deliberadamente — o Swift expõe `neighborhood` via `CodingKeys`, ver `data-model.md`);
- os validadores privados de telefone/CNPJ já existentes (compartilhados com `005`/`006`) são
  reutilizados pela RPC.

## Leituras

Todas exigem JWT autenticado e são paginadas até uma página menor que a página técnica.

### Categorias

Origem: `public.service_categories`. Resposta mínima: `id: UUID`, `name: String`, `description:
String?`. Ordenação estável: nome case-insensitive, depois ID. Lista vazia é `.empty`, não erro.

### Serviços por categoria

Origem: `public.services`, filtrada por `category_id`. Resposta mínima: `id: UUID`, `category_id:
UUID`, `name: String`, `description: String?`. O Repository rejeita qualquer registro cujo
`category_id` não seja o solicitado. Lista vazia é estado explícito. A feature não envia
nome/descrição de serviço ao salvar.

### Agregado próprio

O bootstrap consulta `providers` para o `id` derivado da sessão e, se existir, carrega exatamente um
provider, exatamente um endereço, uma ou mais associações `provider_services` e nomes de
serviço/categoria somente leitura. Zero provider significa que o formulário pode ser aberto.
Provider sem exatamente um endereço ou sem oferta é inconsistência de contrato e não deve ser
reparado silenciosamente pelo client.

## RPC de criação (inalterada)

### Assinatura

```sql
public.create_provider_registration(
  p_provider jsonb,
  p_address jsonb,
  p_offers jsonb
) returns jsonb
```

Chamada via `supabase-swift`:

```swift
let response: CreateProviderRegistrationResult = try await client
    .rpc("create_provider_registration", params: payload)
    .execute()
    .value
```

### Autorização (inalterada)

- `SECURITY DEFINER` com `SET search_path = ''`;
- `EXECUTE` revogado de `public` e `anon`, concedido somente a `authenticated`;
- relações e funções totalmente qualificadas;
- `auth.uid()` obrigatório e profile correspondente ativo;
- nenhum argumento de owner/provider/address/category.

### Payload

`p_provider` (`Encodable` Swift struct com `CodingKeys` `name`, `description`, `email`, `phone`,
`cnpj`):

```json
{
  "name": "Oficina Exemplo",
  "description": "Descrição comercial opcional",
  "email": "contato@example.com",
  "phone": "11999999999",
  "cnpj": "<CNPJ_NORMALIZADO>"
}
```

`p_address` (`neighborhood` do Swift serializado como `neighborhood` no JSON de payload — a RPC
já espera essa chave no argumento JSONB, distinta da coluna física `neighbornhood`; conferir
`contracts/supabase-provider-registration.md` original do Android para a chave exata usada pela
função):

```json
{
  "street": "Rua Exemplo",
  "number": "s/n",
  "neighborhood": "Centro",
  "zip_code": "01001000",
  "city": "São Paulo",
  "state": "SP",
  "country": "BR",
  "complement": null,
  "latitude": null,
  "longitude": null
}
```

`p_offers` é um array JSON não vazio e sem limite de produto:

```json
[
  {
    "service_id": "<SERVICE_UUID>",
    "price": "320.00",
    "duration_minutes": 90,
    "description": "Descrição comercial opcional",
    "is_free": false
  },
  {
    "service_id": "<OTHER_SERVICE_UUID>",
    "price": "0.00",
    "duration_minutes": 30,
    "description": null,
    "is_free": true
  }
]
```

`price` viaja como `String` decimal canônica (Swift `Decimal` formatado sem separador de milhar,
ponto decimal, até duas casas) para nunca passar por ponto flutuante binário. `is_free` valida a
escolha explícita, mas somente `price` é persistido. Categoria é derivada de `service_id`.

### Validação definitiva (inalterada, já aplicada no banco)

Antes do primeiro INSERT, a função: normaliza/valida provider e endereço; exige `p_offers` como
array com pelo menos um item; rejeita `service_id` repetido; valida todos os serviços e seus
vínculos de categoria ainda existentes; valida preço (escala ≤ 2 e `(is_free && price=0) ||
(!is_free && price>0)`); valida duração inteira entre 1 e 10.080; valida CEP/UF/país e o par de
coordenadas. Só depois insere provider, endereço e todas as ofertas. Qualquer exceção não tratada
reverte a execução inteira.

### Concorrência e idempotência (inalterada)

1. Adquire `pg_advisory_xact_lock` com namespace estável e `auth.uid()`.
2. Se não existe provider, valida e cria o agregado, retornando `CREATED`.
3. Se existe provider com exatamente um endereço e uma ou mais ofertas, não altera nada e retorna
   `ALREADY_REGISTERED`.
4. Se existe agregado parcial, retorna falha de contrato neutra.

Resposta fechada:

```json
{ "outcome": "CREATED", "offer_count": 2 }
```

```swift
struct CreateProviderRegistrationResult: Decodable {
    enum Outcome: String, Decodable { case created = "CREATED", alreadyRegistered = "ALREADY_REGISTERED" }
    let outcome: Outcome
    let offerCount: Int

    enum CodingKeys: String, CodingKey { case outcome, offerCount = "offer_count" }
}
```

`outcome` aceita somente `CREATED` ou `ALREADY_REGISTERED`. A resposta não retorna `provider_id`
(já é a conta autenticada). Depois da RPC, o Repository recarrega o agregado próprio antes de emitir
sucesso.

## RLS e grants (inalterados)

| Tabela | `anon` | `authenticated` | Policy SELECT |
|---|---|---|---|
| `providers` | nenhum | SELECT | `id = (select auth.uid())` |
| `addresses` | nenhum | SELECT | `provider_id = (select auth.uid())` |
| `provider_services` | nenhum | SELECT | `provider_id = (select auth.uid())` |
| `service_categories` | nenhum | SELECT | catálogo disponível |
| `services` | nenhum | SELECT | catálogo disponível |

Não há grant/policy de INSERT, UPDATE ou DELETE para o client nesta feature, em nenhuma plataforma.

## Resultado e falhas de domínio

| Sinal interno | Resultado do Repository (iOS) | Comportamento UI |
|---|---|---|
| `CREATED` + agregado confirmado | `.created(summary)` | confirmação/resumo |
| `ALREADY_REGISTERED` + agregado completo | `.alreadyRegistered(summary)` | resumo existente |
| timeout | `.timeout` | preservar rascunho e permitir retry |
| falha de transporte | `.offline` | preservar rascunho e permitir retry |
| HTTP 401/403 ou SQLSTATE `42501` | `.sessionExpired` | limpar estado e atualizar o gate |
| HTTP 5xx | `.serviceUnavailable` | mensagem neutra/retry |
| `23505` + `providers_email_unique` | `.emailUnavailable` | erro no e-mail |
| `23505` + `providers_cnpj_unique` | `.cnpjUnavailable` | erro no CNPJ |
| `23505` + provider/service UNIQUE | `.duplicateService` | erro na oferta |
| serviço/FK indisponível | `.catalogChanged` | recarregar catálogo/reselecionar |
| `22023`/`23514` | `.contract` | mensagem neutra, sem detalhe bruto |
| outro | `.unknown` | mensagem genérica |

O mapeamento pode inspecionar somente códigos e nomes allowlisted. Mensagem, `details`, headers,
payload e o `Error` completo nunca chegam à UI, log ou crash reporter.

## Operações explicitamente ausentes

- criação/edição de `service_categories` ou `services`;
- update/delete de provider/endereço/ofertas;
- geocodificação, CEP remoto ou localização;
- service-role, Edge Function ou segredo administrativo;
- uma RPC por oferta;
- persistência local do rascunho;
- qualquer migration nova neste repositório.
