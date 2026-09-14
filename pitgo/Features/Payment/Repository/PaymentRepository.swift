//
//  PaymentRepository.swift
//  pitgo
//
//  Única fronteira com as Edge Functions/RPCs de pagamento já implantadas e compartilhadas com o
//  Android (`018`) e com o canal privado `payment:<request_id>` (broadcast `CHANGED` emitido pelo
//  trigger `payment_status_broadcast` sempre que uma linha de `payments` muda — confirmado via
//  `pg_get_functiondef` nesta sessão). Nenhum `Error` bruto, corpo de resposta ou Access Token chega
//  ao ViewModel — somente os enums resultantes.
//

import Foundation
import Supabase

enum PaymentCreationOutcome {
    case created(PaymentCreationResult)
    case failure(PaymentFailureReason)
}

enum PaymentStatusResult {
    case found(paymentID: UUID, status: PaymentStatus, method: PaymentMethodKind)
    case notFound
    case failure(PaymentFailureReason)
}

enum PaymentRefundOutcome {
    case resolved(PaymentStatus)
    case failure(PaymentFailureReason)
}

final class PaymentRepository {
    private let client: SupabaseClient

    private var channel: RealtimeChannelV2?
    private var subscription: RealtimeSubscription?

    init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Cobrança

    func createPayment(
        requestID: UUID,
        dispatchKind: PaymentDispatchKind,
        amount: Decimal,
        method: PaymentMethodKind,
        savedCardID: UUID? = nil,
        cardSecurityCodeToken: String? = nil,
        appointmentID: UUID? = nil,
        quoteVersion: Int64? = nil
    ) async -> PaymentCreationOutcome {
        let body = CreatePaymentRequestBody(
            request_id: requestID,
            dispatch_kind: dispatchKind.rawValue,
            amount: amount,
            method: method.rawValue,
            saved_card_id: savedCardID,
            card_security_code_token: cardSecurityCodeToken,
            appointment_id: appointmentID,
            quote_version: quoteVersion
        )
        do {
            // `expires_at` vem do próprio Mercado Pago via `.toISOString()` do lado da Edge Function
            // (com milissegundos, ex.: "2024-01-15T10:30:00.000Z") — o `JSONDecoder` padrão do
            // `FunctionsClient` (`.deferredToDate`) não decodifica strings, e `.iso8601` sozinho
            // rejeita frações de segundo; por isso um decoder dedicado (`Self.decoder`) é passado
            // explicitamente aqui.
            let result: PaymentCreationResult = try await client.functions.invoke(
                "mp-create-payment",
                options: FunctionInvokeOptions(body: body),
                decoder: Self.decoder
            )
            return .created(result)
        } catch {
            return .failure(classify(error))
        }
    }

    /// Fallback quando o canal Realtime não confirma em tempo hábil (`contracts/payment-realtime-ui.md`).
    func status(requestID: UUID) async -> PaymentStatusResult {
        do {
            let envelope: PaymentStatusEnvelope = try await client
                .rpc("get_payment_status", params: GetPaymentStatusParams(p_request_id: requestID))
                .execute()
                .value
            guard envelope.isFound else { return .notFound }
            guard let paymentID = envelope.paymentID, let status = envelope.status, let method = envelope.method else {
                return .failure(.unknown)
            }
            return .found(paymentID: paymentID, status: status, method: method)
        } catch {
            return .failure(classify(error))
        }
    }

    /// Chamado pelo app assim que observa `REFUND_PENDING` (não há trigger/cron server-side que
    /// dispare o estorno sozinho — confirmado nesta sessão inspecionando `pg_cron`/gatilhos reais;
    /// o próprio `mp-refund-payment` já reconfere posse pelo `client_id` da sessão).
    func refund(paymentID: UUID) async -> PaymentRefundOutcome {
        do {
            let response: RefundPaymentResponse = try await client.functions.invoke(
                "mp-refund-payment",
                options: FunctionInvokeOptions(body: RefundPaymentRequestBody(payment_id: paymentID))
            )
            return .resolved(response.status)
        } catch {
            return .failure(classify(error))
        }
    }

    // MARK: - Realtime

    /// `payment:<requestID>` — mesmo padrão de canal privado de `013`/`015`
    /// (`mobile-dispatch:<searchID>`): apenas um sinal para reconsultar `status(requestID:)`, nunca
    /// decodifica o payload do broadcast diretamente.
    func subscribe(requestID: UUID, onChanged: @escaping @Sendable () -> Void) async {
        await unsubscribe()
        await client.realtimeV2.setAuth()
        let newChannel = client.realtimeV2.channel("payment:\(requestID)") { config in
            config.isPrivate = true
        }
        channel = newChannel
        subscription = newChannel.onBroadcast(event: "*") { _ in onChanged() }
        try? await newChannel.subscribeWithError()
    }

    func unsubscribe() async {
        subscription = nil
        if let channel {
            await client.realtimeV2.removeChannel(channel)
        }
        channel = nil
    }

    /// Remove o canal numa `Task` desacoplada (mesma técnica de `013`) — garante que a remoção
    /// sempre complete mesmo que o chamador já tenha sido cancelado.
    func disconnect() {
        let repository = self
        Task { await repository.unsubscribe() }
    }

    // MARK: - Helpers

    /// Aceita ISO8601 com ou sem frações de segundo — o Mercado Pago/`Date.toISOString()` sempre
    /// inclui milissegundos, o que `JSONDecoder.DateDecodingStrategy.iso8601` sozinho rejeita.
    private static let decoder: JSONDecoder = {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let withoutFractionalSeconds = ISO8601DateFormatter()
        withoutFractionalSeconds.formatOptions = [.withInternetDateTime]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { valueDecoder in
            let container = try valueDecoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = withFractionalSeconds.date(from: value) { return date }
            if let date = withoutFractionalSeconds.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Data ISO8601 inválida: \(value)")
        }
        return decoder
    }()

    private func classify(_ error: Error) -> PaymentFailureReason {
        if let functionsError = error as? FunctionsError {
            return classifyEdgeFunctionError(functionsError)
        }
        if let postgrestError = error as? PostgrestError {
            switch postgrestError.code {
            case "42501": return .sessionExpired
            case "P0002": return .notFound
            default: return .unknown
            }
        }
        if let httpError = error as? HTTPError {
            switch httpError.response.statusCode {
            case 401, 403: return .sessionExpired
            case 404: return .notFound
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

    /// As cinco Edge Functions sempre respondem erro como `{ "code": "..." }` no corpo (ver
    /// `supabase/functions/mp-*/index.ts` reais) — `FunctionsError.httpError(code:data:)` carrega
    /// esse corpo bruto, decodificado aqui contra um allowlist fechado.
    private func classifyEdgeFunctionError(_ error: FunctionsError) -> PaymentFailureReason {
        guard case let .httpError(statusCode, data) = error else { return .serviceUnavailable }
        let code = try? JSONDecoder().decode(PaymentEdgeFunctionErrorBody.self, from: data).code
        switch code {
        case "SESSION_REQUIRED": return .sessionExpired
        case "PAYER_DOCUMENT_REQUIRED": return .payerDocumentRequired
        case "CARD_REJECTED": return .cardRejected
        case "CARD_NOT_FOUND": return .cardNotFound
        case "INVALID_INPUT": return .unknown
        default:
            switch statusCode {
            case 401, 403: return .sessionExpired
            case 404: return .notFound
            case 500...599: return .serviceUnavailable
            default: return .unknown
            }
        }
    }
}
