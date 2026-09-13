# Contract: RPCs de despacho móvel (shared backend, already implemented)

## Status: already implemented and deployed

Todas as RPCs abaixo já existem e estão aplicadas no projeto Supabase compartilhado com o Android
(ver [research.md §0](../research.md)). Nenhuma migration nova é criada por esta feature iOS. Este
documento existe para que `MobileDispatchRepository` seja implementado contra o contrato exato já
ativo.

## Regras comuns (inalteradas)

- Todas as funções públicas são `SECURITY DEFINER SET search_path = ''`, totalmente qualificadas.
- `EXECUTE` revogado de `public`/`anon`, concedido somente a `authenticated`.
- Identidade, papel, client e provider são derivados de `auth.uid()`/`account_roles`; nenhum RPC
  aceita owner confiável do client.
- Toda função de estado reconcilia appointment `PENDING` vencido antes de responder.
- Exceções ficam reservadas a sessão/papel, input inválido e indisponibilidade; nunca devolvem
  coordenada alheia, CNPJ, contato ou detalhe SQL.

## Projeção comum

```json
{
  "outcome": "UPDATED",
  "server_now": "2026-08-23T18:00:00Z",
  "search_id": "uuid",
  "service_id": "uuid",
  "status": "OPTION_FOUND",
  "revision": 4,
  "radius_meters": 10000,
  "candidate": null,
  "appointment": null,
  "allowed_actions": ["NEXT", "REQUEST", "CANCEL"]
}
```

```swift
struct DispatchRpcResponse: Decodable {
    enum Outcome: String, Decodable {
        case updated = "UPDATED", activeSearchReturned = "ACTIVE_SEARCH_RETURNED"
        case alreadyApplied = "ALREADY_APPLIED", staleRevision = "STALE_REVISION"
        case candidateInvalidated = "CANDIDATE_INVALIDATED", exhausted = "EXHAUSTED"
        case noActiveFlow = "NO_ACTIVE_FLOW"
    }
    let outcome: Outcome
    let snapshot: MobileDispatchSnapshot?
    // CodingKeys mapeiam os demais campos ao nível superior do JSON para MobileDispatchSnapshot
}
```

A UI nunca interpreta mensagem livre — somente o `enum Outcome` fechado.

## Publicação de discovery

### `publish_mobile_provider_location` (inalterada)

Inputs: latitude, longitude, `accuracy_m`, `captured_at`, `tracker_instance_id`,
`tracker_sequence`. Valida provider próprio ativo/`MOBILE`/disponível; precisão `<=100m`, captura
`<=30s`, no máximo `10s` no futuro. Um tracker novo não assume uma lease recente de outro. Update
antigo é ignorado; update aceito incrementa `version`. Quando existe appointment
`ACCEPTED`/`IN_PROGRESS`, o servidor projeta o fix somente no tracking privado (`009`) e não torna
o provider descobrível.

Chamada Swift (mesmo padrão de `publish_provider_location`, `009`):

```swift
try await client.rpc("publish_mobile_provider_location", params: payload).execute()
```

### `stop_mobile_provider_location` (inalterada)

Recebe apenas `tracker_instance_id`. Apaga a linha somente quando owner e tracker correspondem.

## Busca do cliente

### `start_mobile_dispatch` (inalterada)

Inputs: `p_search_id` (gerado uma vez no client — `UUID()` — e reutilizado após resposta perdida,
mesma chave idempotente do Android), `p_service_id`, latitude, longitude, precisão, `captured_at`.
Exige conta CLIENT e serviço `MOBILE_SEQUENTIAL` ativo; busca ativa do mesmo `(client, service)` é
retornada mesmo com outra chave; cria raio 10km e escolhe o primeiro candidato elegível na mesma
transação; expande 10→25→50km quando necessário; só então retorna `.exhausted`.

### `get_my_active_mobile_dispatch` (inalterada)

Sem owner/ID arbitrário. Para CLIENT retorna a busca não terminal mais recente; para PROVIDER
retorna a solicitação pendente ou o appointment reservado; caso contrário `.noActiveFlow`. Inclui
`server_now` e ações permitidas. Chamada no bootstrap (`DispatchResumeCoordinator`), no subscribe e
no reconnect.

### `next_mobile_dispatch_candidate` (inalterada)

Inputs: search ID, candidate ID, expected revision. Marca somente o candidato corrente como
`CLIENT_DISMISSED` e seleciona o próximo. Replay da mesma revisão/candidato retorna o snapshot já
avançado.

### `request_mobile_dispatch_candidate` (inalterada)

Inputs: search ID, candidate ID, expected revision. Revalida posição recente/oferta/provider/
ausência de lease concorrente; cria no máximo um appointment por candidato, copia `price_snapshot`,
define `PENDING` e `response_deadline` server-side de 60s. Replay retorna o mesmo appointment/
cotação.

## Decisão e ciclo do provider

### `get_my_pending_mobile_dispatch` (inalterada)

Retorna somente a solicitação `PENDING` destinada ao provider autenticado, já reconciliada com o
deadline.

### `respond_to_mobile_dispatch` (inalterada)

Inputs: appointment ID, `p_accept`, expected revision. Somente o provider owner responde; aceite
após o deadline é impossível mesmo se o Cron atrasar. Aceite confirma reserva e remove discovery;
recusa registra `PROVIDER_REJECTED`, libera a lease e avança a busca na mesma transação.

### `start_mobile_appointment` / `cancel_mobile_appointment` / `complete_mobile_appointment` (inalteradas)

Comportamento idêntico ao Android — ver contrato Android original para detalhe completo; nenhuma
regra muda por plataforma. `cancel_mobile_appointment` exige motivo (`trim`, obrigatório) e o
servidor deriva `cancelled_by` do papel da sessão.

## Expiração (backend-only, inalterada)

`private.expire_due_mobile_dispatch_requests(p_limit)` roda via Supabase Cron a cada segundo,
independentemente de qualquer client estar aberto. Nenhuma ação do client iOS.

## Segurança e grants (inalterados)

RLS habilitada em todas as tabelas; `anon` sem SELECT/DML/EXECUTE; `authenticated` sem DML direto;
`private.dispatch_candidates` sem grants para o bundle; `provider_discovery_locations` sem SELECT
direto (só o snapshot do candidato corrente revela posição, à conta CLIENT proprietária da busca);
índices parciais protegem uma busca ativa por `(client, service)` e um provider ocupado por vez.
