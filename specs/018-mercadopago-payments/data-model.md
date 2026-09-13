# Phase 1 Data Model: Pagamento de serviços (Pix e cartão) — iOS

## Status: schema/RPCs/Edge Functions já autorados uma única vez, compartilhados com o Android

As duas tabelas, os RPCs e as cinco Edge Functions abaixo pertencem ao mesmo schema `public` do
projeto Supabase compartilhado — seguem o padrão já usado por `mobile_dispatch_searches`/`pittec_*`
(RLS por dono, `SECURITY DEFINER` RPCs para as transições sensíveis, sem acesso direto de escrita do
cliente às colunas de status). O client iOS apenas consome este contrato; nenhum schema é criado ou
alterado por esta feature além do que já foi (ou será, na primeira implementação de qualquer uma das
duas plataformas) publicado uma única vez.

## `payments` (Pagamento)

| Coluna | Tipo | Notas |
|---|---|---|
| `id` | `uuid`, PK, `default gen_random_uuid()` | Identificador interno do pagamento. |
| `request_id` | `uuid`, not null, unique por tentativa ativa | Mesmo `request_id`/`search_id` usado por `request_mobile_dispatch_candidate`/`start_pittec_dispatch`; liga o pagamento à solicitação. |
| `client_id` | `uuid`, not null, FK `auth.users(id)` | Dono do pagamento; usado pela política de RLS. |
| `dispatch_kind` | `enum MOBILE_SEQUENTIAL \| PITTEC_AUTO_SEQUENTIAL` | Qual fluxo originou a cobrança (FR-014). |
| `method` | `enum PIX \| SAVED_CARD` | Forma de pagamento escolhida. |
| `saved_card_id` | `uuid`, nullable, FK `saved_cards(id)` | Preenchido só quando `method = SAVED_CARD`. |
| `amount` | `numeric(10,2)`, not null, `> 0` | Valor cobrado — preço exato da proposta congelada (MOBILE_SEQUENTIAL) ou tarifa fixa de plataforma (PITTEC_AUTO_SEQUENTIAL); ver `research.md §9-10`. |
| `status` | `enum PENDING \| APPROVED \| REJECTED \| EXPIRED \| CANCELLED \| REFUNDED \| REFUND_FAILED` | Ver máquina de estados abaixo. |
| `mp_payment_id` | `text`, nullable, unique quando presente | Id do pagamento no Mercado Pago; chave usada pelo webhook. |
| `idempotency_key` | `text`, not null, unique | `request_id` (+ sufixo de tentativa); evita cobrança duplicada (FR-011). |
| `refund_attempts` | `smallint`, not null, default `0` | Incrementado a cada tentativa de `mp-refund-payment`; limite de 3 (research.md §7). |
| `created_at` / `updated_at` | `timestamptz`, not null, default `now()` | Auditoria simples. |
| `approved_at` | `timestamptz`, nullable | Preenchido quando `status = APPROVED`. |

**RLS**: `client_id = auth.uid()` para `SELECT`; nenhum `INSERT`/`UPDATE`/`DELETE` direto do cliente
— tudo passa pelas Edge Functions (com service role) ou pelos RPCs `SECURITY DEFINER` descritos em
`contracts/payment-rpcs.md`.

**Máquina de estados**:

```text
PENDING --(Mercado Pago aprova)--> APPROVED --(cancelamento pré-conclusão OU busca exaurida)--> REFUNDED
PENDING --(Mercado Pago recusa)--> REJECTED
PENDING --(prazo do Pix expira)--> EXPIRED
PENDING --(cliente cancela antes da aprovação)--> CANCELLED
APPROVED --(estorno falha 3x)--> REFUND_FAILED  (suporte assume manualmente)
```

Nenhuma outra transição é válida; os RPCs que gravam `status` rejeitam transições fora deste
conjunto.

## `saved_cards` (Cartão salvo)

