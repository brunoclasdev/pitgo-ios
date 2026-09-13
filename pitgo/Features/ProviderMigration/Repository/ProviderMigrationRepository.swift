//
//  ProviderMigrationRepository.swift
//  pitgo
//
//  Invoca somente `begin_provider_ownership_migration`/`claim_provider_ownership_migration` (já
//  existentes, ver contracts/account-provider-database.md "Legacy ownership transfer" de `009`).
//  Nenhum ID de conta/provider é enviado — o servidor deriva tudo de `auth.uid()` + token.
//

import Foundation
import Supabase

final class ProviderMigrationRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    enum BeginOutcome {
        case pending(expiresAt: Date, requirements: String?)
        case failure(ProviderMigrationFailureReason)
    }

    private struct BeginParams: Encodable { let p_token: String }

    private struct BeginResult: Decodable {
        let outcome: String
        let expiresAt: Date
        let requirements: String?

        enum CodingKeys: String, CodingKey {
            case outcome
            case expiresAt = "expires_at"
            case requirements
        }
    }

    /// Exige owner CLIENT de um Provider legado — chamado a partir da sessão original.
    func begin(token: String) async -> BeginOutcome {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let result: BeginResult = try await client
                .rpc("begin_provider_ownership_migration", params: BeginParams(p_token: token))
                .execute()
                .value
            return .pending(expiresAt: result.expiresAt, requirements: result.requirements)
        } catch {
            return .failure(classify(error))
        }
    }

    enum ClaimOutcome {
        case migrated(providerID: UUID)
        case alreadyMigrated(providerID: UUID)
        case failure(ProviderMigrationFailureReason)
    }

    private struct ClaimParams: Encodable {
        let p_token: String
        let p_location_mode: String
        let p_geocode_verification_id: UUID?
        let p_divergence_confirmed: Bool
    }

    private struct ClaimResult: Decodable {
        let outcome: String
        let providerID: UUID?

        enum CodingKeys: String, CodingKey {
            case outcome
            case providerID = "provider_id"
        }
    }

    /// Exige uma conta PROVIDER de e-mail diferente, sem outro Provider — chamado a partir da nova
    /// sessão, depois do logout/login intencional (ver contracts/navigation-session.md).
    func claim(
        token: String,
        locationMode: ProviderLocationMode,
        geocodeVerificationID: UUID?,
        divergenceConfirmed: Bool
    ) async -> ClaimOutcome {
        let params = ClaimParams(
            p_token: token,
            p_location_mode: locationMode.rawValue,
            p_geocode_verification_id: geocodeVerificationID,
            p_divergence_confirmed: divergenceConfirmed
        )
        do {
            let result: ClaimResult = try await client
                .rpc("claim_provider_ownership_migration", params: params)
                .execute()
                .value
            guard let providerID = result.providerID else { return .failure(.unknown) }
            return result.outcome == "MIGRATED" ? .migrated(providerID: providerID) : .alreadyMigrated(providerID: providerID)
        } catch {
            return .failure(classify(error))
        }
    }

    /// O contrato só define "falha neutra" para token expirado/reivindicante diferente/origem
    /// alterada — sem vocabulário fechado de outcome, então só classificamos a camada de transporte.
    private func classify(_ error: Error) -> ProviderMigrationFailureReason {
        if let postgrestError = error as? PostgrestError {
            return postgrestError.code == "42501" ? .sessionExpired : .expiredOrInvalid
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return .offline
            default: return .service
            }
        }
        return .unknown
    }
}
