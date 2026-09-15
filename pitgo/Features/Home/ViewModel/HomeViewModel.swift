//
//  HomeViewModel.swift
//  pitgo
//
//  Combina o snapshot autenticado com o catálogo real de serviços (`list_home_services()`, ver
//  `009` — substitui `DemoServiceCatalog` de `003`). Mantém seu próprio fetch para atualizar após
//  uma mutação na Garagem, sem tocar em `SessionStore.state` (evitaria reconstruir a `TabView`
//  inteira a cada refresh).
//

import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var state: HomeUiState = .loading

    private let repository: AccountRepository
    private let catalogRepository: ServiceCatalogRepository
    private let userID: UUID
    private let authEmail: String

    let diagnostic = DiagnosticPrompt(
        title: "Não sei o que aconteceu",
        description: "Descreva o problema e sugerimos o serviço",
        symbolName: "sparkles"
    )

    init(repository: AccountRepository, catalogRepository: ServiceCatalogRepository, userID: UUID, authEmail: String) {
        self.repository = repository
        self.catalogRepository = catalogRepository
        self.userID = userID
        self.authEmail = authEmail
    }

    func load() async {
        async let accountResult = repository.fetchSnapshot(userID: userID, authEmail: authEmail)
        async let servicesResult = catalogRepository.fetchHomeServices()
        let services = await servicesResult

        switch await accountResult {
        case let .success(snapshot):
            state = snapshot.primaryVehicle != nil
                ? .content(snapshot, services: services)
                : .noVehicle(snapshot.profile, services: services)
        case .blocked, .offline:
            state = .failure(.unknown)
        }
    }

    func retryServices() {
        Task { [weak self] in
            guard let self else { return }
            let services = await catalogRepository.fetchHomeServices()
            switch state {
            case let .content(snapshot, _):
                state = .content(snapshot, services: services)
            case let .noVehicle(profile, _):
                state = .noVehicle(profile, services: services)
            case .loading, .failure:
                break
            }
        }
    }
}
