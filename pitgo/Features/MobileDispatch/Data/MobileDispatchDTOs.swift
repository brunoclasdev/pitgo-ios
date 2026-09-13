//
//  MobileDispatchDTOs.swift
//  pitgo
//
//  Payload/resposta das RPCs de despacho móvel já existentes (contracts/mobile-dispatch-rpcs.md).
//  As ~10 funções retornam `jsonb` em um de três formatos, confirmados nesta sessão via
//  `pg_get_functiondef` no projeto compartilhado: (1) o snapshot "nu", sem envelope, quando a
//  mutation avança normalmente; (2) `{"outcome": "...", "snapshot": {...}}` quando há um aviso além
//  do snapshot (revisão desatualizada, candidato invalidado); (3) `{"outcome": "..."}` sem snapshot
//  quando não resta fluxo (nenhuma busca ativa, oferta expirada, recusa). `DispatchFlowResult`
//  decodifica os três formatos de modo uniforme.
//

import Foundation

/// `.snapshot` é sintético — marca o formato (1) acima, quando o JSON é o snapshot diretamente
/// (identificado pela presença de `search_id` na raiz), sem chave `outcome`.
enum DispatchOutcome: String, Decodable {
    case none = "NONE"
    case active = "ACTIVE"
    case staleRevision = "STALE_REVISION"
    case candidateInvalidated = "CANDIDATE_INVALIDATED"
    case offerExpired = "OFFER_EXPIRED"
    case revisionConflict = "REVISION_CONFLICT"
    case declined = "DECLINED"
    case snapshot = "SNAPSHOT"
}

struct DispatchFlowResult: Decodable {
    let outcome: DispatchOutcome
    let snapshot: MobileDispatchSnapshot?

    private enum RootKeys: String, CodingKey {
        case outcome, snapshot, searchID = "search_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RootKeys.self)
        if container.contains(.searchID) {
            outcome = .snapshot
            snapshot = try MobileDispatchSnapshot(from: decoder)
        } else {
            outcome = try container.decode(DispatchOutcome.self, forKey: .outcome)
            snapshot = try container.decodeIfPresent(MobileDispatchSnapshot.self, forKey: .snapshot)
        }
    }
}

// MARK: - Publicação de discovery (`publish_mobile_provider_location`/`stop_mobile_provider_location`)

struct PublishMobileLocationParams: Encodable {
    let p_latitude: Double
    let p_longitude: Double
    let p_accuracy_m: Double
    let p_captured_at: Date
    let p_tracker_instance_id: UUID
    let p_tracker_sequence: Int64
}

struct PublishMobileLocationResponse: Decodable {
    enum Outcome: String, Decodable {
        case published = "PUBLISHED"
        case ignored = "IGNORED"
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

struct StopMobileLocationParams: Encodable {
    let p_tracker_instance_id: UUID
}

struct StopMobileLocationResponse: Decodable {
    enum Outcome: String, Decodable {
        case stopped = "STOPPED"
        case ignored = "IGNORED"
    }

    let outcome: Outcome
}

// MARK: - Busca do cliente

struct StartMobileDispatchParams: Encodable {
    let p_search_id: UUID
    let p_service_id: UUID
    let p_latitude: Double
    let p_longitude: Double
    let p_accuracy_m: Double
}

struct SearchRevisionParams: Encodable {
    let p_search_id: UUID
    let p_expected_revision: Int64
}

// MARK: - Decisão e ciclo do provider

struct RespondToDispatchParams: Encodable {
    let p_appointment_id: UUID
    let p_accept: Bool
    let p_expected_revision: Int64
}

struct AppointmentRevisionParams: Encodable {
    let p_appointment_id: UUID
    let p_expected_revision: Int64
}

struct CancelMobileAppointmentParams: Encodable {
    let p_appointment_id: UUID
    let p_reason: String
    let p_expected_revision: Int64
}
