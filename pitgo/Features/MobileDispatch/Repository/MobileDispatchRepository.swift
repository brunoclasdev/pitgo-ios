//
//  MobileDispatchRepository.swift
//  pitgo
//
//  Única fronteira com as ~10 RPCs de despacho móvel já implementadas e compartilhadas com o
//  Android (contracts/mobile-dispatch-rpcs.md) e com os dois tópicos privados de Broadcast
//  (contracts/mobile-dispatch-realtime.md). Nenhum `Error` bruto, SQLSTATE, mensagem de servidor ou
//  coordenada de terceiro chega ao ViewModel — somente `MobileDispatchOperationResult`.
//
//  NOTA sobre classificação de exceção: ao contrário de `create_vehicle`/`set_primary_vehicle`
//  (`012`, que criaram SQLSTATEs dedicados por campo), esta família de RPCs reaproveita códigos
//  genéricos (`22023`, `P0001`, `P0002`, `42501`) para várias condições distintas e usa a própria
//  `message` da exceção como discriminador (`PAYMENT_REQUIRED`, `PROVIDER_REQUIRED`, etc. — ver
//  `pg_get_functiondef` inspecionado nesta sessão). Ler `.message` aqui para bater contra um
//  allowlist fechado de literais é o próprio mecanismo do contrato, não uma violação dele — nenhuma
//  string bruta do servidor é repassada adiante, só o `enum` resultante.
//

import Foundation
import Supabase

enum MobileDispatchOperationResult {
    case snapshot(MobileDispatchSnapshot)
    /// Nenhuma busca/solicitação ativa (`NONE`), oferta expirada sem resposta (`OFFER_EXPIRED`) ou
    /// recusa do provider confirmada (`DECLINED`) — nenhum snapshot a aplicar.
    case noActiveFlow
    case failure(MobileDispatchFailureReason)
}

enum MobileDispatchFailureReason {
    case offline
    case timeout
    case sessionExpired
    /// `start_mobile_dispatch` exige um pagamento `APPROVED` prévio para o mesmo `search_id`
    /// (`018-mercadopago-payments`, dependência descoberta nesta sessão ao inspecionar a função
    /// real — não documentada em `013`). Sem uma cobrança aprovada, a busca nunca inicia.
    case paymentRequired
    case notFound
    case serviceUnavailable
    case contract
    case unknown
}

enum DiscoveryPublishOutcome {
    case published(version: Int64, publishedAt: Date)
    case ignored
    case publisherConflict
    case failure(MobileDispatchFailureReason)
}

final class MobileDispatchRepository {
    private let client: SupabaseClient

    private var searchChannel: RealtimeChannelV2?
    private var searchSubscription: RealtimeSubscription?
    private var providerChannel: RealtimeChannelV2?
    private var providerSubscription: RealtimeSubscription?

    init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Busca do cliente

    func startSearch(searchID: UUID, serviceID: UUID, latitude: Double, longitude: Double, accuracyMeters: Double) async -> MobileDispatchOperationResult {
        await call("start_mobile_dispatch", params: StartMobileDispatchParams(
            p_search_id: searchID,
            p_service_id: serviceID,
            p_latitude: latitude,
            p_longitude: longitude,
            p_accuracy_m: accuracyMeters
        ))
    }

    /// Mesmo endpoint serve cliente (busca ativa) e provider (solicitação pendente/atendimento
    /// reservado) — o servidor decide pelo papel da sessão (`get_my_pending_mobile_dispatch` é um
    /// alias exato desta função, confirmado via `pg_get_functiondef`).
    func getActiveDispatch() async -> MobileDispatchOperationResult {
        await callNoParams("get_my_active_mobile_dispatch")
    }

    func nextCandidate(searchID: UUID, expectedRevision: Int64) async -> MobileDispatchOperationResult {
        await call("next_mobile_dispatch_candidate", params: SearchRevisionParams(p_search_id: searchID, p_expected_revision: expectedRevision))
    }

    func requestCandidate(searchID: UUID, expectedRevision: Int64) async -> MobileDispatchOperationResult {
        await call("request_mobile_dispatch_candidate", params: SearchRevisionParams(p_search_id: searchID, p_expected_revision: expectedRevision))
    }

    // MARK: - Decisão e ciclo do provider

    func respond(appointmentID: UUID, accept: Bool, expectedRevision: Int64) async -> MobileDispatchOperationResult {
        await call("respond_to_mobile_dispatch", params: RespondToDispatchParams(
            p_appointment_id: appointmentID,
            p_accept: accept,
            p_expected_revision: expectedRevision
        ))
    }

    func startAppointment(appointmentID: UUID, expectedRevision: Int64) async -> MobileDispatchOperationResult {
        await call("start_mobile_appointment", params: AppointmentRevisionParams(p_appointment_id: appointmentID, p_expected_revision: expectedRevision))
    }

    func completeAppointment(appointmentID: UUID, expectedRevision: Int64) async -> MobileDispatchOperationResult {
        await call("complete_mobile_appointment", params: AppointmentRevisionParams(p_appointment_id: appointmentID, p_expected_revision: expectedRevision))
    }

    /// `reason` já deve chegar aparado e não vazio — o servidor também recusa (`22023`) um motivo
    /// em branco, mas a UI valida antes para dar feedback imediato no campo.
    func cancelAppointment(appointmentID: UUID, reason: String, expectedRevision: Int64) async -> MobileDispatchOperationResult {
        await call("cancel_mobile_appointment", params: CancelMobileAppointmentParams(
            p_appointment_id: appointmentID,
            p_reason: reason,
            p_expected_revision: expectedRevision
        ))
    }

    // MARK: - Publicação de discovery (provider móvel disponível, sem atendimento ainda)

