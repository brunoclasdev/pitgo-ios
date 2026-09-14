//
//  PitTecRepository.swift
//  pitgo
//
//  Única fronteira com as RPCs PitTec já implementadas e compartilhadas com o Android
//  (contracts/pittec-rpcs.md `015`) — nomes/formatos confirmados nesta sessão via
//  `pg_get_functiondef` no projeto Supabase compartilhado. `respond_to_mobile_dispatch`/
//  `cancel_mobile_appointment`/`complete_mobile_appointment` (`013`) já são compartilhadas pelo
//  backend entre `MOBILE_SEQUENTIAL` e `PITTEC_AUTO_SEQUENTIAL` — reaproveitadas via
//  `MobileDispatchRepository` em vez de duplicadas aqui.
//
//  ACHADO CRÍTICO desta sessão: `start_pittec_dispatch` exige o mesmo pagamento `APPROVED` prévio
//  (`request_id = p_request_id`) que `start_mobile_dispatch` (`013`) — dependência de
//  `018-mercadopago-payments` não documentada em `015 spec.md`/`contracts/`.
//
//  ACHADO ADICIONAL: a Edge Function `pittec-route` citada em `015 plan.md` como "já existente" NÃO
//  está deployada neste projeto (`supabase functions list` não a lista) — `upsert_pittec_route_snapshot`
//  nunca é chamada por ninguém, então `get_pittec_route_snapshot` sempre retorna `NOT_FOUND`. O
//  fallback de estimativa direta (FR-023, já exigido pelo próprio spec para quando a rota não está
//  disponível) é, portanto, o único caminho exercitável — implementado como tal, não como exceção.
//
//  ACHADO ADICIONAL (verificado em device físico real): `listNearby`/`startDispatch` enviavam
//  `fix.timestamp` (quando o CoreLocation capturou a posição) como `p_captured_at`. As RPCs
//  rejeitam (`22023 INVALID_LOCATION`) captured_at com mais de 30s de idade — em device físico,
//  só `requestOneShotFix(timeout: 15)` já consome boa parte desse orçamento; somado à latência real
//  de rede até o Postgres, o total observado passou de 37s. Corrigido enviando `Date()` capturado no
//  momento do envio da RPC, não o timestamp original do GPS — `list_nearby_pittecs` é `stable`
//  (somente leitura) e usa `p_captured_at` só para esse gate de frescor, não para ordenação ou
//  persistência, então isso não muda o contrato da RPC, só evita contar a latência do próprio
//  cliente contra o orçamento do servidor.
//

import Foundation
import Supabase

enum PitTecOperationResult {
    case snapshot(PitTecDispatchSnapshot)
    case noActiveFlow
    case failure(PitTecFailureReason)
}

enum PitTecMarkersResult {
    case success([PitTecMarker])
    case failure(PitTecFailureReason)
}

/// Duas posições correntes (`get_pittec_route_context`) — usadas para a linha direta/estimativa
/// quando não há rota calculada (sempre, ver nota acima).
struct PitTecRouteContext: Equatable {
    let providerLatitude: Double
    let providerLongitude: Double
    let clientLatitude: Double
    let clientLongitude: Double
}

enum PitTecRouteContextResult {
    case ready(PitTecRouteContext)
    case notReady
    case failure(PitTecFailureReason)
}

final class PitTecRepository {
    private let client: SupabaseClient

    private var searchChannel: RealtimeChannelV2?
    private var searchSubscription: RealtimeSubscription?
    private var providerChannel: RealtimeChannelV2?
    private var providerSubscription: RealtimeSubscription?

    init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Descoberta e despacho do cliente

    func listNearby(serviceID: UUID, fix: DeviceLocationFix, limit: Int = 200) async -> PitTecMarkersResult {
        struct Params: Encodable {
            let p_service_id: UUID
            let p_latitude: Double
            let p_longitude: Double
            let p_accuracy_meters: Double
            let p_captured_at: Date
            let p_limit: Int
        }
        do {
            let markers: [PitTecMarker] = try await client
                .rpc("list_nearby_pittecs", params: Params(
                    p_service_id: serviceID,
                    p_latitude: fix.latitude,
                    p_longitude: fix.longitude,
                    p_accuracy_meters: fix.horizontalAccuracy,
                    // `Date()` no envio, não `fix.timestamp` — ver ACHADO acima.
                    p_captured_at: Date(),
                    p_limit: limit
                ))
                .execute()
                .value
            return .success(markers)
        } catch {
            return .failure(classify(error))
        }
    }

