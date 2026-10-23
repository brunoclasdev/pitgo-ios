//
//  PitTecPricingRepository.swift
//  pitgo
//
//  Leitura somente-consulta do preço configurado do atendimento PitTec (aba "Valores", `022`) — sem
//  edição por esta tela (spec.md Clarifications, 2026-09-14). Reaproveita `CatalogService`/
//  `ProviderServiceRow` já existentes (`ProviderRegistrationDTOs.swift`) e o mesmo padrão de
//  resolver o serviço implícito por `dispatch_kind` já usado por
//  `ServiceCatalogRepository.fetchImplicitService` — PitTec sempre tem exatamente um serviço (`016`),
//  então basta uma leitura pontual, sem paginação.
//

import Foundation
import Supabase

enum PitTecPricingFetchResult {
    case success(PitTecPricingInfo)
    case notFound
    case offline
}

private struct CurrentServicePricingParams: Encodable { let p_service_id: UUID? }
private struct CurrentServicePricingResponse: Decodable {
    let pittec: [CurrentPitTecPrice]
}
private struct CurrentPitTecPrice: Decodable {
    let serviceID: UUID
    let version: Int64
    let price: Decimal
    let durationMinutes: Int
    enum CodingKeys: String, CodingKey {
        case serviceID = "service_id", version, price
        case durationMinutes = "duration_minutes"
    }
}

final class PitTecPricingRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchPitTecPrice(providerID: UUID) async -> PitTecPricingFetchResult {
        do {
            let services: [CatalogService] = try await client
                .from("services")
                .select()
                .eq("dispatch_kind", value: ServiceDispatchKind.pittecAutoSequential.rawValue)
                .eq("active", value: true)
                .limit(1)
                .execute()
                .value
            guard let service = services.first else { return .notFound }

            let response: CurrentServicePricingResponse = try await client
                .rpc("get_current_service_pricing", params: CurrentServicePricingParams(p_service_id: service.id))
                .execute()
                .value
            guard let price = response.pittec.first(where: { $0.serviceID == service.id }) else { return .notFound }

            return .success(PitTecPricingInfo(price: price.price, serviceName: service.name, durationMinutes: price.durationMinutes, version: price.version))
        } catch {
            return .offline
        }
    }
}
