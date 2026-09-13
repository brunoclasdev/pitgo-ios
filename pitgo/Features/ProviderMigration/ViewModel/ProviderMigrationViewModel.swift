//
//  ProviderMigrationViewModel.swift
//  pitgo
//
//  Dois ViewModels pequenos para as duas metades da migração assistida — cada um vive numa sessão
//  autenticada diferente (CLIENT depois PROVIDER), unidas apenas pelo desafio em
//  `ProviderMigrationCoordinator` (ver contracts/navigation-session.md "Assisted migration stack").
//

import Foundation

@Observable
@MainActor
final class ProviderMigrationStartViewModel {
    private(set) var state: ProviderMigrationBeginState = .idle

    private let repository: ProviderMigrationRepository
    private let coordinator: ProviderMigrationCoordinator

    init(repository: ProviderMigrationRepository, coordinator: ProviderMigrationCoordinator) {
        self.repository = repository
        self.coordinator = coordinator
    }

    func begin() {
        guard state != .beginning else { return }
        state = .beginning
        let token = coordinator.generateToken()
        Task { [weak self] in
            guard let self else { return }
            switch await repository.begin(token: token) {
            case let .pending(expiresAt, requirements):
                coordinator.markPending(expiresAt: expiresAt)
                state = .pending(expiresAt: expiresAt, requirements: requirements)
            case let .failure(reason):
                coordinator.clear()
                state = .failure(reason)
            }
        }
    }

    func cancel() {
        coordinator.clear()
        state = .idle
    }
}

@Observable
@MainActor
final class ProviderMigrationClaimViewModel {
    private(set) var state: ProviderMigrationClaimState = .idle
    private(set) var claimedProviderID: UUID?

    private let repository: ProviderMigrationRepository
    private let coordinator: ProviderMigrationCoordinator

    init(repository: ProviderMigrationRepository, coordinator: ProviderMigrationCoordinator) {
        self.repository = repository
        self.coordinator = coordinator
    }

    var hasPendingChallenge: Bool {
        coordinator.activeToken != nil
    }

    func claim(locationMode: ProviderLocationMode) {
        guard state != .claiming, let token = coordinator.activeToken else {
            state = .failure(.expiredOrInvalid)
            return
        }
        state = .claiming
        Task { [weak self] in
            guard let self else { return }
            let result = await repository.claim(
                token: token,
                locationMode: locationMode,
                geocodeVerificationID: nil,
                divergenceConfirmed: false
            )
            switch result {
            case let .migrated(providerID), let .alreadyMigrated(providerID):
                coordinator.clear()
                claimedProviderID = providerID
                state = .succeeded
            case let .failure(reason):
                state = .failure(reason)
            }
        }
    }
}
