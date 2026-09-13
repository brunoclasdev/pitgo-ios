//
//  ProviderRegistrationDTOs.swift
//  pitgo
//
//  Mapeia o catálogo somente leitura e o agregado próprio (`public.providers`/`addresses`/
//  `provider_services`, já existentes e compartilhados com o Android — ver
//  contracts/supabase-provider-registration.md) e o payload/resultado da RPC
//  `create_provider_registration`. A coluna física de bairro é `addresses.neighbornhood` (grafia
//  legada preservada deliberadamente); o Swift expõe `neighborhood` via `CodingKeys`, mesma
//  estratégia de `Profile.isActive`/`active`. O JSONB de payload da RPC já espera a chave
//  `neighborhood` (grafia correta, distinta da coluna física) — sem `CodingKeys` nesse caso.
//

import Foundation

// MARK: - Read: catálogo somente leitura

struct ServiceCategory: Decodable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let description: String?
}

struct CatalogService: Decodable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let description: String?
    let categoryID: UUID
    /// Já existe na tabela `services`; passa a ser lido aqui para resolver o serviço implícito de
    /// Móvel/PitTec no cadastro (`016`) — `009` já decodifica o mesmo campo em `HomeServiceListing`.
    let dispatchKind: ServiceDispatchKind

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case categoryID = "category_id"
        case dispatchKind = "dispatch_kind"
    }
}

// MARK: - Read: agregado próprio

struct Provider: Decodable {
    /// Identificador estável da empresa — nunca o owner (ver data-model.md "Relationship overview"
    /// de `009`).
    let id: UUID
    /// Owner Auth substituível (`providers.account_id`); muda somente por migração assistida.
    let accountID: UUID
    let name: String
    let description: String?
    let email: String
    let phone: String
    let cnpj: String
    let locationMode: ProviderLocationMode
    let active: Bool
    let available: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, description, email, phone, cnpj, active, available
        case accountID = "account_id"
        case locationMode = "location_mode"
    }
}

enum ProviderLocationMode: String, Decodable, CaseIterable {
    case fixed = "FIXED"
    case mobile = "MOBILE"
    /// Terceira modalidade (`015`) — atendimento técnico sob demanda; despacho automático, sem
    /// serviço/preço escolhido pelo prestador (ver `016`).
    case pittec = "PITTEC"
}

struct ProviderAddress: Decodable {
    let id: UUID
    let street: String
    let number: String
    let neighborhood: String
    let zipCode: String
    let city: String
    let state: String
    let country: String
    let complement: String?
    let latitude: Decimal?
    let longitude: Decimal?

    enum CodingKeys: String, CodingKey {
        case id, street, number, city, state, country, complement, latitude, longitude
        case neighborhood = "neighbornhood"
        case zipCode = "zip_code"
    }
}

struct ProviderServiceRow: Decodable {
    let serviceID: UUID
    let price: Decimal
    let durationMinutes: Int
    let description: String?

    enum CodingKeys: String, CodingKey {
        case serviceID = "service_id"
        case price
        case durationMinutes = "duration_minutes"
        case description
    }
}

// MARK: - Write: payload da RPC (ver contracts/account-provider-database.md "Provider registration"
// de `009` — `p_address` foi removido: texto/ponto do endereço vêm da prova de geocodificação
// travada por `p_geocode_verification_id`, nunca de um argumento separado).

struct CreateProviderRegistrationParams: Encodable {
    let p_provider: ProviderPayload
    let p_offers: [OfferPayload]
    let p_geocode_verification_id: UUID
    let p_divergence_confirmed: Bool
}

struct ProviderPayload: Encodable {
    let name: String
    let description: String?
    let email: String
    let phone: String
    let cnpj: String
    let location_mode: String
}

struct OfferPayload: Encodable {
    let service_id: UUID
    /// Decimal canônica formatada como `String` (ponto decimal, até duas casas) — nunca `Double`,
    /// para nunca passar por ponto flutuante binário (ver research.md §9).
    let price: String
    let duration_minutes: Int
    let description: String?
    let is_free: Bool
}

// MARK: - Write: resultado da RPC
//
// O `outcome` cobre sucesso e falha de domínio no mesmo formato fechado (ver
// contracts/account-provider-database.md "Provider registration"). `provider_id`/`offer_count` só
// vêm preenchidos em `CREATED`/`ALREADY_REGISTERED`.

struct CreateProviderRegistrationResult: Decodable {
    enum Outcome: String, Decodable {
        case created = "CREATED"
        case alreadyRegistered = "ALREADY_REGISTERED"
        case geocodeExpired = "GEOCODE_EXPIRED"
        case divergenceConfirmationRequired = "DIVERGENCE_CONFIRMATION_REQUIRED"
        case catalogChanged = "CATALOG_CHANGED"
        case emailUnavailable = "EMAIL_UNAVAILABLE"
        case cnpjUnavailable = "CNPJ_UNAVAILABLE"
        case invalidInput = "INVALID_INPUT"
        case sessionBlocked = "SESSION_BLOCKED"
    }

    let outcome: Outcome
    let providerID: UUID?
    let offerCount: Int?

    enum CodingKeys: String, CodingKey {
        case outcome
        case providerID = "provider_id"
        case offerCount = "offer_count"
    }
}

// MARK: - Write: Edge Function `geocode-provider-address` (ver contracts/geocoding-edge-function.md)

struct GeocodeAddressPayload: Encodable {
    let street: String
    let number: String
    let neighborhood: String
    let zip_code: String
    let city: String
    let state: String
    let country: String
    let complement: String?
}

struct GeocodeDeviceFixPayload: Encodable {
    let latitude: Double
    let longitude: Double
    let accuracy_m: Double
    let captured_at: Date
}

struct GeocodeVerificationRequest: Encodable {
    let address: GeocodeAddressPayload
    let device_fix: GeocodeDeviceFixPayload
}

struct GeocodeVerificationResponse: Decodable {
    let outcome: Outcome
    let verificationID: UUID?
    let normalizedAddress: String?
    let distanceM: Double?
    let requiresConfirmation: Bool?
    let expiresAt: Date?

    enum Outcome: String, Decodable {
        case verified = "VERIFIED"
        case noMatch = "NO_MATCH"
        case ambiguousOrPartial = "AMBIGUOUS_OR_PARTIAL"
        case wrongRegion = "WRONG_REGION"
        case fixTooOld = "FIX_TOO_OLD"
        case fixTooImprecise = "FIX_TOO_IMPRECISE"
        case invalidAddress = "INVALID_ADDRESS"
        case rateLimited = "RATE_LIMITED"
        case upstreamUnavailable = "UPSTREAM_UNAVAILABLE"
        case sessionBlocked = "SESSION_BLOCKED"
    }

    enum CodingKeys: String, CodingKey {
        case outcome
        case verificationID = "verification_id"
        case normalizedAddress = "normalized_address"
        case distanceM = "distance_m"
        case requiresConfirmation = "requires_confirmation"
        case expiresAt = "expires_at"
    }
}
