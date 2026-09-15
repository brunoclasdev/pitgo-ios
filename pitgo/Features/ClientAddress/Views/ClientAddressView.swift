//
//  ClientAddressView.swift
//  pitgo
//
//  Cadastro/edição do endereço do cliente (`014` US5/US6) — aberto pela Home ou pelo Perfil.
//

import SwiftUI

struct ClientAddressView: View {
    @Environment(\.pitGoTokens) private var tokens
    @StateObject private var viewModel: ClientAddressViewModel

    let onFinished: () -> Void
    let onSessionExpired: () -> Void

    init(
        repository: ClientAddressRepository,
        locationRepository: DeviceLocationRepository,
        onFinished: @escaping () -> Void,
        onSessionExpired: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ClientAddressViewModel(repository: repository, locationRepository: locationRepository))
        self.onFinished = onFinished
        self.onSessionExpired = onSessionExpired
    }

    var body: some View {
        content
            .navigationTitle("Endereço")
            .navigationBarTitleDisplayMode(.inline)
            .task { viewModel.load() }
            .onChange(of: isSessionExpired) { expired in
                if expired { onSessionExpired() }
            }
    }

    private var isSessionExpired: Bool {
        if case .sessionExpired = viewModel.state { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Carregando…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(tokens.background)
        case let .editing(draft, fieldErrors, submission, savedAddress):
            editingView(draft, fieldErrors: fieldErrors, submission: submission, savedAddress: savedAddress)
        case .sessionExpired:
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).background(tokens.background)
        }
    }

    private func editingView(_ draft: ClientAddressDraft, fieldErrors: [ClientAddressField: ClientAddressFieldError], submission: ClientAddressSubmission, savedAddress: ClientAddress?) -> some View {
        let isInputEnabled = submission != .submitting
        return List {
            if savedAddress != nil, submission == .idle {
                Section {
                    Label("Endereço salvo", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityAddTraits(.updatesFrequently)
                    Button("Concluído", action: onFinished)
                        .frame(minHeight: 44)
                }
            }
            Section("CEP") {
                HStack(spacing: 8) {
                    TextField(
                        "",
                        text: Binding(
                            get: { BrazilianTextFormatting.formatCEP(draft.postalCode) },
                            set: { viewModel.update(.postalCode, text: $0) }
                        )
                    )
                    .keyboardType(.numberPad)
                    .disabled(!isInputEnabled)
                    Button(action: { viewModel.lookupPostalCode() }) {
                        if draft.postalCodeLookup.isLoading { ProgressView() } else { Text("Buscar CEP") }
                    }
                    .frame(minHeight: 44)
                    .disabled(!isInputEnabled || draft.postalCodeLookup.isLoading || draft.postalCode.count != 8)
                }
                if let error = fieldErrors[.postalCode] {
                    Text(fieldErrorMessage(error)).font(PitGoTypography.caption).foregroundStyle(.red)
                }
            }
            Section("Endereço") {
                labeledField("Rua", error: fieldErrors[.street]) {
                    TextField("", text: Binding(get: { draft.street }, set: { viewModel.update(.street, text: $0) })).disabled(!isInputEnabled)
                }
                labeledField("Número", error: fieldErrors[.number]) {
                    TextField("", text: Binding(get: { draft.number }, set: { viewModel.update(.number, text: $0) })).disabled(!isInputEnabled)
                }
                labeledField("Complemento (opcional)", error: nil) {
                    TextField("", text: Binding(get: { draft.complement }, set: { viewModel.update(.complement, text: $0) })).disabled(!isInputEnabled)
                }
                labeledField("Bairro", error: fieldErrors[.neighborhood]) {
                    TextField("", text: Binding(get: { draft.neighborhood }, set: { viewModel.update(.neighborhood, text: $0) })).disabled(!isInputEnabled)
                }
                labeledField("Cidade", error: fieldErrors[.city]) {
                    TextField("", text: Binding(get: { draft.city }, set: { viewModel.update(.city, text: $0) })).disabled(!isInputEnabled)
                }
                labeledField("Estado", error: fieldErrors[.state]) {
                    Picker("", selection: Binding(get: { draft.state }, set: { viewModel.updateState($0) })) {
                        Text("Selecione").tag(BrazilianState?.none)
                        ForEach(BrazilianState.allCases) { state in
                            Text(state.rawValue).tag(BrazilianState?.some(state))
                        }
                    }
                    .disabled(!isInputEnabled)
                }
            }
            if case let .failure(reason) = submission {
                Section {
                    Text(message(for: reason)).font(PitGoTypography.caption).foregroundStyle(.red)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            Section {
                Button(action: { viewModel.save() }) {
                    ZStack {
                        if submission == .submitting { ProgressView().tint(.white) }
                        Text("Salvar endereço").opacity(submission == .submitting ? 0 : 1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .foregroundStyle(.white)
                .background(tokens.accent)
                .clipShape(Capsule())
                .frame(minHeight: 56)
                .disabled(!isInputEnabled)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .background(tokens.background)
    }

    private func labeledField<Content: View>(_ label: LocalizedStringResource, error: ClientAddressFieldError?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
            content()
            if let error {
                Text(fieldErrorMessage(error)).font(PitGoTypography.caption).foregroundStyle(.red)
            }
        }
    }

    private func fieldErrorMessage(_ error: ClientAddressFieldError) -> String {
        switch error {
        case .required: "Este campo é obrigatório."
        case .invalidFormat: "Informe um CEP com 8 dígitos."
        case .notFound: "CEP não encontrado."
        }
    }

    private func message(for reason: ClientAddressFailureReason) -> String {
        switch reason {
        case .invalidInput: "Alguns dados não puderam ser aceitos. Revise o formulário."
        case .locationRequired: "Precisamos da sua localização para salvar o endereço. Permita o acesso e tente novamente."
        case .sessionExpired: "Sua sessão expirou. Entre novamente."
        case .offline: "Sem conexão com a internet. Verifique sua rede e tente novamente."
        case .service: "Não foi possível salvar agora. Tente novamente em instantes."
        case .unknown: "Não foi possível salvar o endereço. Tente novamente."
        }
    }
}
