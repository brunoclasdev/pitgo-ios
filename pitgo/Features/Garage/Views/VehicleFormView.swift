//
//  VehicleFormView.swift
//  pitgo
//
//  Compartilhado entre onboarding e Garagem (`origin`, único argumento não sensível — o `userID`
//  nunca atravessa a rota, ver contracts/navigation.md). Voltar com rascunho sujo exige confirmação.
//

import SwiftUI

struct VehicleFormView: View {
    @Environment(\.pitGoTokens) private var tokens
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: VehicleFormViewModel
    @FocusState private var focusedField: VehicleField?
    @State private var showDiscardConfirmation = false

    /// Quando presente, substitui o `dismiss()` padrão ao voltar/descartar — usado pela origem
    /// `.onboarding`, cujo contrato de navegação manda voltar direto para o convite (não para a
    /// Home) sem resolver a pendência (ver contracts/vehicle-form-ui.md "Navegação").
    private let onCancel: (() -> Void)?
    /// Delegado ao gate central de sessão (`SessionStore`, `006`) — nunca tratado como falha comum.
    private let onSessionExpired: (() -> Void)?

    init(
        repository: VehicleRepository,
        existingVehicleCount: Int,
        origin: VehicleFormOrigin,
        onSaved: @escaping (Vehicle) -> Void,
        onCancel: (() -> Void)? = nil,
        onSessionExpired: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: VehicleFormViewModel(
                repository: repository,
                existingVehicleCount: existingVehicleCount,
                origin: origin,
                onSaved: onSaved
            )
        )
        self.onCancel = onCancel
        self.onSessionExpired = onSessionExpired
    }

    private func cancel() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Categoria para transporte", selection: $viewModel.transportCategoryID) {
                        Text("Selecionar categoria").tag(UUID?.none)
                        ForEach(viewModel.categories) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Text("Informe a categoria para solicitar guincho, incluindo micro-ônibus.").font(.caption)
                    if viewModel.catalogFailed {
                        Button("Tentar carregar categorias") { Task { await viewModel.loadCatalog() } }
                    }
                    VehicleMakePicker(selection: Binding(get: { viewModel.state.input.brand }, set: { viewModel.update(.brand, text: $0) }))
                    if viewModel.state.fieldErrors[.brand] != nil { Text("Selecione a marca.").foregroundStyle(.red) }
                    textField(.model, label: "Modelo", keyboard: .default)
                    textField(.version, label: "Versão (opcional)", keyboard: .default)
                    textField(.manufactureYear, label: "Ano de fabricação (opcional)", keyboard: .numberPad)
                    textField(.modelYear, label: "Ano-modelo (opcional)", keyboard: .numberPad)
                    textField(.plate, label: "Placa (opcional)", keyboard: .asciiCapable, autocapitalize: .characters)
                    textField(.renavam, label: "Renavam (opcional)", keyboard: .numberPad)
                    textField(.chassis, label: "Chassi (opcional)", keyboard: .asciiCapable, autocapitalize: .characters)
                    textField(.color, label: "Cor (opcional)", keyboard: .default)
                    textField(.fuelType, label: "Combustível (opcional)", keyboard: .default)
                    textField(.transmission, label: "Câmbio (opcional)", keyboard: .default)
                    textField(.engine, label: "Motor (opcional)", keyboard: .default)
                    textField(.mileage, label: "Quilometragem (opcional)", keyboard: .numberPad)

                    if viewModel.state.showsPrimaryToggle {
                        Toggle(
                            "Tornar principal",
                            isOn: Binding(
                                get: { viewModel.state.input.makePrimary },
                                set: { viewModel.setMakePrimary($0) }
                            )
                        )
                        .disabled(!viewModel.state.isInputEnabled)
                    }

                    submissionBanner
                    submitButton
                }
                .padding(16)
            }
            .onChange(of: viewModel.state.focusRequest?.requestID) { _ in
                guard let request = viewModel.state.focusRequest else { return }
                withAnimation { proxy.scrollTo(request.field, anchor: .center) }
                Task {
                    // Aguarda a rolagem renderizar antes de focar — evita disputa entre o scroll
                    // programático e o scroll automático do teclado (contracts/vehicle-form-ui.md).
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    focusedField = request.field
                }
            }
        }
        .task { await viewModel.loadCatalog() }
        .background(tokens.background)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Cadastrar veículo")
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
            "Descartar dados do veículo?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Descartar", role: .destructive, action: cancel)
            Button("Continuar editando", role: .cancel) {}
        }
        .onChange(of: isSessionExpired) { expired in
            if expired { onSessionExpired?() }
        }
    }

    private var isSessionExpired: Bool {
        if case .failure(.sessionExpired) = viewModel.state.submission { return true }
        return false
    }

    private func handleBack() {
        guard !viewModel.state.isSubmitting else { return }
        if hasMeaningfulInput {
            showDiscardConfirmation = true
        } else {
            cancel()
        }
    }

    private var hasMeaningfulInput: Bool {
        let input = viewModel.state.input
        return ![input.brand, input.model, input.version, input.plate, input.renavam, input.chassis]
            .allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
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
                Text("Salvar veículo")
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

    private func message(for reason: VehicleFormFailureReason) -> LocalizedStringResource {
        switch reason {
        case .offline: "Sem conexão com a internet. Verifique sua rede e tente novamente."
        case .timeout: "Não foi possível concluir agora. Tente novamente."
        case .sessionExpired: "Sua sessão expirou. Entre novamente."
        case .rpcUnavailable: "O cadastro de veículos está temporariamente indisponível. Tente novamente mais tarde."
        case .serviceUnavailable: "Não foi possível concluir agora. Tente novamente em instantes."
        case .vehicleUnavailable: "Não foi possível concluir esta ação agora. Tente novamente."
        case .contract: "Alguns dados não puderam ser aceitos. Revise o formulário."
        case .unknown: "Não foi possível salvar o veículo. Tente novamente."
        }
    }

    @ViewBuilder
    private func textField(
        _ field: VehicleField,
        label: LocalizedStringResource,
        keyboard: UIKeyboardType,
        autocapitalize: TextInputAutocapitalization = .sentences
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(PitGoTypography.caption)
                .foregroundStyle(tokens.textSecondary)

            TextField("", text: Binding(get: { text(for: field) }, set: { viewModel.update(field, text: $0) }))
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocapitalize)
                .focused($focusedField, equals: field)
                .disabled(!viewModel.state.isInputEnabled)
                .padding()
                .frame(minHeight: 44)
                .background(tokens.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(viewModel.state.fieldErrors[field] == nil ? tokens.outline : Color.red, lineWidth: 1)
                )
                .accessibilityLabel(accessibilityLabel(field: field, label: label))

            if let error = viewModel.state.fieldErrors[field] {
                Text(fieldErrorMessage(field, error))
                    .font(PitGoTypography.caption)
                    .foregroundStyle(.red)
            }
        }
        .id(field)
    }

    private func accessibilityLabel(field: VehicleField, label: LocalizedStringResource) -> String {
        let labelText = String(localized: label)
        guard let error = viewModel.state.fieldErrors[field] else { return labelText }
        return "\(labelText). \(fieldErrorMessage(field, error))"
    }

    private func text(for field: VehicleField) -> String {
        let input = viewModel.state.input
        switch field {
        case .brand: return input.brand
        case .model: return input.model
        case .version: return input.version
        case .manufactureYear: return input.manufactureYear
        case .modelYear: return input.modelYear
        case .plate: return input.plate
        case .renavam: return input.renavam
        case .chassis: return input.chassis
        case .color: return input.color
        case .fuelType: return input.fuelType
        case .transmission: return input.transmission
        case .engine: return input.engine
        case .mileage: return input.mileage
        }
    }

    /// Mensagens específicas por campo/erro (contracts/vehicle-form-ui.md "Mensagens por campo") —
    /// nunca um texto genérico para Marca/Modelo/Placa/Renavam/Chassi/anos/quilometragem.
    private func fieldErrorMessage(_ field: VehicleField, _ error: VehicleFieldError) -> LocalizedStringResource {
        switch (field, error) {
        case (.brand, .required): "Informe a marca do veículo."
        case (.model, .required): "Informe o modelo do veículo."
        case (.plate, .invalidFormat): "Informe uma placa válida."
        case (.renavam, .invalidFormat): "O Renavam deve conter 11 dígitos."
        case (.chassis, .invalidFormat): "Informe um chassi válido com 17 caracteres."
        case (.plate, .unavailable), (.renavam, .unavailable), (.chassis, .unavailable):
            "Este identificador já está cadastrado."
        case (.manufactureYear, _), (.modelYear, _):
            "Informe um ano entre 1900 e \(maximumYear)."
        case (.mileage, .outOfRange):
            "A quilometragem não pode ser negativa."
        case (.mileage, .invalidFormat):
            "Informe a quilometragem usando um número inteiro."
        default:
            genericFieldErrorMessage(error)
        }
    }

    private var maximumYear: Int {
        Calendar.current.component(.year, from: Date()) + 1
    }

    private func genericFieldErrorMessage(_ error: VehicleFieldError) -> LocalizedStringResource {
        switch error {
        case .required: "Este campo é obrigatório."
        case .invalidFormat: "Verifique o formato informado."
        case .outOfRange: "Valor fora do intervalo permitido."
        case .unavailable: "Este valor não está disponível."
        }
    }
}
