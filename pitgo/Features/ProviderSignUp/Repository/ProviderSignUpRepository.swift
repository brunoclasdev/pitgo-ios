//
//  ProviderSignUpRepository.swift
//  pitgo
//
//  Cria somente uma conta Auth `PROVIDER` (`raw_user_meta_data.account_type = "PROVIDER"`,
//  consumido pelo hook/trigger já existentes — ver contracts/account-provider-database.md "Signup
//  gate" de `009`). Diferente de `SignUpRepository` (005), não há profile a confirmar: o trigger
//  não insere nada além de `account_roles` para PROVIDER, então sucesso é apenas "sessão existe com
//  o e-mail informado".
//

import Foundation
import Supabase

final class ProviderSignUpRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func register(email: String, password: String) async -> ProviderSignUpResult {
        let metadata: [String: AnyJSON] = ["account_type": .string("PROVIDER")]

        do {
            _ = try await client.auth.signUp(email: email, password: password, data: metadata)
        } catch {
            if Task.isCancelled { return .unknown }
            if let mapped = mapAuthError(error) {
                return mapped
            }
            // Conflito de signup sem sessão local: tentar um único signIn com as mesmas
            // credenciais antes de tratar como falha (resposta anterior ambígua).
            if let session = try? await client.auth.signIn(email: email, password: password) {
                return .success(userID: session.user.id)
            }
            return classify(error)
        }

        if Task.isCancelled { return .unknown }

        guard let session = try? await client.auth.session, session.user.email != nil else {
            return .environmentMisconfigured
        }
        return .success(userID: session.user.id)
    }

    /// Mapeia somente `AuthError.errorCode` estável; nunca a mensagem/payload bruto.
    private func mapAuthError(_ error: Error) -> ProviderSignUpResult? {
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

    private func classify(_ error: Error) -> ProviderSignUpResult {
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
