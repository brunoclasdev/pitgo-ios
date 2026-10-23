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
    /// `021`/migration `20260913010000` — exclusivo do PitTec: o prestador aceitou, o cliente ainda
    /// precisa confirmar o orçamento (`quoted_price`) antes de qualquer pagamento ou acompanhamento.
    case awaitingClientConfirmation = "AWAITING_CLIENT_CONFIRMATION"
    /// `021` — PitTec (confirma o orçamento antes de pagar); `028` — também o Guincho, cujo aceite
    /// do prestador acontece ANTES do pagamento (clarificação de 30/09/2026 do Android): aqui não há
    /// orçamento a confirmar, só o pagamento em si, liberado assim que `allowedActions` permite.
    case awaitingPayment = "AWAITING_PAYMENT"
    case accepted = "ACCEPTED"
    case inProgress = "IN_PROGRESS"
    /// `028`: o guincheiro solicitou a conclusão (`complete_mobile_appointment`) — só o cliente pode
    /// confirmar (`confirm_pittec_completion`, nome compartilhado) ou contestar
    /// (`dispute_guincho_completion`).
    case awaitingClientCompletionConfirmation = "AWAITING_CLIENT_COMPLETION_CONFIRMATION"
    /// `028`: o cliente informou que algo não deu certo — aguarda resolução do suporte (fora do app
    /// cliente/prestador; ver `dashboard_resolve_guincho_dispute`, não portado).
    case disputed = "DISPUTED"
    case cancelled = "CANCELLED"
    case completed = "COMPLETED"
    case exhausted = "EXHAUSTED"

    /// Estados que não admitem mais nenhuma ação — a tela mostra confirmação e oferece retorno.
    /// `disputed` fica de fora de propósito: continua tendo sua própria tela ativa (motivo + aguarda
    /// resolução), nunca a tela terminal genérica.
    var isTerminal: Bool {
        switch self {
        case .cancelled, .completed, .exhausted: true
        default: false
        }
    }
}

enum AppointmentStatus: String, Decodable, Hashable {
    case pending = "PENDING"
    /// `021`/migration `20260913010000` — exclusivo do PitTec, ver `ServiceSearchStatus`.
    case awaitingClientConfirmation = "AWAITING_CLIENT_CONFIRMATION"
    /// `021` PitTec / `028` Guincho — ver `ServiceSearchStatus`.
    case awaitingPayment = "AWAITING_PAYMENT"
    case accepted = "ACCEPTED"
    case inProgress = "IN_PROGRESS"
    /// `028` — ver `ServiceSearchStatus`.
    case awaitingClientCompletionConfirmation = "AWAITING_CLIENT_COMPLETION_CONFIRMATION"
    /// `028` — ver `ServiceSearchStatus`.
    case disputed = "DISPUTED"
    case providerRejected = "PROVIDER_REJECTED"
    case expired = "EXPIRED"
    case completed = "COMPLETED"
    case cancelled = "CANCELLED"
}

enum CancelledBy: String, Decodable, Hashable {
    case system = "SYSTEM"
    case client = "CLIENT"
    case provider = "PROVIDER"
}

/// Ações permitidas pelo snapshot corrente — a UI nunca inventa uma ação fora deste conjunto.
enum DispatchAction: String, Decodable, Hashable {
    case openPayment = "OPEN_PAYMENT"
    case openTracking = "OPEN_TRACKING"
    case next = "NEXT"
    case request = "REQUEST"
    case cancel = "CANCEL"
    case accept = "ACCEPT"
    case decline = "DECLINE"
    case complete = "COMPLETE"
    /// `028`: guincheiro registra a chegada à retirada (`arrive_guincho_appointment`), antes de
    /// poder iniciar o transporte.
    case arrive = "ARRIVE"
    /// `028`: guincheiro inicia o transporte após a chegada (`start_guincho_transport`).
    case start = "START"
    /// `028`: cliente confirma a conclusão solicitada pelo guincheiro (`confirm_pittec_completion`,
    /// nome compartilhado).
    case confirmCompletion = "CONFIRM_COMPLETION"
    /// `028`: cliente informa problema em vez de confirmar (`dispute_guincho_completion`).
    case dispute = "DISPUTE"
}

