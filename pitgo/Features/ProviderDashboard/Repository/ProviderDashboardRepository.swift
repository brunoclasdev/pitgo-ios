//
//  ProviderDashboardRepository.swift
//  pitgo
//
//  Lê o Provider próprio e invoca `set_my_provider_mode`/`set_provider_availability` (ver
//  contracts/account-provider-database.md "Provider settings" de `009` — documentado lá como
//  `set_my_provider_availability`, mas o schema cache atual só tem `set_provider_availability`,
//  sem o "my_"; confirmado nesta sessão via chamada direta ao PostgREST, ver `setAvailability`).
//  Owner é sempre derivado de `auth.uid()` no servidor — nenhum ID é enviado pelo client.
//
//  ATENÇÃO: `set_my_provider_mode` (usado por `setMode`) também não foi encontrado no schema cache
//  na mesma verificação (nem a variante sem "my_") — a troca de Modalidade (Fixo/Móvel) em
//  `ProviderDashboardView` está com o mesmo tipo de falha, mas o nome real da função não foi
//  confirmado; precisa de acesso à secret key/painel do Supabase para achar o nome certo.
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
            // `set_provider_availability` (sem "my_") — nome real da função no schema cache atual
            // (confirmado via chamada direta ao PostgREST nesta sessão: `set_my_provider_availability`
            // retorna PGRST202 "Could not find the function", com hint apontando para este nome).
            let rows: [Provider] = try await client
                .rpc("set_provider_availability", params: SetAvailabilityParams(p_available: available))
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
