//
//  PitTecModels.swift
//  pitgo
//
//  Domínio do PitTec sob demanda (`015`). Formato confirmado nesta sessão via `pg_get_functiondef`
//  de `private.pittec_dispatch_snapshot` no projeto Supabase compartilhado — deliberadamente
//  DIFERENTE do snapshot de guincho móvel (`013`): antes do aceite não há `candidate` nenhum (o
//  cliente não sabe quem está sendo consultado), o provider só vê distância aproximada arredondada
//  a 500m + região (nunca o nome/posição exata do cliente), e `provider` só aparece para o cliente
//  a partir de `ACCEPTED`.
//

import Foundation

enum PitTecOfferAction: String, Decodable, Hashable {
    case cancel = "CANCEL"
    case accept = "ACCEPT"
    case decline = "DECLINE"
    case arrive = "ARRIVE"
    case complete = "COMPLETE"
}

/// Marcador aproximado de um PitTec disponível antes do aceite — grade de ~500m, `markerID` opaco e
/// estável por hora (nunca a posição exata do provider, FR-003/FR-031).
struct PitTecMarker: Decodable, Identifiable, Equatable {
    let markerID: String
    let latitude: Double
    let longitude: Double
    let accuracyRadiusMeters: Int

    var id: String { markerID }

    enum CodingKeys: String, CodingKey {
        case markerID = "marker_id"
        case latitude, longitude
        case accuracyRadiusMeters = "accuracy_radius_meters"
    }
}

/// Só visível ao provider quando `appointment.status == .pending` — distância já arredondada pelo
/// servidor (nunca a posição exata do cliente antes do aceite).
struct PitTecOffer: Decodable, Equatable {
    let approximateDistanceMeters: Double
    let region: String

    enum CodingKeys: String, CodingKey {
        case approximateDistanceMeters = "approximate_distance_meters"
        case region
    }
}

/// Só visível ao cliente a partir de `ACCEPTED`/`IN_PROGRESS`/`COMPLETED`/`CANCELLED` — antes disso
/// o cliente não sabe qual provider está sendo consultado.
struct PitTecProviderIdentity: Decodable, Equatable {
    let providerID: UUID
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case displayName = "display_name"
    }
}

struct PitTecAppointment: Decodable, Equatable {
    let appointmentID: UUID
    let status: AppointmentStatus
    let responseDeadline: Date?
    let revision: Int64
    let acceptedAt: Date?
    let arrivedAt: Date?
    let cancelledBy: CancelledBy?

    enum CodingKeys: String, CodingKey {
        case appointmentID = "appointment_id"
        case status
        case responseDeadline = "response_deadline"
        case revision
        case acceptedAt = "accepted_at"
        case arrivedAt = "arrived_at"
        case cancelledBy = "cancelled_by"
    }
}

/// Ocorrência mais recente da busca (`service_searches.last_event`) — usada para distinguir "o
/// candidato recusou" de "o prazo expirou" no card inferior (FR-016), já que o snapshot não guarda
/// um histórico de candidatos como o guincho móvel.
enum PitTecLastEvent: String, Decodable, Hashable {
    case providerRejected = "PROVIDER_REJECTED"
    case proposalExpired = "PROPOSAL_EXPIRED"
    case providerCancelled = "PROVIDER_CANCELLED"
}

struct PitTecDispatchSnapshot: Decodable, Equatable {
    let searchID: UUID
    let serviceID: UUID
    let serviceName: String
    let status: ServiceSearchStatus
    let radiusMeters: Int
    let revision: Int64
    let serverNow: Date
    let allowedActions: Set<PitTecOfferAction>
    let lastEvent: PitTecLastEvent?
    let lastEventAt: Date?
    let offer: PitTecOffer?
    let provider: PitTecProviderIdentity?
    let appointment: PitTecAppointment?

    enum CodingKeys: String, CodingKey {
        case searchID = "search_id"
        case serviceID = "service_id"
        case serviceName = "service_name"
        case status
        case radiusMeters = "radius_meters"
        case revision
        case serverNow = "server_now"
        case allowedActions = "allowed_actions"
        case lastEvent = "last_event"
        case lastEventAt = "last_event_at"
        case offer, provider, appointment
    }

    /// "Chegou" no vocabulário PitTec é `IN_PROGRESS` (design decision #4 do plan.md) — antes disso,
    /// `ACCEPTED` significa "a caminho".
    var hasArrived: Bool { appointment?.status == .inProgress }

    /// Um evento só é "recente" (exibível como aviso pontual) se aconteceu depois da última troca de
    /// revisão-1 — aproximado aqui apenas exibindo o evento enquanto o status ainda for `SEARCHING`,
    /// que é justamente quando `advance_pittec_dispatch` acabou de reagir a ele.
    var recentNotice: PitTecLastEvent? {
        status == .searching ? lastEvent : nil
    }
}

// MARK: - Envelope de resposta das RPCs (mesmo formato tolerante de `013`)

enum PitTecOutcome: String, Decodable {
    case started = "STARTED"
    case activeDispatchExists = "ACTIVE_PITTEC_DISPATCH_EXISTS"
    case none = "NONE"
    case active = "ACTIVE"
    case cancelled = "CANCELLED"
    case revisionConflict = "REVISION_CONFLICT"
    case invalidTransition = "INVALID_TRANSITION"
    case arrived = "ARRIVED"
    case offerExpired = "OFFER_EXPIRED"
    case declined = "DECLINED"
    case snapshot = "SNAPSHOT"
}

struct PitTecFlowResult: Decodable {
    let outcome: PitTecOutcome
    let snapshot: PitTecDispatchSnapshot?

    private enum RootKeys: String, CodingKey {
        case outcome, snapshot, searchID = "search_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: RootKeys.self)
        if container.contains(.searchID) {
            outcome = .snapshot
            snapshot = try PitTecDispatchSnapshot(from: decoder)
        } else {
            outcome = try container.decode(PitTecOutcome.self, forKey: .outcome)
            snapshot = try container.decodeIfPresent(PitTecDispatchSnapshot.self, forKey: .snapshot)
        }
    }
}

// MARK: - Estados de tela

enum PitTecFailureReason {
    case offline
    case timeout
    case sessionExpired
    case paymentRequired
    case notFound
    case serviceUnavailable
    case contract
    case unknown
}

enum PitTecClientUiState: Equatable {
    case restoring
    case locationRequired(reason: LocationRequiredReason)
    /// Antes de qualquer busca — mostra o mapa com marcadores aproximados e o botão "Chamar PitTec".
    case discovering([PitTecMarker])
    case content(PitTecDispatchSnapshot, pendingAction: PendingDispatchAction?)
    case terminal(PitTecDispatchSnapshot)
    case failure(lastConfirmed: PitTecDispatchSnapshot?)
    case sessionExpired
}
