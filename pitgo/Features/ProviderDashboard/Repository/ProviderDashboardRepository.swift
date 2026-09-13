//
//  ProviderDashboardRepository.swift
//  pitgo
//
//  Lê o Provider próprio e invoca `set_my_provider_mode`/`set_my_provider_availability` (já
//  existentes, ver contracts/account-provider-database.md "Provider settings" de `009`). Owner é
//  sempre derivado de `auth.uid()` no servidor — nenhum ID é enviado pelo client.
//

import Foundation
import Supabase

enum ProviderFetchResult {
    case success(Provider)
    case notFound
    case offline
}

enum ProviderSettingsResult {
    case success(Provider)
    case sessionExpired
    case offline
    case service
    case unknown
}

final class ProviderDashboardRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchProvider(accountID: UUID) async -> ProviderFetchResult {
        do {
            let providers: [Provider] = try await client
                .from("providers")
                .select()
                .eq("account_id", value: accountID)
                .limit(1)
                .execute()
                .value
            guard let provider = providers.first else { return .notFound }
            return .success(provider)
        } catch {
            return .offline
        }
    }

    private struct SetModeParams: Encodable { let p_mode: String }
    private struct SetAvailabilityParams: Encodable { let p_available: Bool }

    /// Mudar para `.fixed` apaga a localização corrente na mesma transação (backend, inalterado).
    func setMode(_ mode: ProviderLocationMode) async -> ProviderSettingsResult {
        do {
            let rows: [Provider] = try await client
                .rpc("set_my_provider_mode", params: SetModeParams(p_mode: mode.rawValue))
                .execute()
                .value
            guard let provider = rows.first else { return .unknown }
            return .success(provider)
        } catch {
            return classify(error)
        }
    }

    func setAvailability(_ available: Bool) async -> ProviderSettingsResult {
        do {
            let rows: [Provider] = try await client
                .rpc("set_my_provider_availability", params: SetAvailabilityParams(p_available: available))
                .execute()
                .value
            guard let provider = rows.first else { return .unknown }
            return .success(provider)
        } catch {
            return classify(error)
        }
    }

    private func classify(_ error: Error) -> ProviderSettingsResult {
        if let postgrestError = error as? PostgrestError {
            return postgrestError.code == "42501" ? .sessionExpired : .service
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return .offline
            default:
                return .service
            }
        }
        return .unknown
    }
}
