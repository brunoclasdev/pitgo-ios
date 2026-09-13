//
//  ProviderMigrationModels.swift
//  pitgo
//
//  Migração assistida de empresa legada (CLIENT → nova conta PROVIDER, ver research.md §3 e
//  contracts/navigation-session.md "Assisted migration stack" de `009`). O desafio de 32 bytes em
//  texto plano nunca é `Codable`/persistido — vive somente em `ProviderMigrationCoordinator`
//  (escopo de processo).
//

import Foundation

enum ProviderMigrationBeginState: Equatable {
    case idle
    case beginning
    case pending(expiresAt: Date, requirements: String?)
    case failure(ProviderMigrationFailureReason)
}

enum ProviderMigrationClaimState: Equatable {
    case idle
    case claiming
    case succeeded
    case failure(ProviderMigrationFailureReason)
}

/// O contrato não define um vocabulário fechado de erro para begin/claim ("falha neutra" — ver
/// contracts/account-provider-database.md "Legacy ownership transfer") — apenas a classificação de
/// transporte abaixo é derivável com segurança.
enum ProviderMigrationFailureReason: Hashable {
    case offline
    case service
    case sessionExpired
    case expiredOrInvalid
    case unknown
}
