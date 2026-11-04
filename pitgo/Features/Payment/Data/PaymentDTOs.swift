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
    let service_id: UUID
    let checkout_environment: String
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
    let details: PaymentStatusDetails

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
        details = try PaymentStatusDetails(from: decoder)
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

struct PaymentCancellationResponse: Decodable {
    let status: PaymentStatus
    let cancelRequested: Bool?

    enum CodingKeys: String, CodingKey {
        case status
        case cancelRequested = "cancel_requested"
    }
}

nonisolated struct PaymentStatusDetails: Decodable {
    var pix: PaymentPixDetails? = nil
    var cancelRequested: Bool = false
    var supportRequired: Bool = false
    var syncState: String = "CURRENT"
    var requestID: UUID? = nil
    var serviceID: UUID? = nil
    var dispatchKind: PaymentDispatchKind? = nil

    enum CodingKeys: String, CodingKey {
        case pix
        case cancelRequested = "cancel_requested"
        case supportRequired = "support_required"
        case syncState = "sync_state"
        case requestID = "request_id"
        case serviceID = "service_id"
        case dispatchKind = "dispatch_kind"
    }

    init(pix: PaymentPixDetails? = nil, cancelRequested: Bool = false, supportRequired: Bool = false,
         requestID: UUID? = nil, serviceID: UUID? = nil, dispatchKind: PaymentDispatchKind? = nil, syncState: String = "CURRENT") {
        self.pix = pix; self.cancelRequested = cancelRequested; self.supportRequired = supportRequired
        self.syncState = syncState
        self.requestID = requestID; self.serviceID = serviceID; self.dispatchKind = dispatchKind
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pix = try values.decodeIfPresent(PaymentPixDetails.self, forKey: .pix)
        cancelRequested = try values.decodeIfPresent(Bool.self, forKey: .cancelRequested) ?? false
        supportRequired = try values.decodeIfPresent(Bool.self, forKey: .supportRequired) ?? false
        syncState = try values.decodeIfPresent(String.self, forKey: .syncState) ?? "CURRENT"
        requestID = try values.decodeIfPresent(UUID.self, forKey: .requestID)
        serviceID = try values.decodeIfPresent(UUID.self, forKey: .serviceID)
        dispatchKind = try values.decodeIfPresent(PaymentDispatchKind.self, forKey: .dispatchKind)
    }
}
