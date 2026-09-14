# Contract: Orçamento e pagamento do PitTec (real, implantado em 2026-09-13)

**Status**: ✅ Implantado — migration `20260913010000_pittec_call_tracking.sql` (repositório
Android, `supabase/migrations/`) aplicada à nuvem compartilhada nesta sessão; Edge Function
`mp-create-payment` (mesma origem) implantada em seguida. Este arquivo documenta o contrato real
consumido pelo client iOS, substituindo `confirm-pittec-value-rpc.md` (ver nota lá).

## Mudança de fundo em relação ao design original desta spec

A busca do PitTec **não exige mais pagamento prévio**. A cobrança acontece **depois** que o cliente
confirma o orçamento específico ofertado pelo provider ao aceitar — não uma tarifa fixa de
plataforma.

## Novos status (compartilhados entre `service_searches.status`/`appointments.status`)

- `AWAITING_CLIENT_CONFIRMATION`: provider aceitou; cliente vê o orçamento (`quoted_price`) e tem
  até 2 minutos (`client_confirmation_deadline`) para confirmar ou recusar.
- `AWAITING_PAYMENT`: cliente confirmou o orçamento; falta o pagamento em si.

Expiração automática (2 min sem resposta) é tratada por um cron job
(`pitgo-expire-pittec-confirmations`, a cada segundo) chamando
`expire_due_pittec_confirmations()` — o client nunca decide expiração pelo próprio relógio.

## RPC: `respond_to_pittec_quote`

```sql
respond_to_pittec_quote(
  p_request_id uuid,      -- search_id
  p_appointment_id uuid,
  p_quote_version bigint,
  p_accept boolean,
  p_expected_revision bigint
)
```

- Só o cliente dono do atendimento pode chamar.
- `p_accept = true`: `AWAITING_CLIENT_CONFIRMATION` → `AWAITING_PAYMENT`
  (`client_confirmed_at`/`client_confirmed_quote_version` preenchidos). Idempotente: chamar de novo
  já em `AWAITING_PAYMENT` com a mesma versão confirmada retorna `CONFIRMED` sem repetir a
  transição.
- `p_accept = false`: cancela o atendimento e a busca (`cancellation_reason = 'QUOTE_DECLINED'`),
  sem exigir nenhum texto do cliente.
- Outcomes: `CONFIRMED`, `DECLINED` (ambos com `snapshot`), `REVISION_CONFLICT`,
  `INVALID_TRANSITION`, `CONFIRMATION_EXPIRED` (idem), `NOT_FOUND` (sem `snapshot`).
- **Achado relevante para o client iOS**: o outcome `DECLINED` também é usado por
  `respond_to_mobile_dispatch` (provider recusando a chamada, guincho móvel `013`) — mas SEM
  `snapshot` nesse outro caso. `PitTecRepository.interpret(_:)` distingue os dois pela presença do
  `snapshot`, nunca pelo nome do outcome.

## Pagamento (`AWAITING_PAYMENT` → `ACCEPTED`)

- Cliente chama `mp-create-payment` (Edge Function) com `request_id` (= `search_id`),
  `dispatch_kind = "PITTEC_AUTO_SEQUENTIAL"`, `appointment_id`, `quote_version` — a função resolve o
  `amount` real a partir de `appointments.quoted_price` no servidor, **nunca confia num valor vindo
  do client**; valida `status = AWAITING_PAYMENT`, `quote_version` e `client_confirmed_quote_version`
  batendo.
- Quando o Mercado Pago aprova, o trigger `reconcile_pittec_payment_change` (em `payments`) avança
  `appointments`/`service_searches` para `ACCEPTED` sozinho e cria a linha inicial de
  `client_current_locations` — nenhuma RPC adicional do client é necessária para essa transição.
- O mesmo trigger é defensivo: se o pagamento não bater exatamente com o atendimento/versão/valor
  esperados, marca `REFUND_PENDING` em vez de aceitar silenciosamente.

## Estados por lado (client iOS)

| `status` | Cliente | PitTec |
|---|---|---|
| `AWAITING_CLIENT_CONFIRMATION` | Card de orçamento — Confirmar/Recusar (`confirmQuote()`/`declineQuote()`) | Tela "Aguardando confirmação do cliente" |
| `AWAITING_PAYMENT` | Tela "Orçamento confirmado — falta só pagar" + botão que abre `PaymentCheckoutView` (`PitTecPaymentContext`) | Tela "Aguardando pagamento" |
| `ACCEPTED`/`IN_PROGRESS` | Mapa de acompanhamento conjunto (inalterado, `pittec-confirmation-tracking-ui.md`) | Idem |

## Nenhuma mudança em

`start_pittec_dispatch` (mesma assinatura; só deixou de exigir pagamento prévio — a guarda foi
removida no backend, não no client), `cancel_mobile_appointment`, `arrive_pittec_appointment`,
`complete_mobile_appointment`, `list_nearby_pittecs`, `get_pittec_route_context`, o mecanismo de
publicação periódica de posição (`ProviderLocationTracker`, ~10s), e o enquadramento conjunto do
mapa (`PitGoMapView.fitCoordinates`) — todos preservados do design original desta spec.
