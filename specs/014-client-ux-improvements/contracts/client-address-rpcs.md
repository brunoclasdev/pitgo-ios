# Contract: RPCs de endereço do cliente (shared backend, already implemented)

## Status: already implemented and deployed

`get_my_client_address`/`upsert_my_client_address` e a tabela `public.client_addresses` já existem
e estão aplicadas no projeto Supabase compartilhado com o Android (ver
[research.md §0](../research.md)). Nenhuma migration nova é criada por esta feature iOS.

## Regras comuns (inalteradas)

- `SECURITY DEFINER SET search_path = ''`, nomes totalmente qualificados, derivam o cliente de
  `auth.uid()` — nenhum parâmetro de identidade é aceito do client.
- `EXECUTE` revogado de `public`/`anon`, concedido somente a `authenticated` com
  `account_type = 'CLIENT'` (mesma verificação `private.has_account_type('CLIENT')`).
- `public.client_addresses` tem RLS habilitada e nenhum grant direto de tabela ao bundle iOS.
- Inputs de texto validados com as mesmas regras de `public.addresses` (trim, não vazio, limites de
  tamanho, CEP 8 dígitos, UF válida).

## Projeção comum

```json
{
  "outcome": "FOUND",
  "address": {
    "street": "Rua Exemplo", "number": "100", "neighborhood": "Centro",
    "zip_code": "01001000", "city": "São Paulo", "state": "SP", "country": "BR",
    "complement": null, "latitude": -23.55, "longitude": -46.63
  }
}
```

Outcomes fechados: `FOUND`, `NOT_FOUND` (nenhum endereço cadastrado — não é erro), `SAVED` (após
upsert), `INVALID_INPUT` (validação falhou, sem detalhe SQL). A UI iOS nunca interpreta texto livre.

### `get_my_client_address()`

```swift
let response: ClientAddressResponse = try await client.rpc("get_my_client_address").execute().value
```

Sem parâmetros. `.notFound` (sem `address`) é o estado hoje representado pelo texto neutro
"Endereço não cadastrado" na Home (`006`); a partir desta feature, esse texto passa a refletir o
resultado real desta RPC.

### `upsert_my_client_address(...)`

```swift
try await client.rpc("upsert_my_client_address", params: payload).execute()
```

Insere ou atualiza a única linha do cliente. `p_latitude`/`p_longitude` são opcionais e, quando
fornecidos, DEVEM vir da busca de CEP/geocodificação já usada no formulário (`011`) — não de
digitação livre. Retorna o endereço salvo no mesmo formato de `get_my_client_address`.

## Autorização (inalterada)

Nenhuma outra conta (`PROVIDER`, outro `CLIENT`, `anon`) pode ler ou escrever o endereço de um
cliente diferente do autenticado. O provider **não** recebe este dado por nenhuma via — a posição
usada no mapa do provider (US3) vem da leitura pontual de GPS do cliente durante o atendimento (ver
`contracts/client-location-rpcs.md`), não deste cadastro.
