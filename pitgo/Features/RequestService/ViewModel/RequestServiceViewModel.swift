//
//  RequestServiceViewModel.swift
//  pitgo
//
//  Resolve o serviço por UUID a partir do catálogo real (`list_home_services`, compartilhado com a
//  Home) — nunca recorre ao catálogo demo de `003` (ver plan.md "Bateria/preço demo" de `010`). O
//  `providerID` recebido da descoberta por mapa é opaco e só é usado no callback mockado de
//  confirmação, nunca em uma chamada real (esta feature permanece mockada nesta entrega).
//

import Combine
import Foundation

@MainActor
final class RequestServiceViewModel: ObservableObject {
    @Published private(set) var state: RequestServiceUiState = .loading

    private let serviceID: UUID
    private let providerID: UUID
    private let catalogRepository: ServiceCatalogRepository

    init(serviceID: UUID, providerID: UUID, catalogRepository: ServiceCatalogRepository) {
        self.serviceID = serviceID
        self.providerID = providerID
        self.catalogRepository = catalogRepository
    }

    func load() {
        state = .loading
        Task { [weak self] in
            guard let self else { return }
            let result = await catalogRepository.fetchHomeServices()
            switch result {
            case let .content(listings):
                if let listing = listings.first(where: { $0.serviceID == serviceID }) {
                    state = .content(RequestServiceContent(
                        serviceID: serviceID,
                        providerID: providerID,
                        serviceName: listing.serviceName,
                        categoryName: listing.categoryName,
                        description: listing.serviceDescription,
                        minimumPrice: listing.minimumPrice
                    ))
                } else {
                    state = .invalid
                }
            case .empty:
                state = .invalid
            case .loading, .failure:
                state = .failure
            }
        }
    }

    func retry() {
        load()
    }

    /// Confirmação mockada — nenhuma RPC/Edge Function é chamada nesta entrega (ver data-model.md
    /// "RequestServiceSelection").
    func confirm() {
        guard case let .content(content) = state else { return }
        state = .confirmed(content)
    }
}
