# Contract: Supabase Auth, profiles e vehicles (shared backend)

## Status: already implemented and deployed

Este contrato descreve o schema e as RPCs **já criados e conciliados** pela feature Android
equivalente (`supabase/migrations/20260819010000_auth_session_vehicles.sql`), no mesmo projeto
Supabase compartilhado. Nenhuma migration nova é criada por esta feature iOS (ver
[research.md §0](../research.md)). Este documento existe para que o `SessionStore`/`AccountRepository`/
`VehicleRepository` iOS sejam implementados contra o contrato exato já ativo, incluindo os nomes de
RPC e de constraint usados na allowlist de sanitização de erros.

## Purpose

Definir a fronteira entre o app iOS, Supabase Auth e o schema público. A implementação usa somente a
publishable/anon key já configurada (`004-configure-supabase`); nenhuma operação depende de
service-role no bundle iOS.

## Auth contract

### Required project settings (shared, already satisfied)

- provedor Email habilitado;
- criação de usuário habilitada;
- confirmação de e-mail desabilitada, para que cadastro/login resultem em sessão imediata;
- senha mínima de oito caracteres;
- trigger de perfil instalado e funcionando (ver `005-create-user-account/contracts/profiles-schema.md`).

### Operations (equivalente Swift)

| Operation | supabase-swift call | Success | Domain failures |
|---|---|---|---|
| initialize | `client.auth.session` / `authStateChanges` | estado local carregado, depois verificado remotamente quando presente | offline, sessão inválida |
| sign in | `client.auth.signIn(email:password:)` | sessão do SDK importada, identidade verificada | credenciais inválidas, rate limit, offline, timeout, serviço |
| validate | sessão atual do SDK | usuário Auth atual retornado | inválida/revogada, offline, timeout |
| sign out | `client.auth.signOut(scope: .local)` | sessão local removida e estado do app limpo | falha remota não retém UI privada local |

O app nunca deve logar o `Error` do Auth, headers de request, URL contendo credenciais, access
token, refresh token, senha ou resposta bruta. O mapeamento pode inspecionar somente a classe/código
estável da exceção, status HTTP e código de erro Auth allowlisted.

## `public.profiles`

### Required projection

| Column | PostgreSQL type | Swift | Contract |
|---|---|---|---|
| `id` | `uuid` | `UUID` | PK/FK para `auth.users.id` |
| `name` | `text` | `String` | obrigatório para um perfil autorizado |
| `email` | `text` | `String` | normalizado, deve casar com o e-mail do Auth |
| `phone` | `text` | `String` | obrigatório para um perfil autorizado |
| `cpf` | `text` nullable | `String?` | XOR com CNPJ |
| `cnpj` | `text` nullable | `String?` | XOR com CPF |
| `avatar_url` | `text` nullable | `URL?` | avatar HTTPS opcional |
| `active` | `boolean` | `Bool` | somente `true` autoriza a Home |

A coluna canônica de status é exatamente `active`; `activity` e `activty` são aliases proibidos.
Colunas `created_at`/`updated_at` existentes podem permanecer, mas não são exigidas pela projeção
iOS.

### Read

```text
table: profiles
filter: id == id do usuário Auth atual
limit: 1
```

Classificação do resultado:

- nenhuma linha → `ProfileBlockedReason.missing`;
- linha com `active = false` → `.inactive`;
- dado obrigatório nulo/vazio, ID/e-mail divergente ou XOR de documento inválido → `.inconsistent`;
- linha válida → porção de perfil do `AccountSnapshot`.

### Write

O client iOS não faz INSERT/UPDATE de perfil nesta feature. A metadata do cadastro é consumida por
exatamente um trigger de banco (já existente). Retry apenas lê novamente; nunca faz upsert, recria
ou reativa.

### Trigger invariant (inalterado)

- exatamente um trigger `AFTER INSERT ON auth.users` cria o perfil;
- função `SECURITY DEFINER SET search_path = ''`, totalmente qualificada;
- chaves de metadata são exatamente `name`, `phone`, `cpf`, `cnpj`;
- e-mail vem de `new.email`, status do default `active = true` do banco;
- trigger/função não é executável diretamente por `public`, `anon` ou `authenticated`.

## `public.vehicles`

### Table projection

| Column | Type | Nullable | Writer |
|---|---|---:|---|
| `id` | `uuid` | não | default do banco |
| `user_id` | `uuid` | não | RPC a partir de `auth.uid()` |
| `brand` | `text` | não | RPC |
| `model` | `text` | não | RPC |
| `version` | `text` | sim | RPC |
| `manufacture_year` | `integer` | sim | RPC |
| `model_year` | `integer` | sim | RPC |
| `plate` | `text` | sim | RPC, canônica maiúscula de sete caracteres |
| `renavam` | `text` | sim | RPC, 11 dígitos |
| `chassis` | `text` | sim | RPC, VIN maiúsculo 17 |
| `color` | `text` | sim | RPC |
| `fuel_type` | `text` | sim | RPC |
| `transmission` | `text` | sim | RPC |
| `engine` | `text` | sim | RPC |
| `mileage` | `integer` | sim | RPC, não negativo |
| `is_primary` | `boolean` | não | somente RPC |
| `active` | `boolean` | não | banco/RPC, `true` na criação |
| `created_at` | `timestamptz` | não | default do banco |
| `updated_at` | `timestamptz` | não | banco/RPC |

### Read list

```text
table: vehicles
filters:
  user_id == id do usuário Auth atual
  active == true
order:
  is_primary descending
  created_at ascending
maximum expected result: 100 rows
```

O filtro explícito de `user_id` é exigido mesmo com RLS. O bootstrap de perfil pode adicionalmente
consultar `is_primary == true` com `limit(1)`.

