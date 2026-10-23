//
//  EnvironmentStateRepository.swift
//  pitgo
//
//  `027`: só um ambiente fica instalado por vez neste app (mesmo bundle identifier para Dev/Homol/
//  Prod — ver project.pbxproj) — uma atualização que troca de ambiente substitui a anterior sem
//  limpar o sandbox. `validate(clearIncompatible:)` compara o fingerprint do ambiente ativo com o
//  último gravado em `UserDefaults`; se divergir (primeira instalação, versão legada sem
//  fingerprint, ou troca Dev/Homol/Prod), executa `clearIncompatible` ANTES de gravar o novo
//  fingerprint — nunca reaproveita sessão ou estado local de um ambiente diferente (FR-009/FR-010).
//  Mesma estratégia do `EnvironmentStateRepository`/`PitGoAppContainer` do Android, adaptada para
//  `UserDefaults` (suficiente para um único valor síncrono, sem precisar de um Keychain/DataStore).
//

import Foundation

struct EnvironmentStateRepository {
    private static let fingerprintKey = "pitgo.environment.fingerprint"

    private let defaults: UserDefaults
    private let environment: EnvironmentConfig

    init(defaults: UserDefaults = .standard, environment: EnvironmentConfig = .current) {
        self.defaults = defaults
        self.environment = environment
    }

    func validate(clearIncompatible: () async -> Void) async {
        guard defaults.string(forKey: Self.fingerprintKey) != environment.fingerprint else { return }
        await clearIncompatible()
        defaults.set(environment.fingerprint, forKey: Self.fingerprintKey)
    }
}
