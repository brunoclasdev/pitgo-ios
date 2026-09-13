//
//  SignUpViewModel.swift
//  pitgo
//

import Foundation

@Observable
@MainActor
final class SignUpViewModel {
    private(set) var state = SignUpUiState()
    /// Definido somente quando `state.submission == .success`; a pendência de onboarding já foi
    /// persistida pelo Repository antes deste valor existir (ver `SignUpRepository.ensureProfile`).
    private(set) var completedUserID: UUID?

    private let repository: SignUpRepository
    private var focusRequestID = 0
    private var lastRegistration: AccountRegistration?

    init(repository: SignUpRepository) {
        self.repository = repository
    }

    // MARK: - Field events

    func selectPersonType(_ personType: PersonType) {
        guard state.isInputEnabled else { return }
        state.draft.personType = personType
        state.draft.document = ""
        state.fieldErrors.personType = nil
        state.fieldErrors.document = nil
    }

    func updateName(_ value: String) {
        guard state.isInputEnabled else { return }
        state.draft.name = value
        state.fieldErrors.name = nil
    }

    func updateEmail(_ value: String) {
        guard state.isInputEnabled else { return }
        state.draft.email = value
        state.fieldErrors.email = nil
    }

    func updatePhone(_ rawInput: String) {
        guard state.isInputEnabled else { return }
        state.draft.phone = String(SignUpValidation.digitsOnly(rawInput).prefix(11))
        state.fieldErrors.phone = nil
    }

    func updateDocument(_ rawInput: String) {
        guard state.isInputEnabled, let personType = state.draft.personType else { return }
        let normalized = SignUpValidation.normalizeDocument(rawInput, personType: personType)
        state.draft.document = String(normalized.prefix(personType.documentMaxLength))
        state.fieldErrors.document = nil
    }

    func updatePassword(_ value: String) {
        guard state.isInputEnabled else { return }
        state.draft.password = value
        state.fieldErrors.password = nil
    }

    func updatePasswordConfirmation(_ value: String) {
        guard state.isInputEnabled else { return }
        state.draft.passwordConfirmation = value
        state.fieldErrors.passwordConfirmation = nil
    }

    // MARK: - Submission

    func submit() {
        // Guarda síncrona contra toque duplo — nenhuma segunda `Task` é criada enquanto submitting
        // ou depois de sucesso; reenvio a partir de uma falha é permitido.
        switch state.submission {
        case .editing, .failure:
            break
        case .submitting, .success:
            return
        }

        let errors = validate()
        state.fieldErrors = errors
        guard errors.isEmpty, let registration = buildRegistration() else {
            focusRequestID += 1
            if let field = errors.firstInvalidField {
                state.focusRequest = FocusRequest(field: field, requestID: focusRequestID)
            }
            return
        }

        lastRegistration = registration
        state.submission = .submitting(.creatingAccount)

        Task { [weak self] in
            guard let self else { return }
            let result = await repository.register(registration)
            await MainActor.run {
                self.apply(result)
            }
        }
    }

    /// Reenvia somente a recuperação de perfil (não um novo signup) a partir de uma falha
    /// `profileRecoveryRequired`/`environmentMisconfigured` (ver contracts/account-registration.md).
    func retry() {
        guard case .failure(let reason, let profilePending) = state.submission,
              profilePending || reason == .profileRecoveryRequired,
              let registration = lastRegistration else {
            submit()
            return
        }

        state.submission = .submitting(.recoveringProfile)
        Task { [weak self] in
            guard let self else { return }
            let result = await repository.retryProfile(registration)
            await MainActor.run {
                self.apply(result)
            }
        }
    }

    private func apply(_ result: RegistrationResult) {
        switch result {
        case let .success(userID):
            state.draft.password = ""
            state.draft.passwordConfirmation = ""
            completedUserID = userID
            state.submission = .success
        case .profileRecoveryRequired, .environmentMisconfigured:
            state.draft.password = ""
            state.draft.passwordConfirmation = ""
            state.submission = .failure(reason: result, profilePending: true)
        default:
            state.draft.password = ""
            state.draft.passwordConfirmation = ""
            mapFieldError(for: result)
            state.submission = .failure(reason: result, profilePending: false)
        }
    }

    private func mapFieldError(for result: RegistrationResult) {
        switch result {
        case .emailUnavailable:
            state.fieldErrors.email = .unavailable
        case .documentUnavailable:
            state.fieldErrors.document = .unavailable
        default:
            break
        }
    }

    // MARK: - Validation

    private func validate() -> SignUpFieldErrors {
        var errors = SignUpFieldErrors()
        let draft = state.draft

        guard let personType = draft.personType else {
            errors.personType = .required
            // Sem tipo de pessoa, os demais campos ainda são checados independentemente (US2 AC1).
            validateCommonFields(draft, into: &errors)
            return errors
        }

        validateCommonFields(draft, into: &errors)

        let document = SignUpValidation.normalizeDocument(draft.document, personType: personType)
        if document.isEmpty {
            errors.document = .required
        } else {
            let isValid = switch personType {
            case .individual: SignUpValidation.isValidCPF(document)
            case .company: SignUpValidation.isValidCNPJ(document)
            }
            if !isValid {
                errors.document = .invalidFormat
            }
        }

        return errors
    }

    private func validateCommonFields(_ draft: SignUpDraft, into errors: inout SignUpFieldErrors) {
        let name = SignUpValidation.trim(draft.name)
        if name.isEmpty {
            errors.name = .required
        }

        let email = SignUpValidation.normalizeEmail(draft.email)
        if email.isEmpty {
            errors.email = .required
        } else if !SignUpValidation.isValidEmail(email) {
            errors.email = .invalidFormat
        }

        let phoneDigits = SignUpValidation.digitsOnly(draft.phone)
        if phoneDigits.isEmpty {
            errors.phone = .required
        } else if !SignUpValidation.isValidBrazilianPhone(phoneDigits) {
            errors.phone = .invalidFormat
        }

        if draft.password.isEmpty {
            errors.password = .required
        } else if draft.password.count < 8 {
            errors.password = .passwordTooShort
        }

        if draft.passwordConfirmation.isEmpty {
            errors.passwordConfirmation = .required
        } else if draft.passwordConfirmation != draft.password {
            errors.passwordConfirmation = .passwordMismatch
        }
    }

    private func buildRegistration() -> AccountRegistration? {
        guard let personType = state.draft.personType else { return nil }
        let document = SignUpValidation.normalizeDocument(state.draft.document, personType: personType)
        return AccountRegistration(
            personType: personType,
            name: SignUpValidation.trim(state.draft.name),
            email: SignUpValidation.normalizeEmail(state.draft.email),
            phone: SignUpValidation.digitsOnly(state.draft.phone),
            normalizedDocument: document,
            password: state.draft.password
        )
    }
}
