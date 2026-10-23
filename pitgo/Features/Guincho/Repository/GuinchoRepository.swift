//
//  GuinchoRepository.swift
//  pitgo
//
//  `028` (porte do app Android — `GuinchoRepository.kt`): fronteira com as RPCs/Edge Function da
//  etapa pré-pagamento do Guincho, já implantadas e compartilhadas com o Android no mesmo projeto
//  Supabase. `reserve(quote:operationID:)` é a única ponte para o snapshot de despacho compartilhado
//  (`013`) — a partir daí, `MobileDispatchRepository`/`ClientMobileDispatchViewModel` assumem o
//  acompanhamento.
//

import CoreLocation
import Foundation
import Supabase

private struct SaveGuinchoTripDraftParams: Encodable {
    let p_vehicle_id: UUID
    let p_pickup_address: String
    let p_pickup_latitude: Double
    let p_pickup_longitude: Double
    let p_destination_address: String
    let p_destination_latitude: Double
    let p_destination_longitude: Double
    let p_draft_id: UUID?
    let p_expected_revision: Int64?
}

private struct DiscoverGuinchoProvidersParams: Encodable {
    let p_draft_id: UUID
    let p_expected_revision: Int64
    let p_limit: Int
}

private struct GuinchoQuoteRequestBody: Encodable {
    let draft_id: UUID
    let input_revision: Int64
    let provider_id: UUID
}

private struct CreateGuinchoRequestParams: Encodable {
    let p_quote_id: UUID
    let p_operation_id: UUID
}

final class GuinchoRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    /// `Contratar` — cria a solicitação (`PENDING`, aguardando o guincheiro escolhido aceitar) ANTES
    /// de qualquer pagamento (clarificação de 30/09/2026 do Android, que este porte segue). O
    /// `operationID` é gerado uma única vez pelo chamador (idempotência — reenviar o mesmo toque
    /// nunca duplica a solicitação).
    func reserve(quote: GuinchoQuote, operationID: UUID) async -> GuinchoOutcome<MobileDispatchSnapshot> {
        await call {
            let result: DispatchFlowResult = try await self.client
                .rpc("create_guincho_request_before_payment", params: CreateGuinchoRequestParams(
                    p_quote_id: quote.id,
                    p_operation_id: operationID
                ))
                .execute()
                .value
            guard let snapshot = result.snapshot else { throw GuinchoContractError() }
            return snapshot
        }
    }

    func saveTrip(_ input: GuinchoTripInput, previous: GuinchoDraft?) async -> GuinchoOutcome<GuinchoDraft> {
        guard input.isValid else { return .failure(.invalidInput) }
        return await call {
            let dto: GuinchoDraftDTO = try await self.client
                .rpc("save_guincho_trip_draft", params: SaveGuinchoTripDraftParams(
                    p_vehicle_id: input.vehicleID,
                    p_pickup_address: input.pickupAddress.trimmingCharacters(in: .whitespaces),
                    p_pickup_latitude: input.pickup.latitude,
                    p_pickup_longitude: input.pickup.longitude,
                    p_destination_address: input.destinationAddress.trimmingCharacters(in: .whitespaces),
                    p_destination_latitude: input.destination.latitude,
                    p_destination_longitude: input.destination.longitude,
                    p_draft_id: previous?.id,
                    p_expected_revision: previous?.revision
                ))
                .execute()
                .value
            return dto.domain()
        }
    }

    func discover(draft: GuinchoDraft) async -> GuinchoOutcome<[GuinchoProvider]> {
        await call {
            let dtos: [GuinchoProviderDTO] = try await self.client
                .rpc("discover_guincho_providers", params: DiscoverGuinchoProvidersParams(
                    p_draft_id: draft.id, p_expected_revision: draft.revision, p_limit: 200
                ))
                .execute()
                .value
            return dtos.map { $0.domain() }
        }
    }

    func quote(draft: GuinchoDraft, providerID: UUID) async -> GuinchoOutcome<GuinchoQuote> {
        await call {
            let dto: GuinchoQuoteDTO = try await self.client.functions.invoke(
                "guincho-quote",
                options: FunctionInvokeOptions(body: GuinchoQuoteRequestBody(
                    draft_id: draft.id, input_revision: draft.revision, provider_id: providerID
                ))
            )
            return dto.domain()
        }
    }

    // MARK: - Helpers

    /// Mesmo padrão de `MobileDispatchRepository`/`PaymentRepository` — sem timeout próprio; confia
    /// no `URLError.timedOut` já classificado abaixo.
    private func call<T: Sendable>(_ block: () async throws -> T) async -> GuinchoOutcome<T> {
        do {
            return try await .success(block())
        } catch is GuinchoContractError {
            return .failure(.contract)
        } catch {
            return .failure(classify(error))
        }
    }

    private func classify(_ error: Error) -> GuinchoFailureReason {
        if let functionsError = error as? FunctionsError, case let .httpError(statusCode, data) = functionsError {
            let code = try? JSONDecoder().decode(GuinchoEdgeFunctionErrorBody.self, from: data).code
            switch code {
            case "ROUTE_UNAVAILABLE": return .routeUnavailable
            case "PROVIDER_UNAVAILABLE": return .providerUnavailable
            case "QUOTE_EXPIRED": return .quoteExpired
            case "QUOTE_CONFLICT", "REVISION_CONFLICT": return .quoteConflict
            case "PRICING_UNAVAILABLE": return .pricingUnavailable
            default:
                return statusCode == 401 ? .sessionExpired : (statusCode >= 500 ? .serviceUnavailable : .invalidInput)
            }
        }
        if let postgrestError = error as? PostgrestError {
            switch postgrestError.code {
            case "42501": return .sessionExpired
            default: return .contract
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

private struct GuinchoEdgeFunctionErrorBody: Decodable {
    let code: String?
}

private struct GuinchoContractError: Error {}
