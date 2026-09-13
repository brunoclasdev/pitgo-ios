//
//  ClientAddressModels.swift
//  pitgo
//
//  Endereço do cliente (`014`) — backend já compartilhado (`public.client_addresses`,
//  `get_my_client_address`/`upsert_my_client_address`, confirmados via `pg_get_functiondef` nesta
//  sessão). Diferente do endereço do prestador (`007`/`009`), não há verificação/geocodificação
//  travada aqui — a RPC só exige lat/lon numéricos, preenchidos com uma leitura pontual de GPS no
//  momento de salvar (mesma captura pontual já usada em outras telas, nunca inventada).
//

import Foundation

struct ClientAddress: Decodable, Equatable {
    let street: String
    let number: String
    let neighborhood: String
    let zipCode: String
    let city: String
    let state: String
    let complement: String?
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey {
        case street, number, neighborhood
        case zipCode = "zip_code"
        case city, state, complement, latitude, longitude
    }
}

struct ClientAddressDraft: Equatable {
    var street: String = ""
    var number: String = ""
    var neighborhood: String = ""
    var postalCode: String = ""
    var city: String = ""
    var state: BrazilianState?
    var complement: String = ""
    // País é sempre "BR" — sem seleção, mesma convenção do cadastro de empresa (`007`).

    // Reaproveita o mesmo mecanismo de busca por CEP do cadastro de empresa (`011`).
    var postalCodeLookup: PostalCodeLookupState = .idle
    var cepAutofillProvenance: CepAutofillProvenance?
}

enum ClientAddressFieldError: Hashable {
    case required
    case invalidFormat
    case notFound
}

enum ClientAddressField: Hashable, CaseIterable {
    case postalCode, street, number, complement, neighborhood, city, state
}

enum ClientAddressFetchState {
    case loading
    case notFound
    case found(ClientAddress)
    case failure
}

enum ClientAddressSubmission: Equatable {
    case idle
    case submitting
    case failure(ClientAddressFailureReason)

    static func == (lhs: ClientAddressSubmission, rhs: ClientAddressSubmission) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.submitting, .submitting): true
        case let (.failure(a), .failure(b)): a == b
        default: false
        }
    }
}

enum ClientAddressFailureReason: Hashable {
    case invalidInput
    case locationRequired
    case sessionExpired
    case offline
    case service
    case unknown
}

enum ClientAddressUiState {
    case loading
    case editing(draft: ClientAddressDraft, fieldErrors: [ClientAddressField: ClientAddressFieldError], submission: ClientAddressSubmission, savedAddress: ClientAddress?)
    case sessionExpired
}
