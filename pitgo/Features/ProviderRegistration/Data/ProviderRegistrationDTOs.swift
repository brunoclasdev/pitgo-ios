//
//  ProviderRegistrationDTOs.swift
//  pitgo
//
//  Mapeia o catálogo somente leitura e o agregado próprio (`public.providers`/`addresses`/
//  `provider_services`, já existentes e compartilhados com o Android) e o payload/resultado da RPC
//  `create_provider_registration`.
//
//  ACHADO desta sessão (reproduzido em device físico real: cadastro criava a empresa no servidor,
//  mas o app mostrava "Alguns dados não puderam ser aceitos" mesmo assim): a coluna física de bairro
//  já foi `addresses.neighbornhood` (grafia legada), mas a migration `20260821050000_provider_
//  neighborhood_contract` (conferida no repo Android, mesmo backend) renomeou pra `neighborhood`
//  (grafia correta) fazia tempo — `ProviderAddress.CodingKeys` ainda mapeava pro nome antigo, então
//  `fetchOwnAggregate` falhava ao decodificar `addresses` toda vez logo depois do `INSERT` já ter
//  sido confirmado na mesma transação da RPC.
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
    let providerKind: ProviderKind?
    let active: Bool
    let available: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, description, email, phone, cnpj, active, available
        case accountID = "account_id"
        case locationMode = "location_mode"
        case providerKind = "provider_kind"
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
        case id, street, number, neighborhood, city, state, country, complement, latitude, longitude
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

// MARK: - Write: payload da RPC
//
// `contracts/account-provider-database.md` (`009`) documenta `p_address` como removido em favor de
// `p_geocode_verification_id` — desatualizado: a função real (conferida no fonte do repo Android,
// mesmo backend, e via chamada direta ao PostgREST nesta sessão) recebe `p_provider`/`p_address`/
// `p_offers`, com o token da prova dentro de `p_address.verification_token`. Ver nota em
// `ProviderAddressVerificationState`.

struct CreateProviderRegistrationParams: Encodable {
    let p_provider: ProviderPayload
    let p_address: AddressPayload
    let p_offers: [OfferPayload]
}

struct ProviderPayload: Encodable {
    let name: String
    let description: String?
    let email: String
    let phone: String
    let cnpj: String
    let location_mode: String
    let provider_kind: String
    let vehicle: ProviderVehiclePayload?
}

struct ProviderVehiclePayload: Encodable {
    let plate: String
    let make: String
    let model: String
    let color: String
}

struct AddressPayload: Encodable {
    let street: String
    let number: String
    let neighborhood: String
    let zip_code: String
    let city: String
    let state: String
    let country: String
    let complement: String?
    let verification_token: String
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
// Só `CREATED`/`ALREADY_REGISTERED` chegam como um 200 decodificável — toda falha de domínio
// (`LOCATION_VERIFICATION_REQUIRED`, `INVALID_ADDRESS`, `OFFER_REQUIRED`, `DUPLICATE_SERVICE`,
// `PROVIDER_REQUIRED`, unique violation de e-mail/CNPJ etc.) é uma exceção Postgres (`raise
// exception`), nunca um `outcome` fechado num corpo de sucesso — confirmado lendo a função real
// (fonte no repo Android) e reproduzindo em device físico real. `ProviderRegistrationRepository.
// classify(_:)` já cobre esses códigos via `catch`, então nenhuma mudança foi necessária ali.
// `provider_id`/`offer_count` só vêm preenchidos nos dois outcomes abaixo.

struct CreateProviderRegistrationResult: Decodable {
    enum Outcome: String, Decodable {
        case created = "CREATED"
        case alreadyRegistered = "ALREADY_REGISTERED"
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

// MARK: - Write: Edge Function `geocode-provider-address`
//
// `contracts/geocoding-edge-function.md` (`009`) documenta um fix de GPS do dispositivo comparado
// contra o endereço geocodificado (`device_fix`, `outcome` com `FIX_TOO_OLD`/`WRONG_REGION`/etc.,
// `verification_id` como UUID) — desatualizado: o Edge Function real (fonte no repo Android, mesmo
// backend) só geocodifica o texto do endereço via MapTiler, sem nenhum fix de GPS. Toda falha chega
// via status HTTP não-2xx com `{code: "..."}` no corpo (`ProviderAddressVerificationRepository.
// classify(_:)`), nunca como um `outcome` de erro dentro de um 200.

struct GeocodeAddressPayload: Encodable {
    let street: String
    let number: String
    let neighborhood: String
    let zip_code: String
    let city: String
    let state: String
    let country: String
}

struct GeocodeVerificationRequest: Encodable {
    let address: GeocodeAddressPayload
}

struct GeocodeVerificationResponse: Decodable {
    let verificationToken: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case verificationToken = "verification_token"
        case expiresAt = "expires_at"
    }
}
