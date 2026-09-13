//
//  MobileDispatchModels.swift
//  pitgo
//
//  Snapshot imutável do fluxo de despacho móvel (`013`). O PostgreSQL é a fonte autoritativa —
//  este client mantém apenas o retrato mais recente e estado de interação transitório. Os nomes/
//  formatos abaixo foram confirmados diretamente contra `private.dispatch_snapshot` e as ~10 RPCs
//  já implementadas no projeto Supabase compartilhado (inspecionadas nesta sessão via `pg_get_
//  functiondef`), não apenas contra o texto prosaico do contrato — que descreve um envelope
//  ligeiramente mais rico (`notice`, motivo de cancelamento) do que o que o backend realmente
//  retorna hoje. Nenhuma dessas informações ausentes é inventada no client.
//

import Foundation

enum ServiceSearchStatus: String, Decodable, Hashable {
    case searching = "SEARCHING"
    case optionFound = "OPTION_FOUND"
    case awaitingProvider = "AWAITING_PROVIDER"
    case accepted = "ACCEPTED"
    case inProgress = "IN_PROGRESS"
    case cancelled = "CANCELLED"
    case completed = "COMPLETED"
    case exhausted = "EXHAUSTED"

    /// Estados que não admitem mais nenhuma ação — a tela mostra confirmação e oferece retorno.
    var isTerminal: Bool {
        switch self {
        case .cancelled, .completed, .exhausted: true
        default: false
        }
    }
}

enum AppointmentStatus: String, Decodable, Hashable {
    case pending = "PENDING"
    case accepted = "ACCEPTED"
    case inProgress = "IN_PROGRESS"
    case providerRejected = "PROVIDER_REJECTED"
    case expired = "EXPIRED"
    case completed = "COMPLETED"
    case cancelled = "CANCELLED"
}

enum CancelledBy: String, Decodable, Hashable {
    case client = "CLIENT"
    case provider = "PROVIDER"
}

/// Ações permitidas pelo snapshot corrente — a UI nunca inventa uma ação fora deste conjunto.
enum DispatchAction: String, Decodable, Hashable {
    case next = "NEXT"
    case request = "REQUEST"
    case cancel = "CANCEL"
    case accept = "ACCEPT"
    case decline = "DECLINE"
    case complete = "COMPLETE"
}

/// Posição corrente do candidato — ausente/`nil` quando a localização não está mais disponível
/// (provider ficou stale entre a apresentação e a leitura). Coordenadas puras (sem `CoreLocation`),
/// mesma convenção de `ServiceMapResult`/`MapViewport`.
struct CandidateProposal: Decodable, Equatable {
    let candidateID: UUID
    let providerID: UUID
    let providerName: String
    let locality: String
    let latitude: Double?
    let longitude: Double?
    let distanceMeters: Double
    let price: Decimal
    let isFree: Bool

    enum CodingKeys: String, CodingKey {
        case candidateID = "candidate_id"
        case providerID = "provider_id"
        case providerName = "provider_name"
        case locality, latitude, longitude
        case distanceMeters = "distance_meters"
        case price
        case isFree = "is_free"
    }

    var hasValidLocation: Bool { latitude != nil && longitude != nil }
}

struct DispatchAppointment: Decodable, Equatable {
    let appointmentID: UUID
    let status: AppointmentStatus
    let quotedPrice: Decimal
    let isFree: Bool
    let responseDeadline: Date?
    let revision: Int64
    let cancelledBy: CancelledBy?

    enum CodingKeys: String, CodingKey {
        case appointmentID = "appointment_id"
        case status
        case quotedPrice = "quoted_price"
        case isFree = "is_free"
        case responseDeadline = "response_deadline"
        case revision
        case cancelledBy = "cancelled_by"
    }
}

/// Retrato completo devolvido por `private.dispatch_snapshot` — o mesmo formato serve cliente e
/// provider; `allowedActions` já reflete o papel de quem chamou.
struct MobileDispatchSnapshot: Decodable, Equatable {
    let searchID: UUID
    let serviceID: UUID
    let serviceName: String
    let status: ServiceSearchStatus
    let radiusMeters: Int
    let revision: Int64
    let serverNow: Date
    let allowedActions: Set<DispatchAction>
    let candidate: CandidateProposal?
    let appointment: DispatchAppointment?

    enum CodingKeys: String, CodingKey {
        case searchID = "search_id"
        case serviceID = "service_id"
        case serviceName = "service_name"
        case status
        case radiusMeters = "radius_meters"
        case revision
        case serverNow = "server_now"
        case allowedActions = "allowed_actions"
        case candidate, appointment
    }
}

// MARK: - Ação pendente (guarda de toque duplicado)

enum DispatchActionKind: Equatable {
    case next, request, cancel(reason: String), accept, decline, start, complete
}

/// Bloqueia toques concorrentes antes mesmo de criar a `Task` — a mesma ação nunca dispara duas
/// mutations simultâneas (FR-022).
struct PendingDispatchAction: Equatable {
    let kind: DispatchActionKind
    let expectedRevision: Int64
}

// MARK: - Estados de tela

enum LocationRequiredReason: Hashable {
    case permissionDenied
    case serviceDisabled
    case timeout
    case unknown
}

enum ClientMobileDispatchFailureReason: Hashable {
    case offline
    case timeout
    case sessionExpired
    case paymentRequired
    case notFound
    case serviceUnavailable
    case contract
    case unknown
}

enum ClientMobileDispatchUiState: Equatable {
    case restoring
    /// Nova busca ainda não paga (`018`) — `start_mobile_dispatch` exige um pagamento `APPROVED`
    /// prévio para o mesmo `search_id` (verificado nesta sessão via `pg_get_functiondef` do backend
    /// real). A View apresenta `PaymentCheckoutView` como `.sheet`; em `.approved`, chama
    /// `beginPaidSearch(searchID:)` com o `requestID` gerado pelo checkout.
    case paymentRequired(serviceID: UUID)
    case locationRequired(reason: LocationRequiredReason)
    case content(MobileDispatchSnapshot, pendingAction: PendingDispatchAction?)
    case terminal(MobileDispatchSnapshot)
    case failure(ClientMobileDispatchFailureReason, lastConfirmed: MobileDispatchSnapshot?)
    case sessionExpired

    static func == (lhs: ClientMobileDispatchUiState, rhs: ClientMobileDispatchUiState) -> Bool {
        switch (lhs, rhs) {
        case let (.paymentRequired(a), .paymentRequired(b)): a == b
        case let (.locationRequired(a), .locationRequired(b)): a == b
        case let (.content(a, pa), .content(b, pb)): a == b && pa == pb
        case let (.terminal(a), .terminal(b)): a == b
        case let (.failure(a, la), .failure(b, lb)): a == b && la == lb
        case (.restoring, .restoring), (.sessionExpired, .sessionExpired): true
        default: false
        }
    }
}

enum ProviderDispatchUiState: Equatable {
    case noIncoming
    case incoming(MobileDispatchSnapshot, pendingAction: PendingDispatchAction?)
    case reserved(MobileDispatchSnapshot, pendingAction: PendingDispatchAction?)
    case sessionExpired
    case failure(lastConfirmed: MobileDispatchSnapshot?)
}
