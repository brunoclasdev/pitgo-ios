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

            let offers: [ProviderServiceRow] = try await client
                .from("provider_services")
                .select()
                .eq("provider_id", value: providerID)
                .eq("service_id", value: service.id)
                .limit(1)
                .execute()
                .value
            guard let offer = offers.first else { return .notFound }

            return .success(PitTecPricingInfo(price: offer.price, serviceName: service.name))
        } catch {
            return .offline
        }
    }
}
