//
//  SignUpRepository.swift
//  pitgo
//
//  Implementa a sequência normal de cadastro e a recuperação idempotente de perfil descritas em
//  contracts/account-registration.md. Nunca lança `Error` para o ViewModel — todo resultado é um
//  `RegistrationResult` sanitizado (ver research.md §7). Nenhuma migration/schema é tocado aqui; o
//  backend já existe e é compartilhado com o Android (ver research.md §0).
//
//  Desde `006-auth-vehicle-registration`: a recuperação NÃO faz mais upsert de perfil ausente —
//  apenas reconfirma o perfil já criado pelo trigger de banco (ver plan.md "Login/signup/onboarding"
//  daquela feature). O cadastro só é considerado `.success` depois que
//  `VehicleOnboardingStore.markPending` completar.
//

import Foundation
import Supabase

final class SignUpRepository {
    private let client: SupabaseClient
    private let onboardingStore: VehicleOnboardingStore

    init(client: SupabaseClient, onboardingStore: VehicleOnboardingStore) {
        self.client = client
        self.onboardingStore = onboardingStore
    }

    /// Sequência normal (contracts/account-registration.md "Normal registration sequence").
    func register(_ registration: AccountRegistration) async -> RegistrationResult {
        // 1. Ler a sessão atual antes de assumir ausência.
        if let session = try? await client.auth.session,
           session.user.email?.lowercased() == registration.email {
            // 2. Sessão já pertence ao mesmo e-mail normalizado: pular o signup duplicado.
            return await ensureProfile(for: session.user.id, email: registration.email, registration: registration)
        }

        if Task.isCancelled { return .unknown }

        // 3. Caso contrário, chamar signUp com a metadata normalizada.
        var metadata: [String: AnyJSON] = [
            "name": .string(registration.name),
            "phone": .string(registration.phone),
        ]
        if let cpf = registration.cpf {
            metadata["cpf"] = .string(cpf)
        }
        if let cnpj = registration.cnpj {
            metadata["cnpj"] = .string(cnpj)
        }

        do {
            _ = try await client.auth.signUp(email: registration.email, password: registration.password, data: metadata)
        } catch {
            if Task.isCancelled { return .unknown }
            if let mapped = mapAuthError(error) {
                return mapped
            }
            // Conflito de signup sem sessão local: tentar um único signIn com as mesmas credenciais
            // antes de tratar como recuperação (resposta anterior ambígua).
            if let session = try? await client.auth.signIn(email: registration.email, password: registration.password) {
                return await ensureProfile(for: session.user.id, email: registration.email, registration: registration)
            }
            return classify(error)
        }

        if Task.isCancelled { return .unknown }

        // 4-5. Não usar o retorno do signUp como sinal de sessão — reler a sessão atual.
        guard let session = try? await client.auth.session, session.user.email != nil else {
            return .environmentMisconfigured
        }

        return await ensureProfile(for: session.user.id, email: registration.email, registration: registration)
    }

    /// `retryProfile` não exige senha quando já existe sessão ativa.
    func retryProfile(_ registration: AccountRegistration) async -> RegistrationResult {
        guard let session = try? await client.auth.session else {
            return .environmentMisconfigured
        }
        return await ensureProfile(for: session.user.id, email: registration.email, registration: registration)
    }

    // MARK: - Profile recovery sequence

    private func ensureProfile(for userID: UUID, email: String, registration: AccountRegistration) async -> RegistrationResult {
        if Task.isCancelled { return .unknown }

        // Selecionar profiles pelo id da sessão; se presente e consistente, sucesso. O trigger de
        // banco já criou o perfil de forma transacional junto com o signup — não há upsert aqui.
        guard let existing = await selectProfile(id: userID), isConsistent(existing, registration: registration, email: email) else {
            return .profileRecoveryRequired
        }

        // O cadastro só é considerado concluído depois que a pendência de onboarding for
        // persistida (ver data-model.md §6 de `006`) — antes de retornar `.success`.
        onboardingStore.markPending(userID)
        return .success(userID: userID)
    }

    private func selectProfile(id: UUID) async -> ProfileDTO? {
        do {
            let rows: [ProfileDTO] = try await client
                .from("profiles")
                .select()
                .eq("id", value: id.uuidString)
                .execute()
                .value
            return rows.first
        } catch {
            return nil
        }
    }

    private func isConsistent(_ profile: ProfileDTO, registration: AccountRegistration, email: String) -> Bool {
        guard profile.email.lowercased() == email.lowercased() else { return false }
        guard profile.isActive else { return false }
        switch registration.personType {
        case .individual:
            return profile.cpf != nil && profile.cnpj == nil
        case .company:
            return profile.cnpj != nil && profile.cpf == nil
        }
    }

    // MARK: - Error sanitization (ver research.md §7 "Security note")

    /// Mapeia somente `AuthError.errorCode` estável; nunca a mensagem/payload bruto.
    private func mapAuthError(_ error: Error) -> RegistrationResult? {
        guard let authError = error as? AuthError else { return nil }
        switch authError.errorCode {
        case .emailExists, .userAlreadyExists, .identityAlreadyExists:
            return .emailUnavailable
        case .weakPassword, .validationFailed, .badJSON:
            return .invalidServerInput
        case .overRequestRateLimit, .overEmailSendRateLimit, .overSMSSendRateLimit:
            return .rateLimited
        case .requestTimeout, .unexpectedFailure:
            return .serviceUnavailable
        case .signupDisabled, .emailProviderDisabled:
            return .environmentMisconfigured
        default:
            return nil
        }
    }

    /// Classificação final de fallback quando o tipo do erro não é `AuthError`/`PostgrestError`
    /// (ex.: falha de transporte de rede) — nunca propaga o `Error` bruto.
    private func classify(_ error: Error) -> RegistrationResult {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return .offline
            case .timedOut:
                return .serviceUnavailable
            default:
                return .serviceUnavailable
            }
        }
        return .unknown
    }
}
