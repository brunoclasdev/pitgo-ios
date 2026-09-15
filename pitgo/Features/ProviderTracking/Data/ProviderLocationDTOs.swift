//
//  ProviderLocationDTOs.swift
//  pitgo
//
//  Payload/resultado de `publish_mobile_provider_location`/`stop_mobile_provider_location` — mesma
//  RPC unificada já usada pelo discovery tracker deste app (`MobileDispatchRepository.
//  publishDiscoveryLocation`/`stopDiscoveryLocation`) e pelo Android inteiro (`features/
//  providertracking/repository/ProviderLocationRepository.kt`, que nunca chamou outra coisa). O
//  servidor decide sozinho, a partir do `auth.uid()`, se a posição é para a busca pública
//  (`target: DISCOVERY`) ou para o atendimento já aceito (`target: APPOINTMENT`) — por isso não há
//  mais `p_appointment_id` nos parâmetros.
//
//  Alinhado em 2026-09-14: esse arquivo apontava para `publish_provider_location`/
//  `stop_provider_location` (RPC dedicada, documentada no contrato original de `009`), mas essa RPC
//  não foi tocada desde então e divergiu do que o cliente decodificava — `PUBLISHED` não devolve
//  `published_at` (o `guard let` correspondente sempre caía em `.unknown`) e o outcome de fix
//  desatualizado é `IGNORED`, não `IGNORED_OLDER` (decode falhava e era classificado como erro de
//  serviço). Ver `private.advance_pittec_dispatch`/`publish_mobile_provider_location` em
//  `supabase/migrations/20260902000000_pittec_on_demand.sql` para a definição atual das duas RPCs.
//

import Foundation

struct PublishProviderLocationParams: Encodable {
    let p_latitude: Decimal
    let p_longitude: Decimal
    let p_accuracy_m: Decimal
    let p_captured_at: Date
    let p_tracker_instance_id: UUID
    let p_tracker_sequence: Int64
}

struct PublishProviderLocationResult: Decodable {
    enum Outcome: String, Decodable {
        case published = "PUBLISHED"
        case ignored = "IGNORED"
        case publisherConflict = "PUBLISHER_CONFLICT"
    }

    enum Target: String, Decodable {
        case discovery = "DISCOVERY"
        case appointment = "APPOINTMENT"
    }

    let outcome: Outcome
    let version: Int64?
    let publishedAt: Date?
    let target: Target?

    enum CodingKeys: String, CodingKey {
        case outcome, version, target
        case publishedAt = "published_at"
    }
}

struct StopProviderLocationParams: Encodable {
    let p_tracker_instance_id: UUID
}

struct GetAppointmentProviderLocationParams: Encodable {
    let p_appointment_id: UUID
}

struct AppointmentProviderLocationSnapshot: Decodable {
    let latitude: Decimal?
    let longitude: Decimal?
    let accuracyM: Decimal?
    let capturedAt: Date?
    let publishedAt: Date?
    let version: Int64?
    let fresh: Bool?

    enum CodingKeys: String, CodingKey {
        case latitude, longitude, version, fresh
        case accuracyM = "accuracy_m"
        case capturedAt = "captured_at"
        case publishedAt = "published_at"
    }
}