/// `028`: distingue o guincho móvel clássico (busca automática de candidato) do Guincho com seleção
/// explícita no mapa — ambos usam o mesmo `service_searches`/`appointments` e o mesmo snapshot
/// compartilhado. `mobileSequential` é o default para compatibilidade com snapshots antigos que não
/// incluíam este campo (nunca decodificado como ausente = Guincho por engano).
enum MobileDispatchKind: String, Decodable, Hashable {
    case mobileSequential = "MOBILE_SEQUENTIAL"
    case pittecAutoSequential = "PITTEC_AUTO_SEQUENTIAL"
    case guinchoDirect = "GUINCHO_DIRECT"
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

/// `028`: valor pago (preço-base + km) opcionalmente aninhado em `quote` — mesmo formato e mesma
/// técnica de fallback já usadas por `PitTecQuote` (`customer_total_amount` para o cliente,
/// `provider_amount` para o guincheiro; nunca os dois presentes na mesma resposta, pois o backend já
/// filtra por quem está perguntando).
private struct GuinchoAppointmentQuoteDTO: Decodable {
    let amount: Decimal

    enum CodingKeys: String, CodingKey {
        case customerTotalAmount = "customer_total_amount"
        case providerAmount = "provider_amount"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let key: CodingKeys = container.contains(.customerTotalAmount) ? .customerTotalAmount : .providerAmount
        if let number = try? container.decode(Decimal.self, forKey: key) {
            amount = number
        } else {
            let raw = try container.decode(String.self, forKey: key)
            guard raw.range(of: #"^-?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
                  let number = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: container,
                    debugDescription: "Valor de orçamento inválido")
            }
            amount = number
        }
    }
}

struct DispatchAppointment: Decodable, Equatable {
    let appointmentID: UUID
    let status: AppointmentStatus
    let quotedPrice: Decimal
    let isFree: Bool
    let responseDeadline: Date?
    let revision: Int64
    let cancelledBy: CancelledBy?
    /// `028`: preenchido pelo guincheiro ao tocar em "Cheguei" (`arrive_guincho_appointment`).
    let arrivedAt: Date?
    /// `028`: preenchido ao tocar em "Iniciar transporte" (`start_guincho_transport`).
    let serviceStartedAt: Date?
    /// `028`: preenchido quando o guincheiro solicita a conclusão (`complete_mobile_appointment`).
    let completionRequestedAt: Date?
    /// `028`: preenchido quando o cliente confirma (`confirm_pittec_completion`).
    let clientCompletionConfirmedAt: Date?
    /// `028`: amarra o pagamento (`mp-create-payment`) ao orçamento exato deste atendimento — igual
    /// ao PitTec (`021`); ausente em snapshots antigos, default `1`.
    let quoteVersion: Int64