    func startDispatch(requestID: UUID, serviceID: UUID, fix: DeviceLocationFix) async -> PitTecOperationResult {
        struct Params: Encodable {
            let p_request_id: UUID
            let p_service_id: UUID
            let p_latitude: Double
            let p_longitude: Double
            let p_accuracy_meters: Double
            let p_captured_at: Date
        }
        return await call("start_pittec_dispatch", params: Params(
            p_request_id: requestID,
            p_service_id: serviceID,
            p_latitude: fix.latitude,
            p_longitude: fix.longitude,
            p_accuracy_meters: fix.horizontalAccuracy,
            // `Date()` no envio, não `fix.timestamp` — ver ACHADO acima: em device físico o tempo
            // entre a captura do GPS e a chegada da RPC no servidor passa dos 30s tolerados.
            p_captured_at: Date()
        ))
    }

    /// Mesmo endpoint serve cliente (busca ativa) e provider (oferta/atendimento reservado) — o
    /// servidor decide pelo papel da sessão.
    func getActiveDispatch() async -> PitTecOperationResult {
        await callNoParams("get_my_active_pittec_dispatch")
    }

    /// Cancelamento antes do aceite (`SEARCHING`/`AWAITING_PROVIDER`) — ao contrário do guincho móvel
    /// (`013`), o PitTec TEM uma RPC dedicada para isso, sem exigir motivo (a etapa de motivo
    /// obrigatório só existe depois do aceite, ver `cancelAppointment`).
    func cancelSearch(searchID: UUID, expectedRevision: Int64) async -> PitTecOperationResult {
        struct Params: Encodable {
            let p_request_id: UUID
            let p_search_id: UUID
            let p_expected_revision: Int64
        }
        return await call("cancel_pittec_search", params: Params(p_request_id: searchID, p_search_id: searchID, p_expected_revision: expectedRevision))
    }

    /// Cancelamento depois do aceite (`ACCEPTED`/`IN_PROGRESS`) — reaproveita `cancel_mobile_appointment`
    /// (`013`), que já retorna o snapshot no formato PitTec quando `dispatch_kind = PITTEC_AUTO_SEQUENTIAL`
    /// (confirmado via `pg_get_functiondef` nesta sessão). Motivo obrigatório.
    func cancelAppointment(appointmentID: UUID, reason: String, expectedRevision: Int64) async -> PitTecOperationResult {
        struct Params: Encodable {
            let p_appointment_id: UUID
            let p_reason: String
            let p_expected_revision: Int64
        }
        return await call("cancel_mobile_appointment", params: Params(p_appointment_id: appointmentID, p_reason: reason, p_expected_revision: expectedRevision))
    }

    /// `021`/migration `20260913010000` — confirma ou recusa o orçamento ofertado ao aceitar
    /// (`AWAITING_CLIENT_CONFIRMATION`). Confirmar avança para `AWAITING_PAYMENT` (o pagamento em si
    /// é feito à parte, via `PaymentRepository`); recusar cancela o atendimento com o motivo
    /// `QUOTE_DECLINED` já tratado pelo backend, sem precisar de `cancelAppointment`.
    func respondToQuote(searchID: UUID, appointmentID: UUID, quoteVersion: Int64, accept: Bool, expectedRevision: Int64) async -> PitTecOperationResult {
        struct Params: Encodable {
            let p_request_id: UUID
            let p_appointment_id: UUID
            let p_quote_version: Int64
            let p_accept: Bool
            let p_expected_revision: Int64
        }
        return await call("respond_to_pittec_quote", params: Params(
            p_request_id: searchID,
            p_appointment_id: appointmentID,
            p_quote_version: quoteVersion,
            p_accept: accept,
            p_expected_revision: expectedRevision
        ))
    }

    // MARK: - Ciclo do provider (aceite/recusa/cancelamento reaproveitam `013`)

    /// `respond_to_mobile_dispatch`/`complete_mobile_appointment` (`013`) já são compartilhadas pelo
    /// backend entre `MOBILE_SEQUENTIAL` e `PITTEC_AUTO_SEQUENTIAL` — mesmos nomes/parâmetros de
    /// `MobileDispatchRepository`, decodificados aqui como `PitTecFlowResult` porque a própria RPC
    /// devolve o snapshot no formato PitTec quando o atendimento é PitTec (confirmado via
    /// `pg_get_functiondef` nesta sessão).
    func respondPitTec(appointmentID: UUID, accept: Bool, expectedRevision: Int64) async -> PitTecOperationResult {
        struct Params: Encodable {
            let p_appointment_id: UUID
            let p_accept: Bool
            let p_expected_revision: Int64
        }
        return await call("respond_to_mobile_dispatch", params: Params(p_appointment_id: appointmentID, p_accept: accept, p_expected_revision: expectedRevision))
    }

    func completePitTec(appointmentID: UUID, expectedRevision: Int64) async -> PitTecOperationResult {
        struct Params: Encodable {
            let p_appointment_id: UUID
            let p_expected_revision: Int64
        }
        return await call("complete_mobile_appointment", params: Params(p_appointment_id: appointmentID, p_expected_revision: expectedRevision))
    }

