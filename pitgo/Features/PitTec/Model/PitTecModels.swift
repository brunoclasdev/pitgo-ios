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
    case start = "START"
    case complete = "COMPLETE"
    /// `021`/migration `20260913010000` — ações do cliente sobre o orçamento (`respond_to_pittec_quote`).
    case confirmQuote = "CONFIRM_QUOTE"
    case declineQuote = "DECLINE_QUOTE"
    /// Cliente pode abrir o checkout (`AWAITING_PAYMENT`) ou o mapa de acompanhamento
    /// (`ACCEPTED`/`IN_PROGRESS`) — ambos apenas sinalizam qual tela mostrar, sem RPC própria.
    case openPayment = "OPEN_PAYMENT"
    case openTracking = "OPEN_TRACKING"
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
    /// `021` — valor que o provider vai ofertar ao aceitar; o cliente confirma esse mesmo valor
    /// depois (`quoteVersion` amarra a confirmação a esta oferta específica).
    let quotedPrice: Decimal
    let quoteVersion: Int64

    enum CodingKeys: String, CodingKey {
        case approximateDistanceMeters = "approximate_distance_meters"
        case region
        case quotedPrice = "quoted_price"
        case quoteVersion = "quote_version"
    }
}

/// `021`/migration `20260913010000` — orçamento do atendimento aceito, visível a ambos os lados a
/// partir do momento em que o provider aceita (`appointment.status <> PENDING`). `clientConfirmedAt`
/// só é preenchido depois que o cliente confirma via `respond_to_pittec_quote`.
struct PitTecQuote: Decodable, Equatable {
    let amount: Decimal
    let currency: String
    let version: Int64
    let clientConfirmationDeadline: Date?
    let clientConfirmedAt: Date?

    enum CodingKeys: String, CodingKey {
        case serviceAmount = "service_amount"
        case distanceChargeAmount = "distance_charge_amount"
        case amount, currency, version
        case providerAmount = "provider_amount"
        case customerTotalAmount = "customer_total_amount"
        case expiresAt = "expires_at"
        case clientConfirmationDeadline = "client_confirmation_deadline"
        case clientConfirmedAt = "client_confirmed_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The current backend exposes a provider quote as `provider_amount` and a
        // client quote as `customer_total_amount`. Older snapshots used `amount`.
        amount = try container.decodeIfPresent(Decimal.self, forKey: .customerTotalAmount)
            ?? container.decodeIfPresent(Decimal.self, forKey: .providerAmount)
            ?? container.decodeIfPresent(Decimal.self, forKey: .amount)
            ?? 0
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "BRL"
        version = try container.decodeIfPresent(Int64.self, forKey: .version) ?? 1
        clientConfirmationDeadline = try container.decodeIfPresent(Date.self, forKey: .clientConfirmationDeadline)
            ?? container.decodeIfPresent(Date.self, forKey: .expiresAt)
        clientConfirmedAt = try container.decodeIfPresent(Date.self, forKey: .clientConfirmedAt)
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

struct PitTecPaymentSnapshot: Decodable, Equatable {
    let status: String
}

struct PitTecAppointment: Decodable, Equatable {
    let appointmentID: UUID
    let status: AppointmentStatus
    let responseDeadline: Date?
    let revision: Int64
    let acceptedAt: Date?
    let arrivedAt: Date?
    let cancelledBy: CancelledBy?
    /// `021`/migration `20260913010000` — preço ofertado pelo provider ao aceitar; base de
    /// `respond_to_pittec_quote` e do pagamento em `AWAITING_PAYMENT`.
    let quotedPrice: Decimal
    let isFree: Bool
    let quoteVersion: Int64
    let clientConfirmationDeadline: Date?
    let clientConfirmedAt: Date?
    let clientConfirmedQuoteVersion: Int64?
    /// Espelha `quotedPrice`/`quoteVersion`/`clientConfirmationDeadline`/`clientConfirmedAt` num
    /// único objeto — mantido porque é o formato que a View usa para montar o card de confirmação.
    let quote: PitTecQuote?

