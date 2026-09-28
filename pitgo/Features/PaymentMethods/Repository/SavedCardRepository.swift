//
//  SavedCardRepository.swift
//  pitgo
//
//  Única fronteira com `list_saved_cards()` e as Edge Functions `mp-save-card`/`mp-remove-card`
//  (`018`) — formatos confirmados nesta sessão lendo o código-fonte real das duas functions e via
//  `pg_get_functiondef` do RPC.
//

import Foundation
import Supabase

enum SavedCardListResult {
    case success([SavedCard])
    case failure(SavedCardFailureReason)
}

enum SavedCardContextResult {
    case success(SavedCardTokenizationContext)
    case failure(SavedCardFailureReason)
}

enum SavedCardSaveResult {
    case success(SavedCard)
    case failure(SavedCardFailureReason)
}

enum SavedCardRemoveResult {
    case success
    case failure(SavedCardFailureReason)
}

final class SavedCardRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func list() async -> SavedCardListResult {
        do {
            let cards: [SavedCard] = try await client.rpc("list_saved_cards").execute().value
            return .success(cards)
        } catch {
            return .failure(classify(error))
        }
    }

    func tokenizationContext(savedCardID: UUID) async -> SavedCardContextResult {
        struct Params: Encodable { let p_saved_card_id: UUID }
        do {
            let context: SavedCardTokenizationContext = try await client
                .rpc("get_saved_card_tokenization_context", params: Params(p_saved_card_id: savedCardID))
                .execute()
                .value
            return .success(context)
        } catch {
            return .failure(classify(error))
        }
    }

    /// `cardToken` vem do SDK nativo do Mercado Pago (`CoreMethods.createToken`) — o PAN/CVV nunca
    /// passa por este repository nem pelo backend do PitGo (FR-006).
    func save(cardToken: String) async -> SavedCardSaveResult {
        do {
            let response: SaveCardResponse = try await client.functions.invoke(
                "mp-save-card",
                options: FunctionInvokeOptions(body: SaveCardRequestBody(card_token: cardToken))
            )
            return .success(SavedCard(
                id: response.savedCardID,
                brand: response.brand,
                lastFourDigits: response.lastFourDigits,
                createdAt: Date()
            ))
        } catch {
            return .failure(classify(error))
        }
    }

    func remove(id: UUID) async -> SavedCardRemoveResult {
        do {
            try await client.functions.invoke(
                "mp-remove-card",
                options: FunctionInvokeOptions(body: RemoveCardRequestBody(saved_card_id: id))
            )
            return .success
        } catch {
            return .failure(classify(error))
        }
    }

    private func classify(_ error: Error) -> SavedCardFailureReason {
        if case let .httpError(statusCode, data) = error as? FunctionsError {
            let code = try? JSONDecoder().decode(PaymentEdgeFunctionErrorBody.self, from: data).code
            switch code {
            case "SESSION_REQUIRED": return .sessionExpired
            case "CARD_REJECTED": return .cardRejected
            case "CARD_NOT_FOUND": return .notFound
            default:
                switch statusCode {
                case 401, 403: return .sessionExpired
                case 404: return .notFound
                case 500...599: return .serviceUnavailable
                default: return .unknown
                }
            }
        }
        if let postgrestError = error as? PostgrestError {
            switch postgrestError.code {
            case "42501": return .sessionExpired
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
