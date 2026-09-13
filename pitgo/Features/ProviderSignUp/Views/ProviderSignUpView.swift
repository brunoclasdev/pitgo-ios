//
//  ProviderSignUpView.swift
//  pitgo
//
//  Cadastro público de credenciais da empresa (ver contracts/navigation-session.md "Signup stacks").
//  Sem `TabView`; abre diretamente o cadastro empresarial, nunca o formulário de profile (FR-002).
//

import SwiftUI

struct ProviderSignUpView: View {
    @Environment(\.pitGoTokens) private var tokens
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: ProviderSignUpViewModel
    @FocusState private var focusedField: ProviderSignUpField?
    @State private var isPasswordVisible = false
    @State private var isConfirmationVisible = false
    @State private var showDiscardConfirmation = false

    let onAuthenticated: (UUID) -> Void

    init(repository: ProviderSignUpRepository, onAuthenticated: @escaping (UUID) -> Void) {
        _viewModel = State(initialValue: ProviderSignUpViewModel(repository: repository))
        self.onAuthenticated = onAuthenticated
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Crie a conta da sua empresa para cadastrar dados, categorias e localização.")
                    .font(PitGoTypography.body)
                    .foregroundStyle(tokens.textSecondary)

                emailField
                passwordField
                passwordConfirmationField
                submissionBanner
                submitButton
            }
            .padding(16)
        }
        .background(tokens.background)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Sou uma empresa")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: handleBack) {
                    Image(systemName: "chevron.left")
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Voltar")
                .disabled(viewModel.state.isSubmitting)
            }
        }
        .confirmationDialog(
            "Descartar cadastro?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Descartar", role: .destructive) { dismiss() }
            Button("Continuar editando", role: .cancel) {}
        }
        .onChange(of: viewModel.state.focusRequest?.requestID) { _, _ in
            if let request = viewModel.state.focusRequest {
                focusedField = request.field
            }
        }
        .onChange(of: viewModel.state.submission) { _, newValue in
            if newValue == .success, let userID = viewModel.completedUserID {
                onAuthenticated(userID)
            }
        }
    }

    private func handleBack() {
        guard !viewModel.state.isSubmitting else { return }
        if viewModel.state.hasDraft {
            showDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private var emailField: some View {
        labeledField(label: "E-mail comercial", error: viewModel.state.fieldErrors.email) {
            TextField("", text: Binding(get: { viewModel.state.draft.email }, set: { viewModel.updateEmail($0) }))
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .email)
                .disabled(!viewModel.state.isInputEnabled)
        }
    }

    private var passwordField: some View {
        labeledField(label: "Senha (mínimo 8 caracteres)", error: viewModel.state.fieldErrors.password) {
            HStack {
                Group {
                    if isPasswordVisible {
                        TextField("", text: Binding(get: { viewModel.state.draft.password }, set: { viewModel.updatePassword($0) }))
                    } else {
                        SecureField("", text: Binding(get: { viewModel.state.draft.password }, set: { viewModel.updatePassword($0) }))
                    }
                }
                .textContentType(.newPassword)
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

    private var passwordConfirmationField: some View {
        labeledField(label: "Confirmar senha", error: viewModel.state.fieldErrors.passwordConfirmation) {
            HStack {
                Group {
                    if isConfirmationVisible {
                        TextField("", text: Binding(get: { viewModel.state.draft.passwordConfirmation }, set: { viewModel.updatePasswordConfirmation($0) }))
                    } else {
                        SecureField("", text: Binding(get: { viewModel.state.draft.passwordConfirmation }, set: { viewModel.updatePasswordConfirmation($0) }))
                    }
                }
                .textContentType(.newPassword)
                .focused($focusedField, equals: .passwordConfirmation)
                .disabled(!viewModel.state.isInputEnabled)

                Button(action: { isConfirmationVisible.toggle() }) {
                    Image(systemName: isConfirmationVisible ? "eye.slash.fill" : "eye.fill")
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(isConfirmationVisible ? "Ocultar senha" : "Mostrar senha")
            }
        }
    }

    @ViewBuilder
    private var submissionBanner: some View {
        if case let .failure(reason) = viewModel.state.submission {
            Text(bannerMessage(for: reason))
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
                Text("Criar conta da empresa")
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

    private func bannerMessage(for reason: ProviderSignUpResult) -> LocalizedStringResource {
        switch reason {
        case .emailUnavailable:
            "Não foi possível concluir com estes dados. Verifique o e-mail informado."
        case .invalidServerInput:
            "Alguns dados não puderam ser aceitos. Revise o formulário."
        case .rateLimited:
            "Muitas tentativas em pouco tempo. Aguarde um momento antes de tentar de novo."
        case .offline:
            "Sem conexão com a internet. Verifique sua rede e tente novamente."
        case .serviceUnavailable:
            "Não foi possível concluir agora. Tente novamente em instantes."
        default:
            "Não foi possível concluir o cadastro. Tente novamente."
        }
    }

    @ViewBuilder
    private func labeledField<Content: View>(
        label: LocalizedStringResource,
        error: ProviderSignUpFieldError?,
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
                Text(message(for: error))
                    .font(PitGoTypography.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func message(for error: ProviderSignUpFieldError) -> LocalizedStringResource {
        switch error {
        case .required: "Este campo é obrigatório."
        case .invalidFormat: "Verifique o formato informado."
        case .passwordTooShort: "A senha deve ter no mínimo 8 caracteres."
        case .passwordMismatch: "As senhas não coincidem."
        case .unavailable: "Este valor não está disponível."
        }
    }
}
