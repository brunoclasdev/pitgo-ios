# Contract: Vehicle RPCs (shared backend, already restored)

## Status: already implemented and deployed

Este contrato descreve as RPCs **já restauradas** pela feature Android equivalente
(`supabase/migrations/20260823000000_restore_vehicle_rpcs.sql`, já aplicada no projeto compartilhado).
Nenhuma migration nova é criada por esta feature iOS (ver [research.md §0](../research.md)).

## Fronteira de acesso (inalterada)

- Transporte: Supabase PostgREST RPC autenticada, chamada via `client.rpc(...)` do `supabase-swift`.
- Papel aceito: `authenticated` com `account_roles.account_type = 'CLIENT'` e profile ativo.
- Ownership: sempre `auth.uid()`; nenhum parâmetro de owner é aceito.
- Tabelas continuam com RLS habilitado e sem DML direto concedido ao bundle iOS.
- Funções: `SECURITY DEFINER SET search_path = ''`, relações totalmente qualificadas.
- `EXECUTE`: revogado de `public` e `anon`; concedido somente a `authenticated`.

## `create_vehicle` (assinatura inalterada)

```text
create_vehicle(
  p_brand text, p_model text, p_version text,
  p_manufacture_year integer, p_model_year integer,
  p_plate text, p_renavam text, p_chassis text,
  p_color text, p_fuel_type text, p_transmission text, p_engine text,
  p_mileage integer, p_make_primary boolean
) -> exatamente uma linha public.vehicles
```

Comportamento (inalterado): confere sessão/papel CLIENT/profile ativo; adquire lock transacional por
`auth.uid()`; normaliza e valida todos os parâmetros; determina
`is_primary = p_make_primary OR nenhum veículo ativo existente`; desmarca o principal anterior se
necessário; insere com `user_id = auth.uid()`, `active = true`, opcionais vazios como `null`; retorna
a linha criada; qualquer erro reverte toda a operação.

O client iOS envia exatamente os nomes `p_*` acima (`Encodable` struct com `CodingKeys`) e decodifica
com `.execute().value` como `Vehicle` único.

## `set_primary_vehicle` (assinatura inalterada)

```text
set_primary_vehicle(p_vehicle_id uuid) -> exatamente uma linha public.vehicles
```

Comportamento (inalterado): confere sessão/papel/profile; adquire lock por `auth.uid()`; localiza e
bloqueia somente um veículo ativo do próprio usuário; se não existir, falha de forma neutra sem
revelar ownership/existência; desmarca outro principal e marca o alvo na mesma transação; retorna a
linha atualizada.

## Contrato de erros sanitizados (inalterado)

| Origem remota | Resultado de domínio (iOS) | Tratamento de UI |
|---|---|---|
| `P2001` | `.fieldFailure(.brand, .required)` | Marca |
| `P2002` | `.fieldFailure(.model, .required)` | Modelo |
| `P2003` | `.fieldFailure(.plate, .invalidFormat)` | Placa |
| `P2004` | `.fieldFailure(.renavam, .invalidFormat)` | Renavam |
| `P2005` | `.fieldFailure(.chassis, .invalidFormat)` | Chassi |
| `P2006` | `.fieldFailure(.manufactureYear, .outOfRange)` | Ano de fabricação |
| `P2007` | `.fieldFailure(.modelYear, .outOfRange)` | Ano do modelo |
| `P2008` | `.fieldFailure(.mileage, .outOfRange)` | Quilometragem |
| `P2011` | `.fieldFailure(.plate, .unavailable)` | Placa |
| `P2012` | `.fieldFailure(.renavam, .unavailable)` | Renavam |
| `P2013` | `.fieldFailure(.chassis, .unavailable)` | Chassi |
| `23505` não traduzido pela RPC | `.failure(.unknown)` | Aviso geral; nenhum campo marcado |
| `PGRST202`, `PGRST203`, `42883` ou função 404 incompatível | `.failure(.rpcUnavailable)` | Aviso geral temporariamente indisponível |
| HTTP 401/403 ou `42501` | `.failure(.sessionExpired)` | Refresh/gate de sessão |
| timeout | `.failure(.timeout)` | Aviso geral |
| falha de conexão | `.failure(.offline)` | Aviso geral |
| HTTP 5xx | `.failure(.serviceUnavailable)` | Aviso geral |
| `P0002` | `.failure(.vehicleUnavailable)` | Aviso neutro |
| qualquer resposta não permitida | `.failure(.unknown)` | Aviso geral |

Os códigos internos servem apenas ao mapeamento exato. A função converte as três violações únicas
esperadas para `P2011..P2013`, sem o detalhe padrão que conteria o valor. UI, logs e analytics do
app iOS nunca recebem SQLSTATE, constraint, `message`, `details`, `hint`, URL, payload ou o `Error`
bruto do `supabase-swift`.

## Invariantes de compatibilidade (inalteradas)

- Nome e tipos de todos os parâmetros permanecem idênticos ao DTO Swift (`CodingKeys` mapeando
  `p_*`).
- A resposta mantém as mesmas colunas de `Vehicle` (`006 data-model.md`).
- A migration foi aplicada de forma segura tanto quando a função não existia quanto quando existia
  numa versão anterior — irrelevante para o client, que apenas consome o contrato já restaurado.
