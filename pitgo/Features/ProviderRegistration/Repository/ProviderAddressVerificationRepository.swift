//
//  ProviderAddressVerificationRepository.swift
//  pitgo
//
//  Orquestra fix one-shot (`DeviceLocationRepository`) + Edge Function `geocode-provider-address`
//  (já existente e compartilhada, ver contracts/geocoding-edge-function.md). A comparação de
//  distância/500m é autoridade do servidor — o client só encaminha um fix de qualidade e traduz o
//  outcome fechado. O fix do dispositivo nunca é persistido; some da memória após a chamada.
//

import Foundation
import Supabase

final class ProviderAddressVerificationRepository {
    private let client: SupabaseClient
    private let locationRepository: DeviceLocationRepository

    init(client: SupabaseClient, locationRepository: DeviceLocationRepository) {
        self.client = client
        self.locationRepository = locationRepository
    }

    enum VerifyResult {
        case matched(verificationID: UUID, distanceMeters: Double, expiresAt: Date)
        case diverged(verificationID: UUID, distanceMeters: Double, expiresAt: Date)
        case failure(GeocodingFailureReason)
    }

    /// Solicita `.authorizedWhenInUse` se necessário, obtém um fix one-shot de alta precisão e
    /// chama a Edge Function. Nunca solicita `.authorizedAlways` aqui (ver research.md §8).
    func verify(address: NormalizedAddress) async -> VerifyResult {
        switch locationRepository.authorizationStatus {
        case .denied, .restricted:
            return .failure(.permissionDenied)
        case .notDetermined:
            locationRepository.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            break
        }

        let fix: DeviceLocationFix
        switch await locationRepository.requestOneShotFix(timeout: 15) {
        case let .success(value):
            fix = value
        case .permissionDenied:
            return .failure(.permissionDenied)
        case .timeout:
            return .failure(.timeout)
        case .serviceDisabled:
            return .failure(.serviceDisabled)
        case .failure:
            return .failure(.unknown)
        }

        // Pré-checagem local (research.md §6) — a Edge Function também valida e é a autoridade
        // final (`FIX_TOO_OLD`/`FIX_TOO_IMPRECISE`).
        guard fix.horizontalAccuracy <= 100, abs(Date().timeIntervalSince(fix.timestamp)) <= 30 else {
            return .failure(.fixTooImprecise)
        }

        let payload = GeocodeVerificationRequest(
            address: GeocodeAddressPayload(
                street: address.street,
                number: address.number,
                neighborhood: address.neighborhood,
                zip_code: address.zipCode,
                city: address.city,
                state: address.state,
                country: address.country,
                complement: address.complement
            ),
            device_fix: GeocodeDeviceFixPayload(
                latitude: fix.latitude,
                longitude: fix.longitude,
                accuracy_m: fix.horizontalAccuracy,
                captured_at: fix.timestamp
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let response: GeocodeVerificationResponse = try await client.functions.invoke(
                "geocode-provider-address",
                options: FunctionInvokeOptions(body: payload, encoder: encoder),
                decoder: decoder
            )
            return map(response)
        } catch {
            return .failure(classify(error))
        }
    }

    private func map(_ response: GeocodeVerificationResponse) -> VerifyResult {
        switch response.outcome {
        case .verified:
            guard let verificationID = response.verificationID, let expiresAt = response.expiresAt else {
                return .failure(.unknown)
            }
            let distance = response.distanceM ?? 0
            if response.requiresConfirmation == true {
                return .diverged(verificationID: verificationID, distanceMeters: distance, expiresAt: expiresAt)
            }
            return .matched(verificationID: verificationID, distanceMeters: distance, expiresAt: expiresAt)
        case .noMatch: return .failure(.noMatch)
        case .ambiguousOrPartial: return .failure(.ambiguousOrPartial)
        case .wrongRegion: return .failure(.wrongRegion)
        case .fixTooOld: return .failure(.fixTooOld)
        case .fixTooImprecise: return .failure(.fixTooImprecise)
        case .invalidAddress: return .failure(.invalidAddress)
        case .rateLimited: return .failure(.rateLimited)
        case .upstreamUnavailable: return .failure(.upstreamUnavailable)
        case .sessionBlocked: return .failure(.sessionBlocked)
        }
    }

    /// Nunca propaga o `Error` bruto, payload do Google ou chave — apenas a classe do erro.
    private func classify(_ error: Error) -> GeocodingFailureReason {
        if error is FunctionsError { return .upstreamUnavailable }
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
