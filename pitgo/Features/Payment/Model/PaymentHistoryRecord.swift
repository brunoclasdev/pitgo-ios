import Foundation

struct PaymentHistoryRecord: Decodable, Identifiable {
    let id: UUID
    let status: PaymentStatus
    let method: PaymentMethodKind
    let amount: Decimal
    let createdAtRaw: String?
    let cardBrand: String?
    let cardLastFourDigits: String?
    let cancelRequested: Bool
    let supportRequired: Bool

    enum CodingKeys: String, CodingKey {
        case id = "payment_id"
        case status, method, amount
        case createdAtRaw = "created_at"
        case cardBrand = "card_brand"
        case cardLastFourDigits = "card_last_four_digits"
        case cancelRequested = "cancel_requested"
        case supportRequired = "support_required"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        status = try values.decode(PaymentStatus.self, forKey: .status)
        method = try values.decode(PaymentMethodKind.self, forKey: .method)
        if let text = try? values.decode(String.self, forKey: .amount),
           let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) {
            amount = value
        } else { amount = try values.decode(Decimal.self, forKey: .amount) }
        createdAtRaw = try values.decodeIfPresent(String.self, forKey: .createdAtRaw)
        cardBrand = try values.decodeIfPresent(String.self, forKey: .cardBrand)
        cardLastFourDigits = try values.decodeIfPresent(String.self, forKey: .cardLastFourDigits)
        cancelRequested = try values.decodeIfPresent(Bool.self, forKey: .cancelRequested) ?? false
        supportRequired = try values.decodeIfPresent(Bool.self, forKey: .supportRequired) ?? false
    }

    var createdAt: Date? {
        guard let createdAtRaw else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: createdAtRaw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: createdAtRaw)
    }

    var statusLabel: String {
        if cancelRequested && [.pending, .approved].contains(status) { return "Cancelamento solicitado" }
        switch status {
        case .pending: return "Aguardando pagamento"
        case .approved: return "Aprovado"
        case .rejected: return "Recusado"
        case .expired: return "Expirado"
        case .cancelled: return "Cancelado"
        case .refundPending: return "Estorno em andamento"
        case .refunded: return "Estornado"
        case .refundFailed: return "Falha no estorno"
        }
    }
}