    /// "Cheguei" — específico do PitTec (ACCEPTED → IN_PROGRESS); `start_mobile_appointment` (`013`)
    /// não serve aqui porque o vocabulário/transição é outro.
    func arrive(requestID: UUID, appointmentID: UUID, expectedRevision: Int64) async -> PitTecOperationResult {
        struct Params: Encodable {
            let p_request_id: UUID
            let p_appointment_id: UUID
            let p_expected_revision: Int64
        }
        return await call("arrive_pittec_appointment", params: Params(p_request_id: requestID, p_appointment_id: appointmentID, p_expected_revision: expectedRevision))
    }

    // MARK: - Rota/estimativa do atendimento aceito

    func routeContext(appointmentID: UUID) async -> PitTecRouteContextResult {
        struct Params: Encodable { let p_appointment_id: UUID }
        struct Envelope: Decodable {
            let outcome: String
            let provider: PointPayload?
            let client: PointPayload?
        }
        struct PointPayload: Decodable { let latitude: Double; let longitude: Double }
        do {
            let result: Envelope = try await client
                .rpc("get_pittec_route_context", params: Params(p_appointment_id: appointmentID))
                .execute()
                .value
            guard result.outcome == "READY", let provider = result.provider, let clientPoint = result.client else {
                return .notReady
            }
            return .ready(PitTecRouteContext(
                providerLatitude: provider.latitude,
                providerLongitude: provider.longitude,
                clientLatitude: clientPoint.latitude,
                clientLongitude: clientPoint.longitude
            ))
        } catch {
            return .failure(classify(error))
        }
    }

    // MARK: - Realtime

    func subscribeToSearch(searchID: UUID, onInvalidated: @escaping @Sendable () -> Void) async {
        await unsubscribeSearch()
        await client.realtimeV2.setAuth()
        let channel = client.realtimeV2.channel("mobile-dispatch:\(searchID)") { config in
            config.isPrivate = true
        }
        searchChannel = channel
        searchSubscription = channel.onBroadcast(event: "*") { _ in onInvalidated() }
        try? await channel.subscribeWithError()
    }

    func unsubscribeSearch() async {
        searchSubscription = nil
        if let channel = searchChannel { await client.realtimeV2.removeChannel(channel) }
        searchChannel = nil
    }

    func subscribeToProvider(providerID: UUID, onInvalidated: @escaping @Sendable () -> Void) async {
        await unsubscribeProvider()
        await client.realtimeV2.setAuth()
        let channel = client.realtimeV2.channel("provider-dispatch:\(providerID)") { config in
            config.isPrivate = true
        }
        providerChannel = channel
        providerSubscription = channel.onBroadcast(event: "*") { _ in onInvalidated() }
        try? await channel.subscribeWithError()
    }

    func unsubscribeProvider() async {
        providerSubscription = nil
        if let channel = providerChannel { await client.realtimeV2.removeChannel(channel) }
        providerChannel = nil
    }

    func disconnectAll() {
        let repository = self
        Task {
            await repository.unsubscribeSearch()
            await repository.unsubscribeProvider()
        }
    }

    // MARK: - Helpers

    private func call<Params: Encodable>(_ function: String, params: Params) async -> PitTecOperationResult {
        do {
            let result: PitTecFlowResult = try await client.rpc(function, params: params).execute().value
            return interpret(result)
        } catch {
            return .failure(classify(error))
        }
    }

    private func callNoParams(_ function: String) async -> PitTecOperationResult {
        do {
            let result: PitTecFlowResult = try await client.rpc(function).execute().value
            return interpret(result)
        } catch {
            return .failure(classify(error))
        }
    }

    private func interpret(_ result: PitTecFlowResult) -> PitTecOperationResult {
        switch result.outcome {
        case .started, .activeDispatchExists, .active, .snapshot, .cancelled, .revisionConflict,
             .invalidTransition, .arrived, .confirmed, .confirmationExpired:
            guard let snapshot = result.snapshot else { return .failure(.contract) }
            return .snapshot(snapshot)
        case .declined:
            // `respond_to_pittec_quote` (cliente recusa o orçamento) retorna snapshot; já
            // `respond_to_mobile_dispatch` (provider recusa a chamada) não retorna — mesmo literal,
            // dois contextos, distinguidos pela presença do snapshot.
            if let snapshot = result.snapshot { return .snapshot(snapshot) }
            return .noActiveFlow
        case .none, .offerExpired, .notFound:
            return .noActiveFlow
        }
    }

    private func classify(_ error: Error) -> PitTecFailureReason {
        if let postgrestError = error as? PostgrestError {
            switch postgrestError.code {
            case "42501": return .sessionExpired
            case "P0002": return .notFound
            case "P0001" where postgrestError.message.contains("PAYMENT_REQUIRED"): return .paymentRequired
            case "22023", "23505", "P0001": return .contract
            default: return .unknown
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
