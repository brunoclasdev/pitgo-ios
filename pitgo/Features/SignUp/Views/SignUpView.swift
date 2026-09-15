//
//  SignUpView.swift
//  pitgo
//
//  Tela de cadastro (ver contracts/account-registration.md). Sem `TabView` — o cadastro fica fora
//  da área autenticada. `onAuthenticated(userID:)` só é chamado depois que o Repository já
//  persistiu a pendência de onboarding (ver `SignUpRepository.ensureProfile`) — o chamador então
//  aciona `SessionStore.bootstrap()`, cuja troca de `RootPhase` descarta esta View.
//

import SwiftUI

struct SignUpView: View {
    @Environment(\.pitGoTokens) private var tokens
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SignUpViewModel
    @FocusState private var focusedField: SignUpField?
    @State private var isPasswordVisible = false
    @State private var isConfirmationVisible = false
    @State private var showDiscardConfirmation = false

    let onAuthenticated: (UUID) -> Void

    init(repository: SignUpRepository, onAuthenticated: @escaping (UUID) -> Void) {
        _viewModel = StateObject(wrappedValue: SignUpViewModel(repository: repository))
        self.onAuthenticated = onAuthenticated
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                personTypeSection
                nameField
                emailField
                phoneField
                documentField
                passwordField
                passwordConfirmationField
                submissionBanner
                submitButton
            }
            .padding(16)
        }
        .background(tokens.background)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Criar conta")
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
        .onChange(of: focusRequestKey) { _ in
            if let request = viewModel.state.focusRequest {
                focusedField = request.field
            }
        }
        .onChange(of: viewModel.state.submission) { newValue in
            if newValue == .success, let userID = viewModel.completedUserID {
                onAuthenticated(userID)
            }
        }
    }

    private var focusRequestKey: Int? {
        viewModel.state.focusRequest?.requestID
    }

    private func handleBack() {
        guard !viewModel.state.isSubmitting else { return }
        if viewModel.state.hasDraft {
            showDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    // MARK: - Sections

    private var personTypeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tipo de pessoa")
                .font(PitGoTypography.caption)
                .foregroundStyle(tokens.textSecondary)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 12) {
                ForEach(PersonType.allCases, id: \.self) { personType in
                    PersonTypeButton(
                        personType: personType,
                        isSelected: viewModel.state.draft.personType == personType,
                        action: { viewModel.selectPersonType(personType) }
                    )
                }
            }
            .focused($focusedField, equals: .personType)

            if let error = viewModel.state.fieldErrors.personType {
                errorText(error)
            }
        }
    }

    private var nameField: some View {
        labeledField(label: viewModel.state.nameLabel, error: viewModel.state.fieldErrors.name) {
            TextField("", text: Binding(get: { viewModel.state.draft.name }, set: { viewModel.updateName($0) }))
                .textContentType(.name)
                .focused($focusedField, equals: .name)
                .disabled(!viewModel.state.isInputEnabled)
        }
    }

    private var emailField: some View {
        labeledField(label: "E-mail", error: viewModel.state.fieldErrors.email) {
            TextField("", text: Binding(get: { viewModel.state.draft.email }, set: { viewModel.updateEmail($0) }))
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .email)
                .disabled(!viewModel.state.isInputEnabled)
        }
    }

    private var phoneField: some View {
        labeledField(label: "Telefone", error: viewModel.state.fieldErrors.phone) {
            TextField(
                "",
                text: Binding(
                    get: { SignUpValidation.formatPhone(viewModel.state.draft.phone) },
                    set: { viewModel.updatePhone($0) }
                )
            )
            .keyboardType(.numberPad)
            .textContentType(.telephoneNumber)
            .focused($focusedField, equals: .phone)
            .disabled(!viewModel.state.isInputEnabled)
        }
    }

    private var documentField: some View {
        labeledField(label: viewModel.state.documentLabel, error: viewModel.state.fieldErrors.document) {
            TextField(
                "",
                text: Binding(
                    get: {
                        guard let personType = viewModel.state.draft.personType else { return "" }
                        return personType == .individual
                            ? SignUpValidation.formatCPF(viewModel.state.draft.document)
                            : SignUpValidation.formatCNPJ(viewModel.state.draft.document)
                    },
                    set: { viewModel.updateDocument($0) }
                )
            )
            .keyboardType(viewModel.state.draft.personType == .company ? .asciiCapable : .numberPad)
            .textInputAutocapitalization(.characters)
            .focused($focusedField, equals: .document)
            .disabled(!viewModel.state.isInputEnabled || viewModel.state.draft.personType == nil)
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
        if case .failure(let reason, let profilePending) = viewModel.state.submission {
            Text(bannerMessage(for: reason, profilePending: profilePending))
                .font(PitGoTypography.caption)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var submitButton: some View {
        VStack(spacing: 8) {
            Button(action: submitOrRetry) {
                ZStack {
                    if viewModel.state.isSubmitting {
                        ProgressView().tint(.white)
                    }
                    Text(submitButtonTitle)
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
    }

    private var submitButtonTitle: LocalizedStringResource {
        if case .failure(_, let profilePending) = viewModel.state.submission, profilePending {
            return "Tentar novamente"
        }
        return "Criar conta"
    }

    private func submitOrRetry() {
        if case .failure(_, let profilePending) = viewModel.state.submission, profilePending {
            viewModel.retry()
        } else {
            viewModel.submit()
        }
    }

    private func bannerMessage(for reason: RegistrationResult, profilePending: Bool) -> LocalizedStringResource {
        if profilePending {
            return "Sua conta foi criada, mas ainda estamos confirmando seu perfil. Toque em Tentar novamente."
        }
        switch reason {
        case .emailUnavailable:
            return "Não foi possível concluir com estes dados. Verifique o e-mail informado."
        case .documentUnavailable:
            return "Não foi possível concluir com estes dados. Verifique o documento informado."
        case .invalidServerInput:
            return "Alguns dados não puderam ser aceitos. Revise o formulário."
        case .rateLimited:
            return "Muitas tentativas em pouco tempo. Aguarde um momento antes de tentar de novo."
        case .offline:
            return "Sem conexão com a internet. Verifique sua rede e tente novamente."
        case .serviceUnavailable:
            return "Não foi possível concluir agora. Tente novamente em instantes."
        default:
            return "Não foi possível concluir o cadastro. Tente novamente."
        }
    }

    // MARK: - Helpers

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
                errorText(error)
            }
        }
    }

    private func errorText(_ error: SignUpFieldError) -> some View {
        Text(message(for: error))
            .font(PitGoTypography.caption)
            .foregroundStyle(.red)
    }

    private func message(for error: SignUpFieldError) -> LocalizedStringResource {
        switch error {
        case .required: "Este campo é obrigatório."
        case .invalidFormat: "Verifique o formato informado."
        case .passwordTooShort: "A senha deve ter no mínimo 8 caracteres."
        case .passwordMismatch: "As senhas não coincidem."
        case .unavailable: "Este valor não está disponível."
        }
    }
}

private struct PersonTypeButton: View {
    @Environment(\.pitGoTokens) private var tokens
    let personType: PersonType
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").accessibilityHidden(true)
                }
                Text(personType.title)
            }
            .font(PitGoTypography.categoryTitle)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .foregroundStyle(isSelected ? tokens.accent : tokens.textPrimary)
        .background(isSelected ? tokens.purpleContainer : tokens.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? tokens.accent : tokens.outline, lineWidth: isSelected ? 1.5 : 1)
        )
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
