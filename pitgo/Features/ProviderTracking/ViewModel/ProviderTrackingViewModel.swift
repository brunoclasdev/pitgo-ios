//
//  ProviderTrackingViewModel.swift
//  pitgo
//
//  Valida elegibilidade (provider MOBILE/ativo/disponível) e solicita o início do tracking sem
//  possuir o loop — quem possui o estado é `ProviderTrackingStateRepository` (processo, injetado).
//

import Combine
import Foundation

@MainActor
final class ProviderTrackingViewModel: ObservableObject {
    let appointmentID: UUID
    @Published private(set) var eligibilityFailure: TrackingDegradedReason?

    private let stateRepository: ProviderTrackingStateRepository
    private let dashboardRepository: ProviderDashboardRepository
    private let accountID: UUID
    /// Repassa as mudanças de `stateRepository` (dono real do estado) para esta ViewModel — sem
    /// isto, `objectWillChange` nunca dispararia quando só `stateRepository.state` mudasse.
    private var cancellables = Set<AnyCancellable>()

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
        stateRepository.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
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
