//
//  ProviderSignUpViewModel.swift
//  pitgo
//

import Foundation

@Observable
@MainActor
final class ProviderSignUpViewModel {
    private(set) var state = ProviderSignUpUiState()
    /// Definido somente quando `state.submission == .success`.
    private(set) var completedUserID: UUID?

    private let repository: ProviderSignUpRepository
    private var focusRequestID = 0

    init(repository: ProviderSignUpRepository) {
        self.repository = repository
    }

    func updateEmail(_ value: String) {
        guard state.isInputEnabled else { return }
        state.draft.email = value
        state.fieldErrors.email = nil
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

    func submit() {
        switch state.submission {
        case .editing, .failure:
            break
        case .submitting, .success:
            return
        }

        let errors = validate()
        state.fieldErrors = errors
        guard errors.isEmpty else {
            focusRequestID += 1
            if let field = errors.firstInvalidField {
                state.focusRequest = ProviderSignUpFocusRequest(field: field, requestID: focusRequestID)
            }
            return
        }

        let email = SignUpValidation.normalizeEmail(state.draft.email)
        let password = state.draft.password
        state.submission = .submitting

        Task { [weak self] in
            guard let self else { return }
            let result = await repository.register(email: email, password: password)
            await MainActor.run {
                self.apply(result)
            }
        }
    }

    private func apply(_ result: ProviderSignUpResult) {
        state.draft.password = ""
        state.draft.passwordConfirmation = ""
        switch result {
        case let .success(userID):
            completedUserID = userID
            state.submission = .success
        case .emailUnavailable:
            state.fieldErrors.email = .unavailable
            state.submission = .failure(reason: result)
        default:
            state.submission = .failure(reason: result)
        }
    }

    private func validate() -> ProviderSignUpFieldErrors {
        var errors = ProviderSignUpFieldErrors()
        let draft = state.draft

        let email = SignUpValidation.normalizeEmail(draft.email)
        if email.isEmpty {
            errors.email = .required
        } else if !SignUpValidation.isValidEmail(email) {
            errors.email = .invalidFormat
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

        return errors
    }
}
