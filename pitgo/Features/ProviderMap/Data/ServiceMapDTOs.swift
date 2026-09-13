//
//  ServiceMapDTOs.swift
//  pitgo
//
//  Payload/resultado de `discover_service_providers` (já existente, ver
//  contracts/account-provider-database.md "Discovery" de `009`). O contrato descreve a projeção
//  pública apenas semanticamente (ver data-model.md "ServiceMapResult") — as chaves abaixo seguem a
//  convenção `snake_case` já usada por toda RPC deste projeto; não há como confirmar contra o
//  projeto Supabase real nesta sessão (sem credenciais), ver tasks.md. Nunca contém UUID de conta,
//  CNPJ, e-mail, telefone, endereço textual ou ponto de cliente/móvel corrente.
//

import Foundation

struct DiscoverServiceProvidersParams: Encodable {
    let p_service_id: UUID
    let p_center_lat: Double
    let p_center_long: Double
    let p_radius_meters: Int
    let p_limit: Int
}

struct ServiceMapResult: Decodable, Identifiable {
    let id: UUID
    let displayName: String
    let locationMode: ProviderLocationMode
    let latitude: Double
    let longitude: Double
    let serviceSummary: String
    let minimumPrice: Decimal?
    let distanceMeters: Double?

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude
        case displayName = "display_name"
        case locationMode = "location_mode"
        case serviceSummary = "service_summary"
        case minimumPrice = "minimum_price"
        case distanceMeters = "distance_meters"
    }
}
