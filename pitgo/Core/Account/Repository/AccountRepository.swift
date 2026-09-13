//
//  AccountRepository.swift
//  pitgo
//
//  Consulta o perfil exato do `id` autenticado e o único veículo ativo principal, em paralelo
//  (ver research.md §3). O client iOS nunca faz INSERT/UPDATE de perfil — apenas lê.
//

import Foundation
import Supabase

enum AccountBootstrapResult {
    case success(AccountSnapshot)
    case blocked(ProfileBlockedReason)
    case offline
}

final class AccountRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func fetchSnapshot(userID: UUID, authEmail: String) async -> AccountBootstrapResult {
        async let profileResult = fetchProfile(userID: userID)
        async let vehicle = fetchPrimaryVehicle(userID: userID)

        switch await profileResult {
        case .offline:
            return .offline
        case .missing:
            return .blocked(.missing)
        case .inactive:
            return .blocked(.inactive)
        case let .success(profile):
            guard isConsistent(profile, userID: userID, authEmail: authEmail) else {
                return .blocked(.inconsistent)
            }
            let snapshot = AccountSnapshot(
                userID: userID,
                authEmail: authEmail,
                profile: profile,
                primaryVehicle: await vehicle
            )
            return .success(snapshot)
        }
    }

    private func isConsistent(_ profile: Profile, userID: UUID, authEmail: String) -> Bool {
        guard profile.id == userID else { return false }
        guard profile.email.lowercased() == authEmail.lowercased() else { return false }
        guard !profile.name.isEmpty, !profile.email.isEmpty, !profile.phone.isEmpty else { return false }
        guard (profile.cpf != nil) != (profile.cnpj != nil) else { return false }
        return profile.isActive
    }

    private enum ProfileFetchResult {
        case success(Profile)
        case missing
        case inactive
        case offline
    }

    private func fetchProfile(userID: UUID) async -> ProfileFetchResult {
        do {
            let rows: [Profile] = try await client
                .from("profiles")
                .select()
                .eq("id", value: userID.uuidString)
                .limit(1)
                .execute()
                .value
            guard let profile = rows.first else { return .missing }
            return profile.isActive ? .success(profile) : .inactive
        } catch {
            return .offline
        }
    }

    private func fetchPrimaryVehicle(userID: UUID) async -> Vehicle? {
        let rows: [Vehicle]? = try? await client
            .from("vehicles")
            .select()
            .eq("user_id", value: userID.uuidString)
            .eq("active", value: true)
            .eq("is_primary", value: true)
            .limit(1)
            .execute()
            .value
        return rows?.first
    }
}
