//
//  LoginModels.swift
//  pitgo
//

import Foundation

enum LoginFailureReason {
    case invalidCredentials
    case offline
    case timeout
    case rateLimited
    case service
    case unknown
}

struct LoginFieldErrors: Equatable {
    var email: SignUpFieldError?
    var password: SignUpFieldError?

    var isEmpty: Bool { email == nil && password == nil }

    var firstInvalidField: SignUpField? {
        if email != nil { return .email }
        if password != nil { return .password }
        return nil
    }
}

enum LoginSubmissionState: Equatable {
    case editing
    case submitting
    case failure(LoginFailureReason)

    static func == (lhs: LoginSubmissionState, rhs: LoginSubmissionState) -> Bool {
        switch (lhs, rhs) {
        case (.editing, .editing), (.submitting, .submitting):
            true
        case let (.failure(a), .failure(b)):
            a == b
        default:
            false
        }
    }
}

extension LoginFailureReason: Equatable {}

struct LoginUiState {
    var email: String = ""
    var password: String = ""
    var fieldErrors: LoginFieldErrors = .init()
    var focusRequest: FocusRequest?
    var submission: LoginSubmissionState = .editing

    var isInputEnabled: Bool {
        if case .submitting = submission { return false }
        return true
    }

    var isSubmitting: Bool {
        if case .submitting = submission { return true }
        return false
    }
}
