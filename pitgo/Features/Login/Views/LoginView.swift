//
//  LoginView.swift
//  pitgo
//
//  Ver contracts/navigation.md "LoginView". Sem `TabView`; back nativo do `NavigationStack`.
//

import SwiftUI

struct LoginView: View {
    @Environment(\.pitGoTokens) private var tokens
    @StateObject private var viewModel: LoginViewModel
    @FocusState private var focusedField: SignUpField?
    @State private var isPasswordVisible = false

    init(sessionStore: SessionStore) {
        _viewModel = StateObject(wrappedValue: LoginViewModel(sessionStore: sessionStore))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Entrar")
                    .font(PitGoTypography.sectionTitle)
                    .foregroundStyle(tokens.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                emailField
                passwordField
                submissionBanner
                submitButton
                NavigationLink("Esqueci minha senha") {
                    PasswordRecoveryView(client: SupabaseClientProvider.client)
                }
            }
            .padding(16)
        }
        .background(tokens.background)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Entrar")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.state.focusRequest?.requestID) { _ in
            if let request = viewModel.state.focusRequest {
                focusedField = request.field
            }
        }
    }

    private var emailField: some View {
        labeledField(label: "E-mail", error: viewModel.state.fieldErrors.email) {
            TextField("", text: Binding(get: { viewModel.state.email }, set: { viewModel.updateEmail($0) }))
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .email)
                .disabled(!viewModel.state.isInputEnabled)
        }
    }

    private var passwordField: some View {
        labeledField(label: "Senha", error: viewModel.state.fieldErrors.password) {
            HStack {
                Group {
                    if isPasswordVisible {
                        TextField("", text: Binding(get: { viewModel.state.password }, set: { viewModel.updatePassword($0) }))
                    } else {
                        SecureField("", text: Binding(get: { viewModel.state.password }, set: { viewModel.updatePassword($0) }))
                    }
                }
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .disabled(!viewModel.state.isInputEnabled)

                Button(action: { isPasswordVisible.toggle() }) {
                    Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(isPasswordVisible ? "Ocultar senha" : "Mostrar senha")
            }
        }
    }

    @ViewBuilder
    private var submissionBanner: some View {
        if case let .failure(reason) = viewModel.state.submission {
            Text(message(for: reason))
                .font(PitGoTypography.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var submitButton: some View {
        Button(action: { viewModel.submit() }) {
            ZStack {
                if viewModel.state.isSubmitting {
                    ProgressView().tint(.white)
                }
                Text("Entrar")
                    .opacity(viewModel.state.isSubmitting ? 0 : 1)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .foregroundStyle(.white)
        .background(tokens.accent)
        .clipShape(Capsule())
        .frame(minHeight: 56)
        .disabled(viewModel.state.isSubmitting)
    }

    private func message(for reason: LoginFailureReason) -> LocalizedStringResource {
        switch reason {
        case .invalidCredentials: "E-mail ou senha inválidos."
        case .offline: "Sem conexão com a internet. Verifique sua rede e tente novamente."
        case .timeout: "Não foi possível concluir agora. Tente novamente em instantes."
        case .rateLimited: "Muitas tentativas em pouco tempo. Aguarde um momento antes de tentar de novo."
        case .service: "Não foi possível concluir agora. Tente novamente em instantes."
        case .unknown: "Não foi possível entrar. Tente novamente."
        }
    }

    @ViewBuilder
    private func labeledField<Content: View>(
        label: LocalizedStringResource,
        error: SignUpFieldError?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(PitGoTypography.caption)
                .foregroundStyle(tokens.textSecondary)

            content()
                .padding()
                .frame(minHeight: 44)
                .background(tokens.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(error == nil ? tokens.outline : Color.red, lineWidth: 1)
                )

            if let error {
                Text(fieldErrorMessage(error))
                    .font(PitGoTypography.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func fieldErrorMessage(_ error: SignUpFieldError) -> LocalizedStringResource {
        switch error {
        case .required: "Este campo é obrigatório."
        case .invalidFormat: "Verifique o formato informado."
        default: "Verifique o valor informado."
        }
    }
}
