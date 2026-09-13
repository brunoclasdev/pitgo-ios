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

enum SavedCardFailureReason: Equatable {
    case offline
    case timeout
    case sessionExpired
    case cardRejected
    case notFound
    case serviceUnavailable
    case unknown
}
