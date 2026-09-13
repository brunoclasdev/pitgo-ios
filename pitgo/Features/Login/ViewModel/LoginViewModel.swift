//
//  LoginViewModel.swift
//  pitgo
//
//  Delega a `SessionStore` — a única fronteira que chama `client.auth` (ver research.md §1).
//

import Foundation

@Observable
@MainActor
final class LoginViewModel {
    private(set) var state = LoginUiState()

    private let sessionStore: SessionStore
    private var focusRequestID = 0

    init(sessionStore: SessionStore) {
        self.sessionStore = sessionStore
    }

    func updateEmail(_ value: String) {
        guard state.isInputEnabled else { return }
        state.email = value
        state.fieldErrors.email = nil
    }

    func updatePassword(_ value: String) {
        guard state.isInputEnabled else { return }
        state.password = value
        state.fieldErrors.password = nil
    }

    func submit() {
        guard state.isInputEnabled else { return }

        let email = SignUpValidation.normalizeEmail(state.email)
        var errors = LoginFieldErrors()
        if email.isEmpty {
            errors.email = .required
        } else if !SignUpValidation.isValidEmail(email) {
            errors.email = .invalidFormat
        }
        if state.password.isEmpty {
            errors.password = .required
        }

        state.fieldErrors = errors
        guard errors.isEmpty else {
            focusRequestID += 1
            if let field = errors.firstInvalidField {
                state.focusRequest = FocusRequest(field: field, requestID: focusRequestID)
            }
            return
        }

        let password = state.password
        state.submission = .submitting

        Task { [weak self] in
            guard let self else { return }
            let failure = await sessionStore.signIn(email: email, password: password)
            await MainActor.run {
                self.state.password = ""
                if let failure {
                    self.state.submission = .failure(failure)
                }
                // Sucesso: `SessionStore.state` já mudou para um dos três estados autenticados ou
                // `.blocked`; `PitGoRootView` descarta esta View junto com a `NavigationStack` não
                // autenticada.
            }
        }
    }
}