### Required indexes/constraints (inalterados, já aplicados)

- PK `vehicles_pkey` em `id`;
- FK `user_id -> profiles(id) ON DELETE CASCADE`;
- unique não nula de placa canônica: `vehicles_plate_unique`;
- unique não nula de Renavam: `vehicles_renavam_unique`;
- unique não nula de chassi canônico: `vehicles_chassis_unique`;
- unique parcial de principal por usuário: `one_primary_vehicle_per_user`;
- `is_primary` implica `active`;
- marca/modelo não vazios após trim;
- quilometragem ≥ 0;
- ano ≥ 1900; limite superior é aplicado no momento da operação como o próximo ano civil;
- checks de representação de placa/Renavam/chassi conforme o data model.

## RPC `create_vehicle`

### Signature (inalterada)

```text
public.create_vehicle(
  p_brand text,
  p_model text,
  p_version text,
  p_manufacture_year integer,
  p_model_year integer,
  p_plate text,
  p_renavam text,
  p_chassis text,
  p_color text,
  p_fuel_type text,
  p_transmission text,
  p_engine text,
  p_mileage integer,
  p_make_primary boolean
) returns setof public.vehicles
```

Chamada via `supabase-swift`:

```swift
try await client.rpc("create_vehicle", params: params).execute()
```

Todas as chaves são enviadas em um único objeto JSON (`Encodable` struct com `CodingKeys`
`p_brand`, `p_model`, ...); opcionais ausentes são `null`. Nenhum parâmetro `user_id`, `active`,
`is_primary`, ID ou timestamp é aceito.

### Transactional behavior (inalterado)

1. exige `auth.uid()` não nulo e um perfil ativo correspondente;
2. adquire advisory lock com escopo de transação derivado desse UUID;
3. normaliza e valida todas as entradas;
4. determina se já existe algum veículo ativo;
5. se for o primeiro ou `p_make_primary = true`, limpa qualquer principal anterior do usuário;
6. insere um único veículo ativo, principal quando primeiro/solicitado;
7. retorna exatamente a linha inserida;
8. qualquer falha reverte todo update/insert.

## RPC `set_primary_vehicle`

### Signature (inalterada)

```text
public.set_primary_vehicle(
  p_vehicle_id uuid
) returns setof public.vehicles
```

### Transactional behavior (inalterado)

1. exige `auth.uid()` não nulo;
2. adquire o mesmo lock de transação por usuário;
3. localiza um alvo ativo cujo `user_id = auth.uid()`;
4. se não existir, retorna uma falha neutra de não encontrado/não autorizado;
5. limpa todo principal anterior desse usuário;
6. marca somente o alvo como principal e atualiza seu `updated_at`;
7. retorna exatamente a linha alvo;
8. qualquer falha reverte todas as mudanças.

## Function security (inalterada)

Ambas as RPCs:

- são `SECURITY DEFINER SET search_path = ''` porque escritas diretas são intencionalmente
  revogadas;
- qualificam totalmente `auth.uid`, `public.profiles`, `public.vehicles` e outros objetos;
- não aceitam campos de owner/status;
- revogam EXECUTE de `public` e `anon`;
- concedem EXECUTE somente a `authenticated`;
- devem ser revisadas sempre que o contrato de tabela mudar — em qualquer repositório, Android ou
  iOS, pois o schema é único.

## Grants and RLS (inalterados)

| Object | anon | authenticated |
|---|---|---|
| `profiles` | nenhum | somente SELECT |
| `vehicles` | nenhum | somente SELECT |
| `create_vehicle` | sem EXECUTE | EXECUTE |
| `set_primary_vehicle` | sem EXECUTE | EXECUTE |

Policies:

- SELECT de perfil: `(select auth.uid()) = id`;
- SELECT de veículo: `(select auth.uid()) = user_id`;
- RLS habilitada em ambas as tabelas;
- políticas antigas de INSERT/UPDATE/DELETE podem ter sido removidas; em todo caso, os grants
  diretos de DML permanecem revogados.

## Error mapping

| Source | Stable discriminator | iOS result |
|---|---|---|
| Auth | código/401 de credenciais inválidas | login inválido; limpa senha |
| Auth/PostgREST | `URLError`/exceção de rede | offline |
| Auth/PostgREST | timeout | timeout/serviço indisponível |
| Postgres | `23505` + token `vehicles_plate_unique` | placa indisponível |
| Postgres | `23505` + token `vehicles_renavam_unique` | Renavam indisponível |
| Postgres | `23505` + token `vehicles_chassis_unique` | chassi indisponível |
| Postgres | `23514`/`22023` | entrada de servidor inválida/falha de contrato |
| Postgres | `42501` ou resposta não autorizada | falha de sessão/permissão |
| Postgres | não encontrado neutro | veículo indisponível; não revela proprietário |
| any | 5xx | serviço indisponível |
| any | não reconhecido | falha genérica |

Somente os tokens de constraint allowlisted acima podem ser inspecionados. `message`, `details`,
headers de resposta, URL de request e o `Error` bruto nunca devem ser logados ou exibidos.

## Migration reconciliation (contexto, não uma tarefa desta feature)

A migration completa (Android) já reconcilia dois estados históricos conhecidos: um banco local
limpo contendo apenas a migration de perfil, e o projeto remoto com `profiles`/`vehicles`
criados manualmente pelo usuário antes desta feature existir. Ela preserva linhas, garante
`avatar_url`, converge para um único trigger seguro de perfil, converge índices/constraints/grants/
policies e instala as RPCs. O repositório iOS não reaplica nem reinterpreta essa reconciliação — ele
depende do resultado já convergido no projeto compartilhado.
