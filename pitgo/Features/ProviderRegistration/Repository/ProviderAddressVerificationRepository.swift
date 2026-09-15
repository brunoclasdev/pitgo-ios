//
//  ProviderAddressVerificationRepository.swift
//  pitgo
//
//  Chama a Edge Function `geocode-provider-address` (já existente e compartilhada com o Android) só
//  com o texto do endereço — nenhum fix de GPS do dispositivo é solicitado. Achado em device físico
//  real (iOS não completava nenhum cadastro): o design original de `009` supunha um fix comparado
//  contra o endereço geocodificado, mas a função real hoje só geocodifica o texto via MapTiler e
//  trava uma prova por `verification_token` (string opaca), nunca por coordenada do dispositivo —
//  confirmado lendo o fonte do Edge Function no repo Android (mesmo backend) e via chamada direta ao
//  PostgREST nesta sessão. Ver nota em `ProviderAddressVerificationState`.
//

import Foundation
import Supabase

final class ProviderAddressVerificationRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    enum VerifyResult {
        case matched(token: String, expiresAt: Date)
        case failure(GeocodingFailureReason)
    }

    func verify(address: NormalizedAddress) async -> VerifyResult {
        let payload = GeocodeVerificationRequest(
            address: GeocodeAddressPayload(
                street: address.street,
                number: address.number,
                neighborhood: address.neighborhood,
                zip_code: address.zipCode,
                city: address.city,
                state: address.state,
                country: address.country
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        do {
            let response: GeocodeVerificationResponse = try await client.functions.invoke(
                "geocode-provider-address",
                options: FunctionInvokeOptions(body: payload, encoder: encoder),
                decoder: Self.decoder
            )
            return .matched(token: response.verificationToken, expiresAt: response.expiresAt)
        } catch {
            return .failure(classify(error))
        }
    }

    /// Aceita ISO8601 com ou sem frações de segundo — mesmo achado de `PaymentRepository`:
    /// `expires.toISOString()` no Edge Function (Deno/JS) sempre inclui milissegundos, o que
    /// `JSONDecoder.DateDecodingStrategy.iso8601` sozinho rejeita (erro de decodificação nunca
    /// captado por `classify`, então toda verificação de endereço falhava silenciosamente como
    /// "Não foi possível verificar o endereço" — reproduzido em device físico real nesta sessão).
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

    /// Nunca propaga o `Error` bruto, payload do Google/MapTiler ou chave — apenas a classe do erro.
    private func classify(_ error: Error) -> GeocodingFailureReason {
        if let functionsError = error as? FunctionsError, case let .httpError(code, data) = functionsError {
            let serverCode = (try? JSONDecoder().decode(GeocodeErrorBody.self, from: data))?.code
            switch (code, serverCode) {
            case (400, "INVALID_ADDRESS"): return .invalidAddress
            case (404, "NO_MATCH"): return .noMatch
            case (401, _), (403, _): return .sessionBlocked
            case (503, _): return .upstreamUnavailable
            default: return .unknown
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return .offline
            case .timedOut: return .timeout
            default: return .upstreamUnavailable
            }
        }
        return .unknown
    }
}

private struct GeocodeErrorBody: Decodable {
    let code: String?
}
