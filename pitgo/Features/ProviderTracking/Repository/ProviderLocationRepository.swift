//
//  ProviderLocationRepository.swift
//  pitgo
//
//  Invoca somente `publish_provider_location`/`stop_provider_location` (já existentes, ver
//  contracts/location-realtime.md "Publish RPC" de `009`). Toda regra de elegibilidade/arbitragem é
//  autoridade do servidor — o client só fornece dados válidos e monotônicos.
//

import Foundation
import Supabase

enum PublishLocationResult {
    case published(version: Int64, publishedAt: Date)
    case ignoredOlder
    case publisherConflict
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

    func publish(
        appointmentID: UUID,
        fix: DeviceLocationFix,
        trackerInstanceID: UUID,
        sequence: Int64
    ) async -> PublishLocationResult {
        let params = PublishProviderLocationParams(
            p_appointment_id: appointmentID,
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
                .rpc("publish_provider_location", params: params)
                .execute()
                .value
            switch result.outcome {
            case .published:
                guard let version = result.version, let publishedAt = result.publishedAt else { return .unknown }
                return .published(version: version, publishedAt: publishedAt)
            case .ignoredOlder:
                return .ignoredOlder
            case .publisherConflict:
                return .publisherConflict
            }
        } catch {
            return classify(error)
        }
    }

    /// Melhor esforço — falhas de rede/servidor não são reportadas à UI (o app está encerrando o
    /// tracking de qualquer forma).
    func stop(appointmentID: UUID, trackerInstanceID: UUID) async {
        let params = StopProviderLocationParams(p_appointment_id: appointmentID, p_tracker_instance_id: trackerInstanceID)
        _ = try? await client.rpc("stop_provider_location", params: params).execute()
    }

    private func classify(_ error: Error) -> PublishLocationResult {
        if let postgrestError = error as? PostgrestError {
            return postgrestError.code == "42501" ? .sessionExpired : .service
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
