//
//  VehicleOnboardingStore.swift
//  pitgo
//
//  Preferência local simples (`UserDefaults`) do convite pós-cadastro pendente, por `userID`
//  (ver data-model.md §6). Não armazena escolha, veículo, documento, senha ou token.
//

import Foundation

struct VehicleOnboardingStore {
    private let defaults: UserDefaults
    private let key = "pitgo.pendingVehicleOnboarding"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func markPending(_ userID: UUID) {
        var pending = storedIDs()
        pending.insert(userID.uuidString)
        defaults.set(Array(pending), forKey: key)
    }

    func isPending(_ userID: UUID) -> Bool {
        storedIDs().contains(userID.uuidString)
    }

    func resolve(_ userID: UUID) {
        var pending = storedIDs()
        pending.remove(userID.uuidString)
        defaults.set(Array(pending), forKey: key)
    }

    private func storedIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }
}
