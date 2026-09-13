//
//  SignUpModels.swift
//  pitgo
//

import Foundation

enum PersonType: Hashable, CaseIterable {
    case individual   // Pessoa física — exige CPF
    case company      // Pessoa jurídica — exige CNPJ
}

extension PersonType {
    var title: LocalizedStringResource {
        switch self {
        case .individual: "Pessoa física"
        case .company: "Pessoa jurídica"
        }
    }

    var nameLabel: LocalizedStringResource {
        switch self {
        case .individual: "Nome completo"
        case .company: "Razão social / nome da empresa"
        }
    }

    var documentLabel: LocalizedStringResource {
        switch self {
        case .individual: "CPF"
        case .company: "CNPJ"
        }
    }

    var documentMaxLength: Int {
        switch self {
        case .individual: 11
        case .company: 14
        }
    }
}

/// Campos focáveis, na ordem visual usada para direcionar o foco ao primeiro erro (FR-009).
enum SignUpField: Hashable, CaseIterable {
    case personType
    case name
    case email
    case phone
    case document
    case password
    case passwordConfirmation
}

/// Rascunho editável, mantido somente em memória (nunca `Codable`/persistido — FR-020).
struct SignUpDraft {
    var personType: PersonType?
    var name: String = ""
    var email: String = ""
    var phone: String = ""              // dígitos puros
    var document: String = ""           // CPF (dígitos) ou CNPJ (alfanumérico maiúsculo)
    var password: String = ""
    var passwordConfirmation: String = ""

    /// `true` quando algum campo não sensível já foi preenchido — usado para exigir confirmação
    /// de descarte ao voltar (FR-021). Senha não sensibiliza esta checagem sozinha.
    var hasMeaningfulContent: Bool {
        personType != nil || !name.isEmpty || !email.isEmpty || !phone.isEmpty || !document.isEmpty
    }
}

enum SignUpFieldError: Hashable {
    case required
    case invalidFormat
    case passwordTooShort
    case passwordMismatch
    case unavailable
}

struct SignUpFieldErrors: Equatable {
    var personType: SignUpFieldError?
    var name: SignUpFieldError?
    var email: SignUpFieldError?
    var phone: SignUpFieldError?
    var document: SignUpFieldError?
    var password: SignUpFieldError?
    var passwordConfirmation: SignUpFieldError?

    var isEmpty: Bool {
        personType == nil && name == nil && email == nil && phone == nil
            && document == nil && password == nil && passwordConfirmation == nil
    }

    /// Primeiro campo com erro, na ordem visual (FR-009).
    var firstInvalidField: SignUpField? {
        if personType != nil { return .personType }
        if name != nil { return .name }
        if email != nil { return .email }
        if phone != nil { return .phone }
        if document != nil { return .document }
        if password != nil { return .password }
        if passwordConfirmation != nil { return .passwordConfirmation }
        return nil
    }
}

struct FocusRequest: Equatable {
    let field: SignUpField
    let requestID: Int
}

/// Entrada normalizada e validada, passada do ViewModel ao Repository (ver data-model.md).
/// Invariante: exatamente um entre `cpf`/`cnpj` é não nulo.
struct AccountRegistration {
    let personType: PersonType
    let name: String
    let email: String
    let phone: String
    let cpf: String?
    let cnpj: String?
    let password: String

    init(personType: PersonType, name: String, email: String, phone: String, normalizedDocument: String, password: String) {
        self.personType = personType
        self.name = name
        self.email = email
        self.phone = phone
        switch personType {
        case .individual:
            cpf = normalizedDocument
            cnpj = nil
        case .company:
            cpf = nil
            cnpj = normalizedDocument
        }
        self.password = password
    }
}

/// Saída de domínio do Repository — nunca um `Error` lançado (ver research.md §7).
enum RegistrationResult: Equatable {
    case success(userID: UUID)
    case emailUnavailable
    case documentUnavailable
    case invalidServerInput
    case rateLimited
    case offline
    case serviceUnavailable
    case profileRecoveryRequired
    case environmentMisconfigured
    case unknown
}

enum SignUpStage {
    case creatingAccount
    case ensuringProfile
    case recoveringProfile
}

enum SignUpSubmissionState: Equatable {
    case editing
    case submitting(SignUpStage)
    case failure(reason: RegistrationResult, profilePending: Bool)
    case success

    static func == (lhs: SignUpSubmissionState, rhs: SignUpSubmissionState) -> Bool {
        switch (lhs, rhs) {
        case (.editing, .editing), (.success, .success):
            true
        case let (.submitting(a), .submitting(b)):
            a == b
        case let (.failure(reasonA, pendingA), .failure(reasonB, pendingB)):
            reasonA == reasonB && pendingA == pendingB
        default:
            false
        }
    }
}

struct SignUpUiState {
    var draft: SignUpDraft = SignUpDraft()
    var fieldErrors: SignUpFieldErrors = SignUpFieldErrors()
    var focusRequest: FocusRequest?
    var submission: SignUpSubmissionState = .editing

    var hasDraft: Bool { draft.hasMeaningfulContent }

    /// `false` durante qualquer `.submitting` — campos e CTA ficam desabilitados (FR-016).
    var isInputEnabled: Bool {
        if case .submitting = submission { return false }
        return true
    }

    var isSubmitting: Bool {
        if case .submitting = submission { return true }
        return false
    }

    var nameLabel: LocalizedStringResource {
        draft.personType?.nameLabel ?? "Nome completo"
    }

    var documentLabel: LocalizedStringResource {
        draft.personType?.documentLabel ?? "Documento"
    }
}
