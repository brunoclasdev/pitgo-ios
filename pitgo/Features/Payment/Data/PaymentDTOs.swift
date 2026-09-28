//
//  PaymentDTOs.swift
//  pitgo
//
//  Formatos de request/response confirmados nesta sessão lendo o código-fonte REAL das cinco Edge
//  Functions (`supabase functions download`) e via `pg_get_functiondef` das RPCs — não apenas o
//  texto prosaico de `contracts/`. Duas divergências relevantes encontradas: `get_payment_status`
//  devolve `{outcome, payment_id, status, method}` (sem `pix_qr_code`/`refund_status`, ao contrário
//  do que o contrato descreve) e `list_saved_cards()` devolve a tabela diretamente, sem envelope.
//

import Foundation

// MARK: - `mp-create-payment`

struct CreatePaymentRequestBody: Encodable {
    let request_id: UUID
    let dispatch_kind: String
    /// MOBILE_SEQUENTIAL envia o preço esperado. Para PITTEC_AUTO_SEQUENTIAL o backend
    /// calcula o valor congelado do pagamento de teste (R$1–R$2) a partir do atendimento;
    /// enviar o orçamento aqui faria a RPC rejeitar com PRICE_CHANGED.
    let amount: Decimal?
    let method: String
    let saved_card_id: UUID?
    let card_security_code_token: String?
    /// `021`/migration `20260913010000` — obrigatórios só para `PITTEC_AUTO_SEQUENTIAL`; a Edge
    /// Function resolve o valor real a partir do atendimento, ignorando `amount` nesse caso.
    let appointment_id: UUID?
    let quote_version: Int64?
}

/// Corpo de erro de qualquer uma das cinco Edge Functions — sempre `{ "code": "..." }` (ver
/// `mp-create-payment`/`mp-save-card`/`mp-remove-card`/index.ts reais).
struct PaymentEdgeFunctionErrorBody: Decodable {
    let code: String
}

// MARK: - `get_payment_status`

struct GetPaymentStatusParams: Encodable {
    let p_request_id: UUID
}

private enum PaymentStatusOutcome: String, Decodable {
    case found = "FOUND"
    case notFound = "NOT_FOUND"
}

/// `get_payment_status(p_request_id)` retorna este envelope diretamente (função `plpgsql` que
/// devolve `jsonb`) — real, não o `payment_status_row` mais rico descrito em `contracts/`.
struct PaymentStatusEnvelope: Decodable {
    let outcome: String
    let paymentID: UUID?
    let status: PaymentStatus?
    let method: PaymentMethodKind?

    enum CodingKeys: String, CodingKey {
        case outcome
        case paymentID = "payment_id"
        case status
        case method
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outcome = try container.decode(String.self, forKey: .outcome)
        paymentID = try container.decodeIfPresent(UUID.self, forKey: .paymentID)
        status = try container.decodeIfPresent(PaymentStatus.self, forKey: .status)
        // The method is useful metadata only. Do not discard an otherwise valid terminal
        // payment status if an older backend returns a method alias not known by this app.
        if let rawMethod = try container.decodeIfPresent(String.self, forKey: .method) {
            method = PaymentMethodKind(rawValue: rawMethod.uppercased())
        } else {
            method = nil
        }
    }

    var isFound: Bool { outcome == PaymentStatusOutcome.found.rawValue }
}

// MARK: - `mp-refund-payment`

struct RefundPaymentRequestBody: Encodable {
    let payment_id: UUID
}

struct RefundPaymentResponse: Decodable {
    let status: PaymentStatus
}
