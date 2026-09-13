//
//  AccountContextRepository.swift
//  pitgo
//
//  Camada única que consulta `get_my_account_context()` e carrega o agregado específico do papel
//  retornado (ver research.md §1 e contracts/account-provider-database.md de `009`). Nenhum destino
//  cai para um papel padrão quando o contexto está ausente/ambíguo.
//

import Foundation
import Supabase

enum AccountContextResult {
    case client(AccountSnapshot)
    case providerOnboarding(AuthIdentity)
    case providerReady(ProviderSnapshot)
    case blocked(BlockedReason)
    case offline
}

final class AccountContextRepository {
    private let client: SupabaseClient
    private let accountRepository: AccountRepository

    init(client: SupabaseClient) {
        self.client = client
        accountRepository = AccountRepository(client: client)
    }

    func fetchContext(userID: UUID, authEmail: String) async -> AccountContextResult {
        let context: AccountContext
        do {
            context = try await client.rpc("get_my_account_context").execute().value
        } catch is CancellationError {
            return .offline
        } catch {
            return .offline
        }

        switch context.accountType {
        case .client:
            return await fetchClient(
                userID: userID,
                authEmail: authEmail,
                legacyProviderMigrationAvailable: context.legacyProviderMigrationAvailable
            )
        case .provider:
            return await fetchProvider(context: context, userID: userID, authEmail: authEmail)
        }
    }

    private func fetchClient(userID: UUID, authEmail: String, legacyProviderMigrationAvailable: Bool) async -> AccountContextResult {
        switch await accountRepository.fetchSnapshot(userID: userID, authEmail: authEmail) {
        case var .success(snapshot):
            snapshot.legacyProviderMigrationAvailable = legacyProviderMigrationAvailable
            return .client(snapshot)
        case let .blocked(reason):
            return .blocked(map(reason))
        case .offline:
            return .offline
        }
    }

    private func fetchProvider(context: AccountContext, userID: UUID, authEmail: String) async -> AccountContextResult {
        switch context.providerState {
        case .ready:
            guard let providerID = context.providerID else { return .blocked(.providerInconsistent) }
            return await fetchProviderSnapshot(
                providerID: providerID,
                accountID: userID,
                authEmail: authEmail,
                legacyMigrationAvailable: context.legacyProviderMigrationAvailable
            )
        case .onboarding, .incomplete, nil:
            return .providerOnboarding(AuthIdentity(userID: userID, authEmail: authEmail))
        }
    }

    private func fetchProviderSnapshot(
        providerID: UUID,
        accountID: UUID,
        authEmail: String,
        legacyMigrationAvailable: Bool
    ) async -> AccountContextResult {
        do {
            let providers: [Provider] = try await client
                .from("providers")
                .select()
                .eq("id", value: providerID)
                .limit(1)
                .execute()
                .value
            guard let provider = providers.first, provider.accountID == accountID else {
                return .blocked(.providerInconsistent)
            }
            return .providerReady(ProviderSnapshot(
                accountID: accountID,
                authEmail: authEmail,
                provider: provider,
                legacyMigrationAvailable: legacyMigrationAvailable
            ))
        } catch {
            return .offline
        }
    }

    private func map(_ reason: ProfileBlockedReason) -> BlockedReason {
        switch reason {
        case .missing: .profileMissing
        case .inactive: .profileInactive
        case .inconsistent: .profileInconsistent
        }
    }
}
