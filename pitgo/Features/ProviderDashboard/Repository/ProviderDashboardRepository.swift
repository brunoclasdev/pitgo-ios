//
//  ProviderDashboardRepository.swift
//  pitgo
//
//  Lê o Provider próprio e invoca `set_provider_availability` (ver `updateSettings`). Owner é
//  sempre derivado de `auth.uid()` no servidor — nenhum ID é enviado pelo client.
//
//  ACHADO desta sessão (reproduzido em device físico real: toggle de disponibilidade sempre dava
//  "Não foi possível concluir a ação"): não existem mais `set_my_provider_mode`/`set_provider_mode`
//  standalone — a função real (conferida no fonte da migration no repo Android, mesmo backend,
//  `set_provider_availability(p_available boolean, p_location_mode text default null)`) unificou
//  disponibilidade e modalidade numa RPC só, e devolve um `jsonb` único
//  `{provider_id,available,location_mode,pending_location_mode}` — nunca mais a linha inteira de
//  `providers` como array. `setAvailability`/`setMode` decodificavam `[Provider]`, o que sempre
//  lançava um erro de decodificação (nem `PostgrestError` nem `URLError` — caía direto em
//  `.unknown` no `classify`, por isso a mensagem genérica). Corrigido decodificando só os dois
//  campos e mesclando no snapshot que o ViewModel já tem em mãos (mesmo padrão do Android,
//  `ProviderDashboardViewModel.mutate`, que sempre manda os dois parâmetros juntos).
//

import Foundation
import Supabase

enum ProviderFetchResult {
    case success(Provider)
    case notFound
    case offline
}

enum ProviderSettingsResult {
    case success(ProviderAvailabilityUpdate)
    case sessionExpired
    case offline
    case service
    case unknown
}

/// Resposta de `set_provider_availability` — só o que a RPC unificada realmente devolve, nunca a
/// linha inteira de `providers` (ver nota no topo do arquivo). `pendingLocationMode` reflete uma
/// troca de modalidade adiada pelo servidor por ter um atendimento ativo em andamento (mesma regra
/// de negócio do Android, `mutate`/`ProviderDashboardUiState`) — o iOS ainda não tem UI dedicada
/// pra isso, só preserva o valor caso passe a precisar.
struct ProviderAvailabilityUpdate: Decodable {
    let available: Bool
    let locationMode: ProviderLocationMode
    let pendingLocationMode: ProviderLocationMode?

    enum CodingKeys: String, CodingKey {
        case available
        case locationMode = "location_mode"
        case pendingLocationMode = "pending_location_mode"
    }
}

extension Provider {
    /// Aplica só `available`/`locationMode` (e ignora `pendingLocationMode` por enquanto, ver nota
    /// em `ProviderAvailabilityUpdate`) sobre o snapshot já em mãos — `set_provider_availability`
    /// não devolve mais a linha inteira de `providers`.
    func applying(_ update: ProviderAvailabilityUpdate) -> Provider {
        Provider(
            id: id, accountID: accountID, name: name, description: description,
            email: email, phone: phone, cnpj: cnpj,
            locationMode: update.locationMode, providerKind: providerKind,
            active: active, available: update.available
        )
    }
}

final class ProviderDashboardRepository {
    let client: SupabaseClient

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

    private struct SetAvailabilityParams: Encodable {
        let p_available: Bool
        let p_location_mode: String
    }

    /// Sempre manda os dois parâmetros — o que não mudou vem do valor atual do snapshot (mesmo
    /// padrão do Android, `ProviderDashboardViewModel.mutate`). Mudar para `.fixed` apaga a
    /// localização corrente na mesma transação (backend, inalterado).
    func updateSettings(available: Bool, locationMode: ProviderLocationMode) async -> ProviderSettingsResult {
        do {
            let update: ProviderAvailabilityUpdate = try await client
                .rpc("set_provider_availability", params: SetAvailabilityParams(
                    p_available: available,
                    p_location_mode: locationMode.rawValue
                ))
                .execute()
                .value
            return .success(update)
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