    enum CodingKeys: String, CodingKey {
        case appointmentID = "appointment_id"
        case status
        case quotedPrice = "quoted_price"
        case isFree = "is_free"
        case responseDeadline = "response_deadline"
        case revision
        case cancelledBy = "cancelled_by"
        case quote
        case arrivedAt = "arrived_at"
        case serviceStartedAt = "service_started_at"
        case completionRequestedAt = "completion_requested_at"
        case clientCompletionConfirmedAt = "client_completion_confirmed_at"
        case quoteVersion = "quote_version"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appointmentID = try container.decode(UUID.self, forKey: .appointmentID)
        status = try container.decode(AppointmentStatus.self, forKey: .status)
        let quote = try container.decodeIfPresent(GuinchoAppointmentQuoteDTO.self, forKey: .quote)
        let flatQuotedPrice = try container.decodeIfPresent(Decimal.self, forKey: .quotedPrice)
        quotedPrice = quote?.amount ?? flatQuotedPrice ?? 0
        isFree = try container.decodeIfPresent(Bool.self, forKey: .isFree) ?? false
        responseDeadline = try container.decodeIfPresent(Date.self, forKey: .responseDeadline)
        revision = try container.decode(Int64.self, forKey: .revision)
        cancelledBy = try container.decodeIfPresent(CancelledBy.self, forKey: .cancelledBy)
        arrivedAt = try container.decodeIfPresent(Date.self, forKey: .arrivedAt)
        serviceStartedAt = try container.decodeIfPresent(Date.self, forKey: .serviceStartedAt)
        completionRequestedAt = try container.decodeIfPresent(Date.self, forKey: .completionRequestedAt)
        clientCompletionConfirmedAt = try container.decodeIfPresent(Date.self, forKey: .clientCompletionConfirmedAt)
        quoteVersion = try container.decodeIfPresent(Int64.self, forKey: .quoteVersion) ?? 1
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
    /// `028` — default `.mobileSequential` para snapshots antigos sem este campo.
    let dispatchKind: MobileDispatchKind
    /// `028`: `true` só depois que o pagamento aprova — antes disso o mapa de acompanhamento não
    /// tem posição nenhuma para mostrar (dados do prestador/cliente ainda não liberados).
    let trackingAuthorized: Bool
    /// `028`: nome, veículo, retirada e destino — `nil` até o pagamento aprovar (FR-011/FR-012).
    let guinchoTrip: GuinchoTripSummary?
    /// `028`: preenchido só quando `status == .disputed`.
    let guinchoDispute: GuinchoDispute?
    /// `028`: nome do guincheiro, visível ao cliente a partir do aceite.
    let providerName: String?
    /// Presente nos resultados paginados de `list_my_service_appointments`.
    let createdAt: Date?
    let inspection: GuinchoInspectionSummary?
    /// `034`: estado privado do cliente para oferecer avaliação sem publicar o comentário.
    let ratingState: ServiceRatingState?

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
        case dispatchKind = "dispatch_kind"
        case trackingAuthorized = "tracking_authorized"
        case trip, dispute, provider
        case createdAt = "created_at"
        case inspection
        case ratingState = "rating_state"
    }

    private enum ProviderCodingKeys: String, CodingKey {
        case displayName = "display_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        searchID = try container.decode(UUID.self, forKey: .searchID)
        serviceID = try container.decode(UUID.self, forKey: .serviceID)
        serviceName = try container.decode(String.self, forKey: .serviceName)
        status = try container.decode(ServiceSearchStatus.self, forKey: .status)
        radiusMeters = try container.decode(Int.self, forKey: .radiusMeters)
        revision = try container.decode(Int64.self, forKey: .revision)
        serverNow = try container.decode(Date.self, forKey: .serverNow)
        allowedActions = try container.decodeIfPresent(Set<DispatchAction>.self, forKey: .allowedActions) ?? []
        candidate = try container.decodeIfPresent(CandidateProposal.self, forKey: .candidate)
        appointment = try container.decodeIfPresent(DispatchAppointment.self, forKey: .appointment)
        dispatchKind = try container.decodeIfPresent(MobileDispatchKind.self, forKey: .dispatchKind) ?? .mobileSequential
        trackingAuthorized = try container.decodeIfPresent(Bool.self, forKey: .trackingAuthorized) ?? false
        guinchoTrip = try container.decodeIfPresent(GuinchoTripDTO.self, forKey: .trip)?.summary()
        guinchoDispute = try container.decodeIfPresent(GuinchoDisputeDTO.self, forKey: .dispute)?.domain()
        if let providerContainer = try? container.nestedContainer(keyedBy: ProviderCodingKeys.self, forKey: .provider) {
            providerName = try providerContainer.decodeIfPresent(String.self, forKey: .displayName)
        } else {
            providerName = nil
        }
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        inspection = try container.decodeIfPresent(GuinchoInspectionSummary.self, forKey: .inspection)
        ratingState = try container.decodeIfPresent(ServiceRatingState.self, forKey: .ratingState)
    }
}

// MARK: - Ação pendente (guarda de toque duplicado)

enum DispatchActionKind: Equatable {
    case next, request, cancel(reason: String), accept, decline, start, complete
    /// `021` — confirmação de valor pós-aceite, exclusiva do PitTec (o guincho móvel não tem essa
    /// etapa); vive aqui pelo mesmo motivo de `cancel`/`accept`/`decline` já serem compartilhados.
    case confirm
    /// `028` — guincheiro registra a chegada à retirada, antes de poder iniciar o transporte.
    case arrive
    /// `028` — cliente confirma a conclusão solicitada pelo guincheiro.
    case confirmCompletion
    /// `028` — cliente informa problema em vez de confirmar a conclusão.
    case dispute(reason: String)
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
