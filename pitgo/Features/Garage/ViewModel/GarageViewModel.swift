//
//  GarageViewModel.swift
//  pitgo
//

import Combine
import Foundation

@MainActor
final class GarageViewModel: ObservableObject {
    @Published private(set) var state: GarageUiState = .loading
    /// Última linha autoritativa de `set_primary_vehicle` — a View observa esta propriedade para
    /// atualizar `SessionStore.applyAuthoritativePrimaryVehicle(_:)` (`012`), sem acoplar este
    /// ViewModel à sessão.
    @Published private(set) var confirmedPrimaryVehicle: Vehicle?

    private let repository: VehicleRepository
    private let userID: UUID

    init(repository: VehicleRepository, userID: UUID) {
        self.repository = repository
        self.userID = userID
    }

    func load() async {
        state = .loading
        guard let vehicles = await repository.listActiveVehicles(userID: userID) else {
            state = .failure(.unknown)
            return
        }
        state = vehicles.isEmpty ? .empty : .content(vehicles, changingPrimaryVehicleID: nil)
    }

    /// Toques concorrentes são ignorados enquanto uma troca de principal está em andamento
    /// (ver contracts/navigation.md "Garage flow").
    func selectPrimary(_ vehicleID: UUID) {
        guard case let .content(vehicles, changing) = state, changing == nil else { return }
        state = .content(vehicles, changingPrimaryVehicleID: vehicleID)

        Task { [weak self] in
            guard let self else { return }
            let result = await repository.setPrimary(vehicleID: vehicleID)
            if case let .success(vehicle) = result {
                confirmedPrimaryVehicle = vehicle
                await load()
            } else if case let .content(current, _) = state {
                state = .content(current, changingPrimaryVehicleID: nil)
            }
        }
    }
}
