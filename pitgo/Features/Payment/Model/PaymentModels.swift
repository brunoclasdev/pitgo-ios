//
//  PaymentModels.swift
//  pitgo
//
//  Domínio de pagamento (`018`). Formatos confirmados nesta sessão via `pg_get_functiondef`/
//  inspeção de schema no projeto Supabase compartilhado — `payments`/`saved_cards`, as cinco Edge
//  Functions e a guarda de pagamento JÁ ESTAVAM implantadas (presumivelmente pelo trabalho Android
//  de `018`) quando esta feature começou no iOS; nenhuma migration/Edge Function nova foi autorada
//  aqui.
//
//  ACHADO CRÍTICO desta sessão, que substitui o ponto de gate descrito em `research.md §9` deste
//  spec: `research.md` argumenta que o gate de MOBILE_SEQUENTIAL deveria viver em
//  `request_mobile_dispatch_candidate` (depois de um candidato existir), não em
//  `start_mobile_dispatch`. A inspeção direta da função REAL implantada mostra o oposto: o gate está
//  em `start_mobile_dispatch` (`payments.request_id = p_search_id`), exatamente como o Android já
//  implementou (`PaymentCheckoutViewModel.kt`, que gera o `requestId` a partir da Home, antes de
//  qualquer busca existir). `request_mobile_dispatch_candidate` continua SEM guarda nenhuma —
//  reservar um candidato específico não exige pagamento além do já feito para iniciar a busca. Este
//  client segue a realidade verificada, não o texto do research.md.
//
//  ACHADO ADICIONAL: `list_home_services().minimum_price` é sempre 0 para
//  PITTEC_AUTO_SEQUENTIAL (a oferta do prestador PitTec é `is_free = true`/preço zero por desenho,
//  `016`) — não pode ser reaproveitado como valor cobrado do cliente. Desde `021`/migration
//  `20260913010000`, o valor cobrado do PitTec vem do orçamento (`appointment.quotedPrice`,
//  `PitTecPaymentContext`), nunca do catálogo nem de uma tarifa fixa do app.
//

import Foundation

enum PaymentDispatchKind: String, Codable, Hashable {
    case mobileSequential = "MOBILE_SEQUENTIAL"
    case pittecAutoSequential = "PITTEC_AUTO_SEQUENTIAL"
    /// `028` — o valor cobrado vem do orçamento do guincheiro escolhido (`appointment.quotedPrice`
    /// já resolvido para o total do cliente), nunca de uma tarifa fixa do app.
    case guinchoDirect = "GUINCHO_DIRECT"
}

enum PaymentMethodKind: String, Codable, Hashable {
    case pix = "PIX"
    case savedCard = "SAVED_CARD"
}

/// Espelha `payments.status` (`data-model.md`). `REFUND_PENDING` é transitório: o backend grava
/// assim que um pagamento aprovado perde a solicitação associada (cancelamento pré-conclusão ou
/// busca PitTec exaurida); o app chama `mp-refund-payment` a partir daí.
enum PaymentStatus: String, Decodable, Hashable {
    case pending = "PENDING"
    case approved = "APPROVED"
    case rejected = "REJECTED"
    case expired = "EXPIRED"
    case cancelled = "CANCELLED"
    case refundPending = "REFUND_PENDING"
    case refunded = "REFUNDED"
    case refundFailed = "REFUND_FAILED"

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self).uppercased()
        switch value {
        case "DECLINED", "FAILED": self = .rejected
        case "CANCELED": self = .cancelled
        default:
            guard let status = Self(rawValue: value) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Status de pagamento desconhecido: \(value)"
                )
            }
            self = status
        }
    }

    var isRefundOutcome: Bool {
        switch self {
        case .refundPending, .refunded, .refundFailed: true
        default: false
        }
    }
}

/// `021`/migration `20260913010000` — contexto do checkout de um atendimento PitTec já aceito e
/// confirmado (`AWAITING_PAYMENT`). Substitui o fluxo antigo de tarifa fixa cobrada antes da busca:
/// o valor vem do orçamento (`appointment.quotedPrice`), e o pagamento é amarrado ao atendimento e
/// à versão do orçamento (`mp-create-payment` valida os dois server-side).
struct PitTecPaymentContext: Equatable, Identifiable {
    let searchID: UUID
    let appointmentID: UUID
    let quoteVersion: Int64
    let amount: Decimal

    var id: UUID { appointmentID }
}

nonisolated struct PaymentPixDetails: Decodable, Equatable {
    let qrCode: String
    let qrCodeBase64: String
    let expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case qrCode = "qr_code"
        case qrCodeBase64 = "qr_code_base64"
        case expiresAt = "expires_at"
    }
}

/// Resposta de `mp-create-payment` (`contracts/mercadopago-edge-functions.md`).
nonisolated struct PaymentCreationResult: Decodable, Equatable {
    let paymentID: UUID
    let status: PaymentStatus
    let pix: PaymentPixDetails?
    let cancelRequested: Bool
    let syncState: String

    init(paymentID: UUID, status: PaymentStatus, pix: PaymentPixDetails?, cancelRequested: Bool = false, syncState: String = "CURRENT") {
        self.paymentID = paymentID; self.status = status; self.pix = pix; self.cancelRequested = cancelRequested; self.syncState = syncState
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        paymentID = try values.decode(UUID.self, forKey: .paymentID)
        status = try values.decode(PaymentStatus.self, forKey: .status)
        pix = try values.decodeIfPresent(PaymentPixDetails.self, forKey: .pix)
        cancelRequested = try values.decodeIfPresent(Bool.self, forKey: .cancelRequested) ?? false
        syncState = try values.decodeIfPresent(String.self, forKey: .syncState) ?? "CURRENT"
    }

    enum CodingKeys: String, CodingKey {
        case paymentID = "payment_id"
        case cancelRequested = "cancel_requested"
        case syncState = "sync_state"
        case status
        case pix
    }
}

enum PaymentFailureReason: Equatable {
    case offline
    case timeout
    case sessionExpired
    /// `mp-create-payment` → `422 PAYER_DOCUMENT_REQUIRED` — Pix exige CPF já cadastrado no perfil.
    case payerDocumentRequired
    /// `mp-create-payment`/`mp-save-card` → `422 CARD_REJECTED`.
    case cardRejected
    case cardNotFound
    case notFound
    case serviceUnavailable
    case unknown
}
