//
//  SavedCardDTOs.swift
//  pitgo
//
//  Formatos de `mp-save-card`/`mp-remove-card` confirmados lendo o código-fonte real das duas Edge
//  Functions nesta sessão.
//

import Foundation

struct SaveCardRequestBody: Encodable {
    let card_token: String
}

struct SaveCardResponse: Decodable {
    let savedCardID: UUID
    let brand: String
    let lastFourDigits: String

    enum CodingKeys: String, CodingKey {
        case savedCardID = "saved_card_id"
        case brand
        case lastFourDigits = "last_four_digits"
    }
}

struct RemoveCardRequestBody: Encodable {
    let saved_card_id: UUID
}
