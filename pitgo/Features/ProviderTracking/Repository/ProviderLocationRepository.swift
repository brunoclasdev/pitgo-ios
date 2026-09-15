//
//  ProviderLocationRepository.swift
//  pitgo
//
//  Invoca `publish_mobile_provider_location`/`stop_mobile_provider_location` — RPC unificada que já
//  serve o discovery tracker (`MobileDispatchRepository.publishDiscoveryLocation`) e, a partir de
//  2026-09-14, também este tracking pós-aceite: o servidor identifica pelo `auth.uid()` se o
//  provider tem um atendimento ACCEPTED/IN_PROGRESS e decide sozinho o destino da posição (`target`
//  na resposta), então não precisamos mais informar `p_appointment_id`. Alinhado com o Android
//  (`features/providertracking/repository/ProviderLocationRepository.kt`, que já usava só esta RPC)
//  — a RPC dedicada `publish_provider_location` (contrato original de `009`) segue existindo no
//  backend mas não recebeu mais nenhuma atualização desde então; ver nota em
//  `ProviderLocationDTOs.swift`. Toda regra de elegibilidade/arbitragem é autoridade do servidor — o
//  client só fornece dados válidos e monotônicos.
//

import Foundation
import Supabase

enum PublishLocationResult {
    case published(version: Int64, publishedAt: Date)
    case ignoredOlder
    case publisherConflict
    case ineligible
    case sessionExpired
    case offline
    case service
    case unknown
}

final class ProviderLocationRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    /// `appointmentID` não é mais enviado à RPC (o servidor infere o atendimento ativo sozinho) —
    /// mantido na assinatura só para não mexer nos chamadores (`ProviderLocationTracker`), que ainda
    /// precisam dele para outras finalidades (ex. `GetAppointmentProviderLocationParams`).
    func publish(
        appointmentID: UUID,
        fix: DeviceLocationFix,
        trackerInstanceID: UUID,
        sequence: Int64
    ) async -> PublishLocationResult {
        let params = PublishProviderLocationParams(
            p_latitude: Decimal(fix.latitude),
            p_longitude: Decimal(fix.longitude),
            p_accuracy_m: Decimal(fix.horizontalAccuracy),
            // `Date()` no envio, não `fix.timestamp` — mesmo achado de `PitTecRepository.swift`/
            // `MobileDispatchRepository.publishDiscoveryLocation`: o timestamp original do GPS já
            // consome parte do orçamento de frescor do servidor antes mesmo de a requisição sair do
            // dispositivo, arriscando `ignoredOlder` silencioso no tracking pós-aceite.
            p_captured_at: Date(),
            p_tracker_instance_id: trackerInstanceID,
            p_tracker_sequence: sequence
        )
        do {
            let result: PublishProviderLocationResult = try await client
                .rpc("publish_mobile_provider_location", params: params)
                .execute()
                .value
            switch result.outcome {
            case .published:
                guard let version = result.version, let publishedAt = result.publishedAt else { return .unknown }
                return .published(version: version, publishedAt: publishedAt)
            case .ignored:
                return .ignoredOlder
            case .publisherConflict:
                return .publisherConflict
            }
        } catch {
            return classify(error)
        }
    }

    /// Melhor esforço — falhas de rede/servidor não são reportadas à UI (o app está encerrando o
    /// tracking de qualquer forma). `appointmentID` idem — não vai mais no payload.
    func stop(appointmentID: UUID, trackerInstanceID: UUID) async {
        let params = StopProviderLocationParams(p_tracker_instance_id: trackerInstanceID)
        _ = try? await client.rpc("stop_mobile_provider_location", params: params).execute()
    }

    private func classify(_ error: Error) -> PublishLocationResult {
        if let postgrestError = error as? PostgrestError {
            if postgrestError.code == "42501" { return .sessionExpired }
            if postgrestError.code == "22023" { return .ineligible }
            return .service
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return .offline
            default: return .service
            }
        }
        return .unknown
    }
}
