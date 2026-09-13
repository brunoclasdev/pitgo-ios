//
//  ServiceCatalogRepository.swift
//  pitgo
//
//  Catálogo real e ativo compartilhado por Home (`list_home_services`) e cadastro de provider
//  (`service_categories`/`services`, já existentes — ver `007`, agora filtrados por `active`).
//

import Foundation
import Supabase

final class ServiceCatalogRepository {
    private static let pageSize = 200

    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    /// Serviços reais para os cards da Home — substitui `DemoServiceCatalog` (`003`).
    func fetchHomeServices() async -> LoadState<[HomeServiceListing]> {
        do {
            let listings: [HomeServiceListing] = try await client
                .rpc("list_home_services")
                .execute()
                .value
            return listings.isEmpty ? .empty : .content(listings)
        } catch {
            return .failure(reason: "home_services")
        }
    }

    func fetchCategories() async -> LoadState<[ServiceCategory]> {
        do {
            var all: [ServiceCategory] = []
            var offset = 0
            while true {
                let page: [ServiceCategory] = try await client
                    .from("service_categories")
                    .select()
                    .eq("active", value: true)
                    .order("name", ascending: true)
                    .order("id", ascending: true)
                    .range(from: offset, to: offset + Self.pageSize - 1)
                    .execute()
                    .value
                all += page
                if page.count < Self.pageSize { break }
                offset += Self.pageSize
            }
            return all.isEmpty ? .empty : .content(all)
        } catch {
            return .failure(reason: "categories")
        }
    }

    func fetchServices(categoryID: UUID) async -> LoadState<[CatalogService]> {
        do {
            var all: [CatalogService] = []
            var offset = 0
            while true {
                let page: [CatalogService] = try await client
                    .from("services")
                    .select()
                    .eq("category_id", value: categoryID)
                    .eq("active", value: true)
                    .order("name", ascending: true)
                    .order("id", ascending: true)
                    .range(from: offset, to: offset + Self.pageSize - 1)
                    .execute()
                    .value
                all += page.filter { $0.categoryID == categoryID }
                if page.count < Self.pageSize { break }
                offset += Self.pageSize
            }
            return all.isEmpty ? .empty : .content(all)
        } catch {
            return .failure(reason: "services")
        }
    }

    /// Localiza o serviço único de um `dispatchKind` (Guincho/PitTec, `016`) — nunca escolhe entre
    /// múltiplos candidatos nem cria/ativa nada; só lê `public.services`.
    func fetchImplicitService(dispatchKind: ServiceDispatchKind) async -> ImplicitServiceResolution {
        do {
            let services: [CatalogService] = try await client
                .from("services")
                .select()
                .eq("dispatch_kind", value: dispatchKind.rawValue)
                .eq("active", value: true)
                .limit(2)
                .execute()
                .value
            switch services.count {
            case 0: return .missing
            case 1: return .found(services[0])
            default: return .duplicated
            }
        } catch {
            return .missing
        }
    }
}
