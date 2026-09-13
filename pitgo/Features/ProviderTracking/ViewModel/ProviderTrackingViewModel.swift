//
//  ProviderTrackingViewModel.swift
//  pitgo
//
//  Valida elegibilidade (provider MOBILE/ativo/disponível) e solicita o início do tracking sem
//  possuir o loop — quem possui o estado é `ProviderTrackingStateRepository` (processo, injetado).
//

import Foundation

@Observable
@MainActor
final class ProviderTrackingViewModel {
    let appointmentID: UUID
    private(set) var eligibilityFailure: TrackingDegradedReason?

    private let stateRepository: ProviderTrackingStateRepository
    private let dashboardRepository: ProviderDashboardRepository
    private let accountID: UUID

    var state: ProviderTrackingState { stateRepository.state }

    init(
        appointmentID: UUID,
        accountID: UUID,
        stateRepository: ProviderTrackingStateRepository,
        dashboardRepository: ProviderDashboardRepository
    ) {
        self.appointmentID = appointmentID
        self.accountID = accountID
        self.stateRepository = stateRepository
        self.dashboardRepository = dashboardRepository
    }

    /// Ação visível exigida pelo contrato antes de solicitar `.authorizedAlways` (ver research.md
    /// §8) — disparada pelo botão "Iniciar" na View, nunca automaticamente.
    func start() {
        eligibilityFailure = nil
        Task { [weak self] in
            guard let self else { return }
            switch await dashboardRepository.fetchProvider(accountID: accountID) {
            case let .success(provider):
                guard provider.locationMode == .mobile, provider.active, provider.available else {
                    eligibilityFailure = .notEligible
                    return
                }
                stateRepository.requestAlwaysAuthorizationIfNeeded()
                stateRepository.start(appointmentID: appointmentID)
            case .notFound:
                eligibilityFailure = .notEligible
            case .offline:
                eligibilityFailure = .offline
            }
        }
    }

    func stop() {
        stateRepository.stop()
    }
}
