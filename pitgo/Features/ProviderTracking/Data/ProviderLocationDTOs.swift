//
//  ProviderLocationDTOs.swift
//  pitgo
//
//  Payload/resultado de `publish_provider_location`/`stop_provider_location`/
//  `get_appointment_provider_location` (já existentes, ver contracts/location-realtime.md "Publish
//  RPC" de `009`). O contrato documenta a assinatura com nomes de parâmetro abreviados
//  (`appointmentId`, `trackerId`) — as chaves `p_`-prefixadas abaixo seguem a mesma convenção já
//  usada por toda RPC deste projeto (`006`/`007`); não há como confirmar contra o projeto Supabase
//  real nesta sessão (sem credenciais), ver tasks.md.
//

import Foundation

struct PublishProviderLocationParams: Encodable {
    let p_appointment_id: UUID
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
        case ignoredOlder = "IGNORED_OLDER"
        case publisherConflict = "PUBLISHER_CONFLICT"
    }

    let outcome: Outcome
    let version: Int64?
    let publishedAt: Date?

    enum CodingKeys: String, CodingKey {
        case outcome, version
        case publishedAt = "published_at"
    }
}

struct StopProviderLocationParams: Encodable {
    let p_appointment_id: UUID
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
