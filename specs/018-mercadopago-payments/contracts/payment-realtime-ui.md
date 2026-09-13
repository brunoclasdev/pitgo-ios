# Contract: Realtime de pagamento e estados de UI (iOS)

## Canal Realtime

Reaproveita o padrão já usado por `MobileDispatchRepository`/`PitTecRepository` (`013`/`015`) em
`supabase-swift`: um canal privado por solicitação, assinado com `RealtimeChannelV2`/`broadcastFlow`
equivalente.

- **Tópico**: `payment:<request_id>` (privado; só o `client_id` dono consegue se inscrever, mesma
  técnica de canal privado já usada em `mobile-dispatch:<searchId>`/`pittec:<requestId>`).
- **Evento**: publicado por `mp-webhook` sempre que `payments.status` muda; payload mínimo:
  `{ "request_id": "...", "status": "PENDING|APPROVED|REJECTED|EXPIRED|CANCELLED|REFUNDED|REFUND_FAILED" }`.
- **Fallback**: se o canal cair ou não emitir em até 10s após uma ação do cliente (ex.: acabou de
  gerar o Pix), o app chama `get_payment_status` (RPC) para não deixar a tela presa sem retorno —
  mesmo padrão de fallback por polling já usado em `015` (`research.md §6` daquela feature).

```swift
for await status in paymentRepository.observe(requestID: requestID) {
    // atualizar PaymentCheckoutViewModel
}
```

## Estados de UI — Checkout (`Features/Payment`)

```swift
enum PaymentCheckoutUiState {
    case selectingMethod(savedCards: [SavedCard])
    case creatingPayment
    case awaitingPix(PaymentPixDetails)
    case awaitingCardConfirmation
    case approved
    case declined
    case expired
    case failure(reason: PaymentFailureReason)
}
```

| Estado | Gatilho | UI |
|---|---|---|
| `.selectingMethod` | Cliente chega à etapa de pagamento | Lista Pix + cartões salvos (sem opção de cadastrar, FR-019). |
| `.creatingPayment` | Cliente confirma o método | `ProgressView` curto enquanto `mp-create-payment` responde. |
| `.awaitingPix` | `method = PIX` e resposta `PENDING` | QR (`Image(uiImage:)` do Base64 decodificado)/copia-e-cola + contagem regressiva até `expiresAt`. |
| `.awaitingCardConfirmation` | `method = SAVED_CARD` e resposta `PENDING` | Loading (cobrança em cartão costuma resolver em segundos). |
| `.approved` | Evento Realtime ou RPC retorna `APPROVED` | Confirmação breve, então navega para `request_mobile_dispatch_candidate`/`start_pittec_dispatch`, conforme `dispatchKind`. |
| `.declined` | `REJECTED` | Mensagem compreensível + ação "tentar outro método" (FR-010). |
| `.expired` | `EXPIRED` | Mensagem de prazo expirado + ação "gerar novo código" ou trocar de método (US1 cenário 3). |
| `.failure` | Erro de rede/serviço indisponível | Mensagem genérica + tentar novamente, sem cobrar de novo (idempotência já garante isso no backend). |

Nenhum destes estados aciona `request_mobile_dispatch_candidate`/`start_pittec_dispatch` fora de
`.approved` — é o ponto único onde o gate de pagamento se conecta ao despacho (research.md §9-10).

## Estados de UI — Formas de pagamento (`Features/PaymentMethods`)

```swift
enum PaymentMethodsUiState {
    case loading
    case empty
    case listing([SavedCard])
    case registering
    case registerFailed(reason: String)
    case removing(SavedCard.ID)
}
```

| Estado | Gatilho | UI |
|---|---|---|
| `.loading` | Tela aberta | `ProgressView` enquanto `list_saved_cards()` carrega. |
| `.empty` | Nenhum cartão salvo | Mensagem + botão "Cadastrar cartão", sem bloquear navegação (FR-005). |
| `.listing` | Um ou mais cartões | Cartões com bandeira/últimos 4 dígitos + ação remover (FR-007). |
| `.registering` | Cliente toca "Cadastrar cartão" | Formulário CoreMethods do SDK do Mercado Pago (campos seguros PCI). |
| `.registerFailed` | `mp-save-card` retorna `422 CARD_REJECTED` | Mensagem compreensível + tentar novamente ou voltar sem cadastrar (US2 cenário 2). |
| `.removing` | Cliente confirma remoção | Loading curto; ao concluir volta para `.listing`/`.empty`. |

## Feedback de estorno

Quando `payments.status` chega a `REFUNDED` ou `REFUND_FAILED` (via o mesmo canal
`payment:<request_id>`), a View de acompanhamento do atendimento
(`Features/AppointmentTracking/Views/AppointmentTrackingView.swift`) e/ou o card de busca
(`ClientMobileDispatchView.swift`/`PitTecView` real) informam o cliente:
- `REFUNDED`: "valor estornado" (SC-007).
- `REFUND_FAILED`: "reembolso em andamento, nossa equipe já foi avisada" (FR-018) — sem exigir que o
  cliente abra chamado.

## Navegação e composição de rota

`PitGoRoute.payment(requestID:dispatchKind:)` é uma nova rota inserida entre o card de proposta
(MOBILE_SEQUENTIAL, após "Solicitar este guincho") ou o botão "Chamar PitTec" (PITTEC_AUTO_SEQUENTIAL)
e o destino já existente:

- MOBILE_SEQUENTIAL: o toque em "Solicitar este guincho" (`OPTION_FOUND`) primeiro gera o pagamento
  (`request_id = candidateID`); em `.approved`, o app chama `request_mobile_dispatch_candidate` com
  esse `candidateID` e navega normalmente para `AWAITING_PROVIDER`.
- PITTEC_AUTO_SEQUENTIAL: o toque em "Chamar PitTec" primeiro gera o pagamento (`request_id` gerado
  uma vez pelo client, mesma chave idempotente usada depois em `start_pittec_dispatch`); em
  `.approved`, o app chama `start_pittec_dispatch` com esse `p_request_id`.

Em ambos os casos, cancelar a tela de pagamento antes de `.approved` não chama nenhuma RPC de
despacho (FR-013) — a única chamada já feita é `mp-create-payment`, cujo pagamento fica `PENDING`
até expirar/ser cancelado.