| Coluna | Tipo | Notas |
|---|---|---|
| `id` | `uuid`, PK, `default gen_random_uuid()` | Identificador interno. |
| `client_id` | `uuid`, not null, FK `auth.users(id)` | Dono do cartão; base da política de RLS. |
| `mp_customer_id` | `text`, not null | Customer do Mercado Pago vinculado a este cliente (um por cliente, reaproveitado entre cartões, independentemente da plataforma de origem). |
| `mp_card_id` | `text`, not null, unique | Customer Card do Mercado Pago; usado como `token` em `POST /v1/payments`. |
| `brand` | `text`, not null | Bandeira retornada pelo Mercado Pago (ex.: `visa`, `mastercard`). |
| `last_four_digits` | `char(4)`, not null | Últimos 4 dígitos retornados pelo Mercado Pago — nunca o PAN completo. |
| `created_at` | `timestamptz`, not null, default `now()` | Data de cadastro. |

Nenhuma coluna guarda PAN completo, CVV ou data de validade (FR-006) — esses dados existem apenas
em trânsito entre o SDK do Mercado Pago (Android ou iOS) e a API do Mercado Pago, nunca no banco do
PitGo.

**RLS**: `client_id = auth.uid()` para `SELECT`; `INSERT`/`DELETE` só via `SECURITY DEFINER` RPC que
confere que o `mp_card_id` pertence ao `mp_customer_id` daquele cliente.

## Relação com entidades existentes e pontos de gate (iOS)

- `payments.request_id` referencia:
  - para MOBILE_SEQUENTIAL, o mesmo `searchID`/`candidateID` usados por
    `request_mobile_dispatch_candidate` (`013`) — a guarda de pagamento vive **nessa** RPC, não em
    `start_mobile_dispatch` (ver `research.md §9`);
  - para PITTEC_AUTO_SEQUENTIAL, o mesmo `p_request_id` usado por `start_pittec_dispatch` (`015`) —
    a guarda de pagamento vive nessa RPC, idêntico ao Android (ver `research.md §10`).
- Cancelamento (`cancel_mobile_appointment`, `cancel_pittec_search` e o equivalente pós-aceite
  compartilhado) e a rotina de busca PitTec exaurida (`advance_pittec_dispatch` alcançando
  `NO_PROVIDER`) passam a, dentro da mesma transação, marcar `payments.status = 'REFUNDED'`/
  enfileirar `mp-refund-payment` quando havia um pagamento `APPROVED` associado e o atendimento não
  chegou a `COMPLETED`/`IN_PROGRESS`→`COMPLETED` (FR-015/FR-017).
- Conclusão do atendimento (`complete_mobile_appointment` e o equivalente PitTec) não altera
  `payments` — o valor já cobrado fica como `APPROVED` definitivo (FR-016).

## Modelos Swift consumidos pelo client iOS

```swift
enum PaymentDispatchKind: String, Codable {
    case mobileSequential = "MOBILE_SEQUENTIAL"
    case pittecAutoSequential = "PITTEC_AUTO_SEQUENTIAL"
}

enum PaymentMethod: String, Codable { case pix = "PIX", savedCard = "SAVED_CARD" }

enum PaymentStatus: String, Codable {
    case pending = "PENDING", approved = "APPROVED", rejected = "REJECTED"
    case expired = "EXPIRED", cancelled = "CANCELLED"
    case refunded = "REFUNDED", refundFailed = "REFUND_FAILED"
}

struct PaymentPixDetails: Decodable {
    let qrCode: String            // copia e cola
    let qrCodeBase64: String      // decodificar com Data(base64Encoded:) para exibir
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case qrCode = "qr_code", qrCodeBase64 = "qr_code_base64", expiresAt = "expires_at"
    }
}

struct PaymentSnapshot: Decodable {
    let paymentID: UUID
    let status: PaymentStatus
    let pix: PaymentPixDetails?     // presente só quando method == .pix e status == .pending

    enum CodingKeys: String, CodingKey {
        case paymentID = "payment_id", status, pix
    }
}

struct SavedCard: Decodable, Identifiable {
    let id: UUID
    let brand: String
    let lastFourDigits: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, brand, createdAt = "created_at"
        case lastFourDigits = "last_four_digits"
    }
}
```

`amount` trafega como `Decimal` em todas as chamadas Swift (nunca `Double`), consistente com o
restante do app (moeda real, não o `Int` de centavos usado exclusivamente pelo protótipo mockado de
`017`).