    enum CodingKeys: String, CodingKey {
        case appointmentID = "appointment_id"
        case status
        case responseDeadline = "response_deadline"
        case revision
        case acceptedAt = "accepted_at"
        case arrivedAt = "arrived_at"
        case cancelledBy = "cancelled_by"
        case quotedPrice = "quoted_price"
        case isFree = "is_free"
        case quoteVersion = "quote_version"
        case clientConfirmationDeadline = "client_confirmation_deadline"
        case clientConfirmedAt = "client_confirmed_at"
        case clientConfirmedQuoteVersion = "client_confirmed_quote_version"
        case quote
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let quote = try container.decodeIfPresent(PitTecQuote.self, forKey: .quote)
        appointmentID = try container.decode(UUID.self, forKey: .appointmentID)
        status = try container.decode(AppointmentStatus.self, forKey: .status)
        responseDeadline = try container.decodeIfPresent(Date.self, forKey: .responseDeadline)
        revision = try container.decode(Int64.self, forKey: .revision)
        acceptedAt = try container.decodeIfPresent(Date.self, forKey: .acceptedAt)
        arrivedAt = try container.decodeIfPresent(Date.self, forKey: .arrivedAt)
        cancelledBy = try container.decodeIfPresent(CancelledBy.self, forKey: .cancelledBy)
        quotedPrice = try container.decodeIfPresent(Decimal.self, forKey: .quotedPrice) ?? quote?.amount ?? 0
        isFree = try container.decodeIfPresent(Bool.self, forKey: .isFree) ?? false
        quoteVersion = try container.decodeIfPresent(Int64.self, forKey: .quoteVersion) ?? quote?.version ?? 1
        clientConfirmationDeadline = try container.decodeIfPresent(Date.self, forKey: .clientConfirmationDeadline)
            ?? quote?.clientConfirmationDeadline
        clientConfirmedAt = try container.decodeIfPresent(Date.self, forKey: .clientConfirmedAt)
            ?? quote?.clientConfirmedAt
        clientConfirmedQuoteVersion = try container.decodeIfPresent(Int64.self, forKey: .clientConfirmedQuoteVersion)
        self.quote = quote
    }
}

/// Ocorrência mais recente da busca (`service_searches.last_event`) — usada para distinguir "o
/// candidato recusou" de "o prazo expirou" no card inferior (FR-016), já que o snapshot não guarda
/// um histórico de candidatos como o guincho móvel.
enum PitTecLastEvent: String, Decodable, Hashable {
    case providerRejected = "PROVIDER_REJECTED"
    /// Achado nesta sessão: o valor real gravado pelo backend sempre foi `OFFER_EXPIRED`
    /// (`20260902000000_pittec_on_demand.sql`, inalterado desde então) — o raw value anterior,
    /// `PROPOSAL_EXPIRED`, nunca bateu com nada gravado de verdade; um evento de expiração de
    /// oferta derrubava a decodificação inteira do snapshot em vez de só não mostrar o aviso.
    case offerExpired = "OFFER_EXPIRED"
    case providerCancelled = "PROVIDER_CANCELLED"
    /// `021`/migration `20260913010000` — gravado quando a busca esgota o raio atual e amplia para
    /// o próximo (`advance_pittec_dispatch`), sempre com `status` ainda `SEARCHING`.
    case searchContinues = "SEARCH_CONTINUES"
    /// `021` — gravados só em transições terminais (`status` vira `CANCELLED`); `recentNotice`
    /// nunca os exibe (só mostra evento com `status == .searching`), mas precisam existir aqui pois
    /// `lastEvent` é decodificado incondicionalmente como parte do snapshot.
    case clientConfirmationTimeout = "CLIENT_CONFIRMATION_TIMEOUT"
    case quoteDeclined = "QUOTE_DECLINED"
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
    let payment: PitTecPaymentSnapshot?

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
        case offer, provider, appointment, payment
    }

    /// A chegada preenche arrived_at mantendo ACCEPTED; START inicia o atendimento.
    var hasArrived: Bool { appointment?.arrivedAt != nil || appointment?.status == .inProgress }

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
    /// `021`/migration `20260913010000` — retornados por `respond_to_pittec_quote`. `DECLINED`
    /// também é retornado (sem `snapshot`) por `respond_to_mobile_dispatch` quando o PROVIDER recusa
    /// a chamada — o mesmo literal, dois contextos; `interpret(_:)` distingue pela presença do
    /// snapshot, não pelo nome do outcome.
    case confirmed = "CONFIRMED"
    case confirmationExpired = "CONFIRMATION_EXPIRED"
    case notFound = "NOT_FOUND"
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

enum PitTecFailureReason: Equatable {
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
