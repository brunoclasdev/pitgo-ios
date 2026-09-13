# Contract: RPCs Postgres de pagamento (compartilhadas com o Android)

## Status: already implemented and deployed (ou autoradas uma única vez, se ainda não publicadas)

Seguem o padrão já usado pelos RPCs de despacho (`SECURITY DEFINER`, `SELECT ... FOR UPDATE` onde
há corrida possível, revisão de `client_id = auth.uid()` antes de qualquer leitura/gravação).

## Novos RPCs

### `get_payment_status(p_request_id uuid) → payment_status_row`

Leitura pelo próprio cliente do estado atual do pagamento de uma solicitação. Usado como fallback
quando o Realtime não entrega a atualização (ver `payment-realtime-ui.md`). Retorna `status`,
`method`, `pix_qr_code` (se ainda pendente e for Pix) e `refund_status`.

```swift
let status: PaymentSnapshot = try await client
    .rpc("get_payment_status", params: ["p_request_id": requestID])
    .execute()
    .value
```

### `list_saved_cards() → setof saved_card_row`

Lista os cartões do cliente autenticado (`brand`, `last_four_digits`, `id`, `created_at`); nunca
retorna `mp_card_id` bruto ao app além do necessário para seleção.

```swift
let cards: [SavedCard] = try await client
    .rpc("list_saved_cards")
    .execute()
    .value
```

### `remove_saved_card(p_saved_card_id uuid) → void`

Chamado pela Edge Function `mp-remove-card` após remover no Mercado Pago; confere posse antes de
apagar a linha. Não é chamado diretamente pelo client iOS (que sempre passa por `mp-remove-card`).

## Guarda adicionada às RPCs de despacho existentes (ponto de gate — ver research.md §9-10)

### MOBILE_SEQUENTIAL: guarda em `request_mobile_dispatch_candidate`, não em `start_mobile_dispatch`

`start_mobile_dispatch` (`013`) permanece **sem** guarda de pagamento — buscar e folhear candidatos
(`OPTION_FOUND`/"Próximo") continua gratuito, sem acionar nenhum prestador, exatamente como
especificado em `013`.

`request_mobile_dispatch_candidate(p_search_id, p_candidate_id, p_expected_revision, ...)` ganha,
logo no início da transação (depois de revalidar posição/oferta/lease, antes de criar o
appointment):

```sql
if not exists (
  select 1 from payments
  where request_id = p_candidate_id  -- mesmo id usado por mp-create-payment para este candidato
    and client_id = auth.uid()
    and status = 'APPROVED'
) then
  raise exception 'PAYMENT_REQUIRED' using errcode = 'P0001';
end if;
```

O app iOS mapeia o código `PAYMENT_REQUIRED` para um novo caso do enum de falha já existente em
`Features/MobileDispatch/Model/MobileDispatchModels.swift`, reaproveitando o tratamento de erro já
existente em vez de criar um canal de erro paralelo.

### PITTEC_AUTO_SEQUENTIAL: guarda em `start_pittec_dispatch`

`start_pittec_dispatch(p_request_id, ...)` (`015`) ganha, logo no início da transação, a mesma
checagem:

```sql
if not exists (
  select 1 from payments
  where request_id = p_request_id
    and client_id = auth.uid()
    and status = 'APPROVED'
) then
  raise exception 'PAYMENT_REQUIRED' using errcode = 'P0001';
end if;
```

O app iOS mapeia `PAYMENT_REQUIRED` para um novo caso de `PitTecFailure`, reaproveitando o mesmo
tratamento de erro já existente em `Features/PitTec/Model/PitTecModels.swift`.

## Guarda de estorno automático adicionada ao cancelamento e à exaustão

`cancel_mobile_appointment`, `cancel_pittec_search` e a rotina privada `advance_pittec_dispatch`
(quando alcança `NO_PROVIDER`) passam a, dentro da mesma transação:

```sql
if exists (
  select 1 from payments
  where request_id = <candidate_id/request_id do atendimento>
    and status = 'APPROVED'
) then
  update payments set status = 'REFUNDED' -- otimista; ajustado por mp-refund-payment se falhar
  where request_id = <...> and status = 'APPROVED';
  perform pg_notify('mp_refund_queue', <payment_id>); -- ou chamada http via pg_net, conforme research.md §7
end if;
```

Isso implementa FR-015/FR-017 sem introduzir uma tabela de fila nova: o próprio `payments` com
`status IN ('REFUNDED', 'REFUND_FAILED')` já é o registro de auditoria necessário nesta versão.