    func publishDiscoveryLocation(fix: DeviceLocationFix, trackerInstanceID: UUID, sequence: Int64) async -> DiscoveryPublishOutcome {
        let params = PublishMobileLocationParams(
            p_latitude: fix.latitude,
            p_longitude: fix.longitude,
            p_accuracy_m: fix.horizontalAccuracy,
            // `Date()` no envio, não `fix.timestamp` — mesmo achado de `PitTecRepository.swift`: o
            // servidor rejeita/ignora silenciosamente (`IGNORED`) um `captured_at` com mais de 30s
            // (contracts/mobile-dispatch-rpcs.md), e o timestamp original do GPS já consome parte
            // desse orçamento antes mesmo de a requisição sair do dispositivo. Sem isso, o provider
            // parece "publicando" no Dashboard (`.ignored` só faz `break` em `ProviderDiscoveryTracker`)
            // enquanto sua posição nunca é de fato aceita, e ele some do `list_nearby_pittecs` do
            // cliente sem nenhum erro visível.
            p_captured_at: Date(),
            p_tracker_instance_id: trackerInstanceID,
            p_tracker_sequence: sequence
        )
        do {
            let result: PublishMobileLocationResponse = try await client
                .rpc("publish_mobile_provider_location", params: params)
                .execute()
                .value
            switch result.outcome {
            case .published:
                guard let version = result.version, let publishedAt = result.publishedAt else { return .failure(.contract) }
                return .published(version: version, publishedAt: publishedAt)
            case .ignored:
                return .ignored
            case .publisherConflict:
                return .publisherConflict
            }
        } catch {
            return .failure(classify(error))
        }
    }

    /// Melhor esforço — o app está encerrando a publicação de qualquer forma.
    func stopDiscoveryLocation(trackerInstanceID: UUID) async {
        _ = try? await client
            .rpc("stop_mobile_provider_location", params: StopMobileLocationParams(p_tracker_instance_id: trackerInstanceID))
            .execute()
    }

    // MARK: - Realtime (cliente)

    /// `mobile-dispatch:<searchID>` — 1) auth 2) subscribe 3) snapshot (mesma ordem de `009`/`010`).
    func subscribeToSearch(searchID: UUID, onInvalidated: @escaping @Sendable () -> Void) async {
        await unsubscribeSearch()
        await client.realtimeV2.setAuth()
        let channel = client.realtimeV2.channel("mobile-dispatch:\(searchID)") { config in
            config.isPrivate = true
        }
        searchChannel = channel
        searchSubscription = channel.onBroadcast(event: "*") { _ in
            onInvalidated()
        }
        try? await channel.subscribeWithError()
    }

    func unsubscribeSearch() async {
        searchSubscription = nil
        if let channel = searchChannel {
            await client.realtimeV2.removeChannel(channel)
        }
        searchChannel = nil
    }

    // MARK: - Realtime (provider)

    /// `provider-dispatch:<providerID>` — mesmo padrão, tópico distinto por participante.
    func subscribeToProvider(providerID: UUID, onInvalidated: @escaping @Sendable () -> Void) async {
        await unsubscribeProvider()
        await client.realtimeV2.setAuth()
        let channel = client.realtimeV2.channel("provider-dispatch:\(providerID)") { config in
            config.isPrivate = true
        }
        providerChannel = channel
        providerSubscription = channel.onBroadcast(event: "*") { _ in
            onInvalidated()
        }
        try? await channel.subscribeWithError()
    }

    func unsubscribeProvider() async {
        providerSubscription = nil
        if let channel = providerChannel {
            await client.realtimeV2.removeChannel(channel)
        }
        providerChannel = nil
    }

    /// Remove os dois canais numa `Task` desacoplada do escopo cancelável (mesma técnica de `010`
    /// contracts/realtime-marker.md) — garante que a remoção sempre complete mesmo que o chamador
    /// já tenha sido cancelado (troca de sessão/logout).
    func disconnectAll() {
        let repository = self
        Task {
            await repository.unsubscribeSearch()
            await repository.unsubscribeProvider()
        }
    }

    // MARK: - Helpers

    private func call<Params: Encodable>(_ function: String, params: Params) async -> MobileDispatchOperationResult {
        do {
            let result: DispatchFlowResult = try await client.rpc(function, params: params).execute().value
            return interpret(result)
        } catch {
            return .failure(classify(error))
        }
    }

    private func callNoParams(_ function: String) async -> MobileDispatchOperationResult {
        do {
            let result: DispatchFlowResult = try await client.rpc(function).execute().value
            return interpret(result)
        } catch {
            return .failure(classify(error))
        }
    }

    private func interpret(_ result: DispatchFlowResult) -> MobileDispatchOperationResult {
        switch result.outcome {
        case .snapshot, .staleRevision, .candidateInvalidated, .revisionConflict, .active:
            guard let snapshot = result.snapshot else { return .failure(.contract) }
            return .snapshot(snapshot)
        case .none, .offerExpired, .declined:
            return .noActiveFlow
        }
    }

    private func classify(_ error: Error) -> MobileDispatchFailureReason {
        if let postgrestError = error as? PostgrestError {
            switch postgrestError.code {
            case "42501":
                return .sessionExpired
            case "P0002":
                return .notFound
            case "P0001" where postgrestError.message.contains("PAYMENT_REQUIRED"):
                return .paymentRequired
            case "22023", "P0001":
                return .contract
            default:
                return .unknown
            }
        }
        if let httpError = error as? HTTPError {
            switch httpError.response.statusCode {
            case 401, 403: return .sessionExpired
            case 404: return .contract
            case 500...599: return .serviceUnavailable
            default: return .unknown
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return .offline
            case .timedOut: return .timeout
            default: return .serviceUnavailable
            }
        }
        return .unknown
    }
}
