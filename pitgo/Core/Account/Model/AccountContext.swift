//
//  AccountContext.swift
//  pitgo
//
//  Mapeia `get_my_account_context()` (já existente e compartilhada, ver
//  contracts/account-provider-database.md de `009`) — a única autoridade de papel de conta.
//  `raw_user_meta_data` nunca autoriza nada; somente esta RPC decide CLIENT vs. PROVIDER.
//

import Foundation

struct AccountContext: Decodable {
    let accountType: AccountType
    let clientState: ClientState?
    let providerState: ProviderState?
    let providerID: UUID?
    let legacyProviderMigrationAvailable: Bool

    enum CodingKeys: String, CodingKey {
        case accountType = "account_type"
        case clientState = "client_state"
        case providerState = "provider_state"
        case providerID = "provider_id"
        case legacyProviderMigrationAvailable = "legacy_provider_migration_available"
    }
}

enum AccountType: String, Decodable {
    case client = "CLIENT"
    case provider = "PROVIDER"
}

enum ClientState: String, Decodable {
    case ready = "READY"
}

enum ProviderState: String, Decodable {
    case onboarding = "ONBOARDING"
    case ready = "READY"
    case incomplete = "INCOMPLETE"
}

/// Identidade autenticada mínima usada em `.authenticatedProviderOnboarding` — antes de existir um
/// `Provider` completo para carregar (ver data-model.md "AppSessionState").
struct AuthIdentity: Equatable {
    let userID: UUID
    let authEmail: String
}

/// Papel efetivo + `Provider` carregado para `.authenticatedProviderReady`. `accountID` é o owner
/// Auth substituível (`providers.account_id`); `provider.id` é o identificador estável da empresa —
/// os dois nunca devem ser confundidos (ver data-model.md "Relationship overview").
struct ProviderSnapshot {
    let accountID: UUID
    let authEmail: String
    let provider: Provider
    let legacyMigrationAvailable: Bool
}

/// Motivo de bloqueio da sessão — generaliza o antigo `ProfileBlockedReason` de `006` com os casos
/// novos de papel ausente/ambíguo ou Provider inconsistente (ver data-model.md "AppSessionState").
enum BlockedReason: Hashable {
    case profileMissing
    case profileInactive
    case profileInconsistent
    case roleMissing
    case roleAmbiguous
    case providerInconsistent
}

/// Resultado interno de `AccountRepository.fetchSnapshot` (006) — mapeado para `BlockedReason` por
/// `AccountContextRepository`.
enum ProfileBlockedReason {
    case missing
    case inactive
    case inconsistent
}
