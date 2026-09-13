# Contract: Supabase account, provider and discovery database (shared backend)

## Status: already implemented and deployed

Este contrato descreve o schema/RPCs **já criados e conciliados** pela feature Android equivalente,
no mesmo projeto Supabase compartilhado. Nenhuma migration nova é criada por esta feature iOS (ver
[research.md §0](../research.md)). Android deve depender de outcomes fechados, nunca de mensagens
PostgreSQL brutas — a mesma regra vale para o client iOS.

## Authoritative account context

`get_my_account_context() -> jsonb`, executável por `authenticated`. Chamada via `supabase-swift`:

```swift
let context: AccountContext = try await client.rpc("get_my_account_context").execute().value
```

Success shape:

```json
{
  "account_type": "CLIENT",
  "client_state": "READY",
  "provider_state": null,
  "provider_id": null,
  "legacy_provider_migration_available": true
}
```

`provider_state` é `ONBOARDING`, `READY` ou `INCOMPLETE`. Exatamente um contexto é retornado. Papel
ausente, linhas contraditórias ou sessão não autorizada usam outcomes/SQLSTATE estáveis e nunca caem
para outro papel.

## Signup gate (inalterado, backend-only)

`private.validate_account_signup(jsonb)` é o Before User Created Auth Hook — aceita somente
`raw_user_meta_data.account_type` igual a `CLIENT` ou `PROVIDER`, vindo de
`client.auth.signUp(email:password:data:)` no client iOS (mesmo payload conceitual do Kotlin).

`private.handle_new_user_account()` é o trigger `AFTER INSERT auth.users` — revalida o tipo, insere
`account_roles` imutável, insere perfil somente para CLIENT, não insere provider/perfil para
PROVIDER. Grants de execução restritos a `supabase_auth_admin`/owner do trigger; `anon`/
`authenticated` não podem executar os helpers nem mutar papéis.

## Provider registration (inalterado)

```text
create_provider_registration(
  p_provider jsonb,
  p_offers jsonb,
  p_geocode_verification_id uuid,
  p_divergence_confirmed boolean
) -> jsonb
```

Chamada via `supabase-swift`:

```swift
let result: CreateProviderRegistrationResult = try await client
    .rpc("create_provider_registration", params: payload)
    .execute()
    .value
```

Owner deriva de `auth.uid()`; nenhum ID de owner/provider/categoria é aceito. `p_provider` contém
dados normalizados da empresa e `location_mode`. `p_offers` contém UUID de serviço, preço, duração,
descrição e flag de gratuidade. Texto/ponto do endereço vêm da prova de geocodificação travada.

Outcomes fechados: `CREATED {provider_id, offer_count}`; `ALREADY_REGISTERED {provider_id,
offer_count}` (retry idempotente); códigos de erro de domínio `GEOCODE_EXPIRED`,
`DIVERGENCE_CONFIRMATION_REQUIRED`, `CATALOG_CHANGED`, `EMAIL_UNAVAILABLE`, `CNPJ_UNAVAILABLE`,
`INVALID_INPUT`, `SESSION_BLOCKED`.

Toda validação de input/catálogo ocorre antes dos inserts. Uma transação insere Provider, Address,
`ProviderCategory`s distintas e `ProviderService`s. Advisory lock na UUID da conta + unique
constraints previnem duplicidade concorrente. Um cadastro completo existente não é sobrescrito.

## Provider settings (inalterado)

`set_my_provider_mode(p_mode)` e `set_my_provider_availability(p_available)` derivam o provider da
conta PROVIDER autenticada. Mudar para FIXED ou indisponível apaga a localização corrente na mesma
transação. Retornam um snapshot sanitizado de Provider.

## Legacy ownership transfer (inalterado)

```text
begin_provider_ownership_migration(p_token text) ->
  {outcome:PENDING, expires_at, requirements}

claim_provider_ownership_migration(
  p_token text,
  p_location_mode text,
  p_geocode_verification_id uuid?,
  p_divergence_confirmed boolean
) -> {outcome:MIGRATED|ALREADY_MIGRATED, provider_id}
```

`begin` exige owner CLIENT de um Provider legado. `claim` exige uma conta PROVIDER de e-mail
diferente sem outro Provider, trava transferência/provider/origem/destino, valida
completude/localização e atualiza somente `providers.account_id` mais a auditoria de transferência.
Retry com o mesmo destino é idempotente. Token expirado, reivindicante diferente ou origem alterada
retornam falha neutra.

## Catalog (inalterado)

Leituras de catálogo retornam somente categorias e serviços ativos. Paginação continua até uma
página curta; nenhum máximo de produto é imposto. Seleções do provider são revalidadas no submit.

`list_home_services()` retorna UUID real de serviço, UUID/nome de categoria, nome/descrição do
serviço e preço mínimo de oferta ativa opcional. Não expõe dados de Provider.

## Discovery (inalterado)

```text
discover_service_providers(
  p_service_id uuid,
  p_center_lat double precision,
  p_center_long double precision,
  p_radius_meters integer,
  p_limit integer
) -> setof ServiceMapResult
```

Regras: caller deve ser CLIENT; centro em WGS84; raio 1..200000 m; limite 1..200; serviço/categoria
ativos exatos e tanto `ProviderService` quanto `ProviderCategory` devem casar; owner do Provider tem
papel PROVIDER, ativo e disponível; geocode do endereço verificado e não expirado; FIXED e MOBILE
retornam ambos o endereço empresarial; ordenação por `ST_Distance`, usa `ST_DWithin`/GiST; retorna
somente a projeção de `data-model.md`.

## RLS and grants matrix (inalterado)

| Resource | CLIENT | PROVIDER | anon |
|---|---|---|---|
| próprio perfil/veículos | próprio SELECT/RPC | nenhum | nenhum |
| próprio provider/endereço/categorias/serviços | nenhum, exceto início de migração | próprio SELECT/RPC | nenhum |
| catálogo ativo | SELECT | SELECT | nenhum |
| tabelas de discovery | sem SELECT direto; projeção via RPC | sem SELECT cross-owner | nenhum |
| `account_roles` | apenas próprio contexto | apenas próprio contexto | nenhum |
| provas/transferências privadas | somente RPC | somente RPC | nenhum |

Toda função crítica usa `SECURITY DEFINER SET search_path=''`, objetos totalmente qualificados,
execução de `public`/`anon` revogada e grant explícito a `authenticated`. O bundle iOS nunca contém
service-role — mesma garantia do APK Android.

## Migration reconciliation (contexto, não uma tarefa desta feature)

A reconciliação (backfill de `CLIENT`, desacoplamento de `providers.id`/`account_id`, marcação de
registros legados, novo trigger de perfil, campos geoespaciais, políticas revisadas) já foi feita
pela migration Android. O repositório iOS não reaplica nem reinterpreta essa reconciliação — depende
do resultado já convergido no projeto compartilhado.
