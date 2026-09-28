//
//  SavedCardModels.swift
//  pitgo
//
//  Cartão salvo (`018`) — nunca guarda PAN/CVV/validade; só o que `list_saved_cards()` devolve.
//

import Foundation

struct SavedCard: Decodable, Identifiable, Hashable {
    let id: UUID
    let brand: String
    let lastFourDigits: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case brand
        case lastFourDigits = "last_four_digits"
        case createdAt = "created_at"
    }
}

struct SavedCardTokenizationContext: Decodable, Equatable, Identifiable {
    let savedCardID: UUID
    let cardID: String
    let holderName: String
    let documentNumber: String?
    let documentType: String

    var id: UUID { savedCardID }

    enum CodingKeys: String, CodingKey {
        case savedCardID = "saved_card_id"
        case cardID = "card_id"
        case holderName = "holder_name"
        case documentNumber = "document_number"
        case documentType = "document_type"
    }
}

enum SavedCardFailureReason: Equatable {
    case offline
    case timeout
    case sessionExpired
    case cardRejected
    case notFound
    case serviceUnavailable
    case unknown
}
