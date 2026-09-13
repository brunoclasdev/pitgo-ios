//
//  ServiceMapRepository.swift
//  pitgo
//
//  Invoca somente `discover_service_providers` (já existente, ver
//  contracts/account-provider-database.md "Discovery" de `009`). Exige sessão CLIENT; nenhum ID de
//  owner é enviado — o filtro de serviço/categoria/disponibilidade é autoridade do servidor.
//

import Foundation
import Supabase

enum ServiceMapDiscoverResult {
    case success([ServiceMapResult])
    case sessionExpired
    case offline
    case service
    case unknown
}

final class ServiceMapRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func discover(
        serviceID: UUID,
        centerLatitude: Double,
        centerLongitude: Double,
        radiusMeters: Int,
        limit: Int = 200
    ) async -> ServiceMapDiscoverResult {
        let params = DiscoverServiceProvidersParams(
            p_service_id: serviceID,
            p_center_lat: centerLatitude,
            p_center_long: centerLongitude,
            p_radius_meters: radiusMeters,
            p_limit: limit
        )
        do {
            let results: [ServiceMapResult] = try await client
                .rpc("discover_service_providers", params: params)
                .execute()
                .value
            return .success(results)
        } catch {
            return classify(error)
        }
    }

    private func classify(_ error: Error) -> ServiceMapDiscoverResult {
        if let postgrestError = error as? PostgrestError {
            return postgrestError.code == "42501" ? .sessionExpired : .service
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return .offline
            default: return .service
            }
        }
        return .unknown
    }
}
