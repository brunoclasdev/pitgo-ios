//
//  ProviderSignUpModels.swift
//  pitgo
//
//  Cadastro de credenciais da conta empresarial (ver contracts/navigation-session.md "Signup
//  stacks" de `009`). Só cria uma conta Auth `PROVIDER` — nenhum profile de cliente é criado ou
//  exigido (FR-002). O agregado da empresa em si é preenchido depois, em `ProviderRegistrationView`.
//

import Foundation

enum ProviderSignUpField: Hashable, CaseIterable {
    case email, password, passwordConfirmation
}

/// Rascunho editável, mantido somente em memória.
struct ProviderSignUpDraft {
    var email: String = ""
    var password: String = ""
    var passwordConfirmation: String = ""

    var hasMeaningfulContent: Bool { !email.isEmpty }
}

enum ProviderSignUpFieldError: Hashable {
    case required
    case invalidFormat
    case passwordTooShort
    case passwordMismatch
    case unavailable
}

struct ProviderSignUpFieldErrors: Equatable {
    var email: ProviderSignUpFieldError?
    var password: ProviderSignUpFieldError?
    var passwordConfirmation: ProviderSignUpFieldError?

    var isEmpty: Bool { email == nil && password == nil && passwordConfirmation == nil }

    var firstInvalidField: ProviderSignUpField? {
        if email != nil { return .email }
        if password != nil { return .password }
        if passwordConfirmation != nil { return .passwordConfirmation }
        return nil
    }
}

struct ProviderSignUpFocusRequest: Equatable {
    let field: ProviderSignUpField
    let requestID: Int
}

/// Saída de domínio do Repository — nunca um `Error` lançado.
enum ProviderSignUpResult: Equatable {
    case success(userID: UUID)
    case emailUnavailable
    case invalidServerInput
    case rateLimited
    case offline
    case serviceUnavailable
    case environmentMisconfigured
    case unknown
}

enum ProviderSignUpSubmissionState: Equatable {
    case editing
    case submitting
    case failure(reason: ProviderSignUpResult)
    case success
}

struct ProviderSignUpUiState {
    var draft = ProviderSignUpDraft()
    var fieldErrors = ProviderSignUpFieldErrors()
    var focusRequest: ProviderSignUpFocusRequest?
    var submission: ProviderSignUpSubmissionState = .editing

    var hasDraft: Bool { draft.hasMeaningfulContent }

    var isInputEnabled: Bool {
        if case .submitting = submission { return false }
        return true
    }

    var isSubmitting: Bool {
        if case .submitting = submission { return true }
        return false
    }
}
