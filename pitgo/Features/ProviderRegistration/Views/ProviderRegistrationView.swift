//
//  ProviderRegistrationView.swift
//  pitgo
//
//  Destino único (formulário + resumo) para cadastro de empresa prestadora (ver
//  contracts/navigation-session.md de `009`). Uma única `List` com três seções — sem `TabView`, sem
//  wizard. Endereço não tem mais lat/lng manuais: "Verificar endereço" chama geocodificação + fix do
//  dispositivo e trava uma prova de 15 minutos antes do submit.
//

import SwiftUI

struct ProviderRegistrationView: View {
    @Environment(\.pitGoTokens) private var tokens
    @StateObject private var viewModel: ProviderRegistrationViewModel
    @FocusState private var focusedField: ProviderField?
    @State private var showDiscardConfirmation = false
    @State private var showDivergenceConfirmation = false

    /// Chamado ao concluir (sucesso/já cadastrado) ou ao descartar um formulário vazio/cancelado.
    let onFinished: () -> Void
    /// Disparado quando a RPC/Edge Function rejeita a chamada por sessão ausente/bloqueada.
    let onSessionExpired: () -> Void

    init(
        repository: ProviderRegistrationRepository,
        verificationRepository: ProviderAddressVerificationRepository,
        accountID: UUID,
        authEmail: String,
        providerKind: ProviderKind,
        onFinished: @escaping () -> Void,
        onSessionExpired: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ProviderRegistrationViewModel(
            repository: repository,
            verificationRepository: verificationRepository,
            accountID: accountID,
            authEmail: authEmail,
            providerKind: providerKind
        ))
        self.onFinished = onFinished
        self.onSessionExpired = onSessionExpired
    }

    var body: some View {
        content
            .navigationTitle("Cadastro da empresa")
            .navigationBarTitleDisplayMode(.inline)
            .task { viewModel.bootstrap() }
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
        case let .startupFailure(reason):
            startupFailureView(reason)
        case let .editing(editingContent):
            editingView(editingContent)
        case let .alreadyRegistered(summary):
            summaryView(summary, justCreated: false)
        case let .success(summary):
            summaryView(summary, justCreated: true)
        case .sessionExpired:
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).background(tokens.background)
        }
    }

    private func startupFailureView(_ reason: ProviderStartupFailureReason) -> some View {
        VStack(spacing: 16) {
            Text("Não foi possível carregar os dados da empresa.")
                .font(PitGoTypography.body)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.updatesFrequently)
            Button("Tentar novamente") { viewModel.retryStartup() }
                .frame(minHeight: 44)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(tokens.background)
    }

    // MARK: - Editing

    private func editingView(_ content: EditingContent) -> some View {
        List {
            Section("Dados da empresa") {
                companyFields(content)
            }
            Section("Modalidade") {
                Text(content.draft.providerKind.title)
                    .font(PitGoTypography.body)
                Text("Valores e duração dos atendimentos são definidos pela PitGo.")
                    .font(PitGoTypography.caption)
                    .foregroundStyle(tokens.textSecondary)
            }
            Section("Endereço") {
                addressFields(content)
            }
            if content.draft.providerKind == .guincho {
                Section("Veículo de atendimento") { vehicleFields(content) }
            }
            if content.showsOffersSection {
                Section("Serviços oferecidos") {
                    offersSection(content)
                }
            } else if content.draft.providerKind != .store {
                Section("Serviço") {
                    implicitServiceSection(content)
                }
            }
            if case let .failure(reason) = content.submission {
                Section {
                    Text(message(for: reason))
                        .font(PitGoTypography.caption)
                        .foregroundStyle(.red)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            Section {
                submitButton(content)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: handleBack) {
                    Image(systemName: "chevron.left")
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Voltar")
                .disabled(content.isSubmitting)
            }
        }
        .confirmationDialog(
            "Descartar cadastro?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Descartar", role: .destructive, action: onFinished)
            Button("Continuar editando", role: .cancel) {}
        }
        .confirmationDialog(
            divergenceMessage(content),
            isPresented: $showDivergenceConfirmation,
            titleVisibility: .visible
        ) {
            Button("Confirmar endereço mesmo assim") { viewModel.confirmDivergence() }
            Button("Corrigir endereço", role: .cancel) {}
        }
        .onChange(of: content.addressVerification) { newValue in
            if case .diverged = newValue { showDivergenceConfirmation = true }
        }
        .onChange(of: content.focusRequest?.requestID) { _ in
            if let request = content.focusRequest {
                focusedField = request.field
            }
        }
    }

    private func handleBack() {
        guard case let .editing(content) = viewModel.state, !content.isSubmitting else { return }
        if content.draft.hasMeaningfulContent {
            showDiscardConfirmation = true
        } else {
            onFinished()
        }
    }

    @ViewBuilder
    private func companyFields(_ content: EditingContent) -> some View {
        labeledField("Nome da empresa", error: content.fieldErrors[.company(.name)]) {
            TextField("", text: Binding(get: { content.draft.company.name }, set: { viewModel.updateCompanyName($0) }))
                .focused($focusedField, equals: .company(.name))
                .disabled(!content.isInputEnabled)
        }
        labeledField("Descrição (opcional)", error: nil) {
            TextField("", text: Binding(get: { content.draft.company.description }, set: { viewModel.updateCompanyDescription($0) }))
                .focused($focusedField, equals: .company(.description))
                .disabled(!content.isInputEnabled)
        }
        labeledField("E-mail comercial", error: content.fieldErrors[.company(.email)]) {
            TextField("", text: Binding(get: { content.draft.company.email }, set: { viewModel.updateCompanyEmail($0) }))
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focusedField, equals: .company(.email))
                .disabled(!content.isInputEnabled)
        }
        labeledField("Telefone", error: content.fieldErrors[.company(.phone)]) {
            TextField(
                "",
                text: Binding(
                    get: { BrazilianTextFormatting.formatPhone(content.draft.company.phone) },
                    set: { viewModel.updateCompanyPhone($0) }
                )
            )
            .keyboardType(.numberPad)
            .focused($focusedField, equals: .company(.phone))
            .disabled(!content.isInputEnabled)
        }
        labeledField("CNPJ", error: content.fieldErrors[.company(.cnpj)]) {
            TextField(
                "",
                text: Binding(
                    get: { BrazilianTextFormatting.formatCNPJ(content.draft.company.cnpj) },
                    set: { viewModel.updateCompanyCNPJ($0) }
                )
            )
            .textInputAutocapitalization(.characters)
            .focused($focusedField, equals: .company(.cnpj))
            .disabled(!content.isInputEnabled)
        }
    }

    @ViewBuilder
    private func locationModeField(_ content: EditingContent) -> some View {
        Picker(
            "Modalidade",
            selection: Binding(get: { content.draft.locationMode }, set: { viewModel.updateLocationMode($0) })
        ) {
            Text("Fixo (endereço)").tag(ProviderLocationMode.fixed)
            Text("Móvel (Guincho)").tag(ProviderLocationMode.mobile)
            Text("PitTec (sob demanda)").tag(ProviderLocationMode.pittec)
        }
        .pickerStyle(.segmented)
        .focused($focusedField, equals: .locationMode)
        .disabled(!content.isInputEnabled)

        Text(locationModeDescription(content.draft.locationMode))
            .font(PitGoTypography.caption)
            .foregroundStyle(tokens.textSecondary)
    }

    @ViewBuilder
    private func vehicleFields(_ content: EditingContent) -> some View {
        Picker("Tipo/porte do guincho", selection: Binding(get: { content.draft.guinchoSizeID }, set: { viewModel.selectGuinchoSize($0) })) {
            Text("Selecione o porte").tag(UUID?.none)
            ForEach(viewModel.guinchoSizes) { Text($0.name).tag(Optional($0.id)) }
        }
        .task { await viewModel.loadTransportCatalog() }
        if content.fieldErrors[.vehicle(.size)] != nil { Text("Selecione o tipo/porte do guincho.").foregroundStyle(.red) }
        if viewModel.transportCatalogFailed {
            Button("Tentar carregar portes") { Task { await viewModel.loadTransportCatalog() } }
        }
        labeledField("Placa", error: content.fieldErrors[.vehicle(.plate)]) {
            TextField("ABC1D23", text: Binding(get: { content.draft.vehiclePlate }, set: { viewModel.updateVehiclePlate($0) }))
                .textInputAutocapitalization(.characters).autocorrectionDisabled().focused($focusedField, equals: .vehicle(.plate))
        }
        labeledField("Marca", error: content.fieldErrors[.vehicle(.make)]) {
            VehicleMakePicker(selection: Binding(get: { content.draft.vehicleMake }, set: { viewModel.updateVehicleMake($0) }))
                .focused($focusedField, equals: .vehicle(.make))
        }
        labeledField("Modelo", error: content.fieldErrors[.vehicle(.model)]) {
            TextField("Modelo", text: Binding(get: { content.draft.vehicleModel }, set: { viewModel.updateVehicleModel($0) }))
                .focused($focusedField, equals: .vehicle(.model))
        }
        labeledField("Cor", error: content.fieldErrors[.vehicle(.color)]) {
            TextField("Cor", text: Binding(get: { content.draft.vehicleColor }, set: { viewModel.updateVehicleColor($0) }))
                .focused($focusedField, equals: .vehicle(.color))
        }
    }

    private func locationModeDescription(_ mode: ProviderLocationMode) -> String {
        switch mode {
        case .fixed:
            "Aparece no mapa pelo endereço cadastrado. Escolha ao menos um serviço abaixo."
        case .mobile:
            "Publica localização em tempo real durante um atendimento aceito. Oferece automaticamente o serviço \"Guincho\" — defina apenas o preço e a duração."
        case .pittec:
            "Atendimento técnico sob demanda: você se desloca até o local solicitado. Oferece automaticamente o serviço \"PitTec\", com valor definido pela plataforma — nenhum preço ou serviço para escolher."
        }
    }

    @ViewBuilder
    private func implicitServiceSection(_ content: EditingContent) -> some View {
        switch content.implicitService {
        case .loading, .none:
            ProgressView("Localizando serviço…")
        case .empty, .failure:
            VStack(alignment: .leading, spacing: 8) {
                Text("Não foi possível localizar o serviço desta modalidade no catálogo.")
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
                Button("Tentar novamente") { viewModel.updateLocationMode(content.draft.locationMode) }
            }
        case let .content(service):
            VStack(alignment: .leading, spacing: 8) {
                Text(service.name)
                    .font(PitGoTypography.body)
                    .bold()
                Text("Tarifa e duração configuradas pela PitGo.")
                    .font(PitGoTypography.caption)
                    .foregroundStyle(tokens.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func addressFields(_ content: EditingContent) -> some View {
        labeledField("CEP", error: content.fieldErrors[.address(.postalCode)]) {
            HStack(spacing: 8) {
                TextField(
                    "",
                    text: Binding(
                        get: { BrazilianTextFormatting.formatCEP(content.draft.address.postalCode) },
                        set: { viewModel.updatePostalCode($0) }
                    )
                )
                .keyboardType(.numberPad)
                .submitLabel(.search)
                .onSubmit { viewModel.lookupPostalCode() }
                .focused($focusedField, equals: .address(.postalCode))
                .disabled(!content.isInputEnabled)

                Button(action: { viewModel.lookupPostalCode() }) {
                    if content.postalCodeLookup.isLoading {
                        ProgressView()
                    } else {
                        Text("Buscar CEP")
                    }
                }
                .frame(minHeight: 44)
                .disabled(
                    !content.isInputEnabled
                        || content.postalCodeLookup.isLoading
                        || content.draft.address.postalCode.count != 8
                )
                .accessibilityLabel("Buscar CEP")
            }
        }
        if let feedback = postalCodeLookupFeedback(content) {
            Text(feedback.text)
                .font(PitGoTypography.caption)
                .foregroundStyle(feedback.isError ? .red : tokens.textSecondary)
                .accessibilityAddTraits(.updatesFrequently)
        }
        labeledField("Rua", error: content.fieldErrors[.address(.street)]) {
            TextField("", text: Binding(get: { content.draft.address.street }, set: { viewModel.updateStreet($0) }))
                .focused($focusedField, equals: .address(.street))
                .disabled(!content.isInputEnabled || content.isAddressLookupLoading)
        }
        labeledField("Número", error: content.fieldErrors[.address(.number)]) {
            TextField("", text: Binding(get: { content.draft.address.number }, set: { viewModel.updateNumber($0) }))
                .focused($focusedField, equals: .address(.number))
                .disabled(!content.isInputEnabled)
        }
        labeledField("Complemento (opcional)", error: nil) {
            TextField("", text: Binding(get: { content.draft.address.complement }, set: { viewModel.updateComplement($0) }))
                .focused($focusedField, equals: .address(.complement))
                .disabled(!content.isInputEnabled || content.isAddressLookupLoading)
        }
        labeledField("Bairro", error: content.fieldErrors[.address(.neighborhood)]) {
            TextField("", text: Binding(get: { content.draft.address.neighborhood }, set: { viewModel.updateNeighborhood($0) }))
                .focused($focusedField, equals: .address(.neighborhood))
                .disabled(!content.isInputEnabled || content.isAddressLookupLoading)
        }
        labeledField("Cidade", error: content.fieldErrors[.address(.city)]) {
            TextField("", text: Binding(get: { content.draft.address.city }, set: { viewModel.updateCity($0) }))
                .focused($focusedField, equals: .address(.city))
                .disabled(!content.isInputEnabled || content.isAddressLookupLoading)
        }
        labeledField("Estado", error: content.fieldErrors[.address(.state)]) {
            Picker("", selection: Binding(get: { content.draft.address.state }, set: { viewModel.updateState($0) })) {
                Text("Selecione").tag(BrazilianState?.none)
                ForEach(BrazilianState.allCases) { state in
                    Text(state.rawValue).tag(BrazilianState?.some(state))
                }
            }
            .focused($focusedField, equals: .address(.state))
            .disabled(!content.isInputEnabled || content.isAddressLookupLoading)
        }
        Text("País: Brasil")
            .font(PitGoTypography.caption)
            .foregroundStyle(tokens.textSecondary)

        Text("O endereço informado será validado automaticamente ao concluir o cadastro.")
            .font(PitGoTypography.caption)
            .foregroundStyle(tokens.textSecondary)
    }

    @ViewBuilder
    private func verificationStatusView(_ content: EditingContent) -> some View {
        switch content.addressVerification {
        case .unverified:
            EmptyView()
        case .geocoding:
            Label("Verificando endereço…", systemImage: "mappin.and.ellipse")
                .font(PitGoTypography.caption)
                .foregroundStyle(tokens.textSecondary)
        case .matched:
            Label("Endereço verificado", systemImage: "checkmark.circle.fill")
                .font(PitGoTypography.caption)
                .foregroundStyle(.green)
                .accessibilityAddTraits(.updatesFrequently)
        case let .confirmedDivergence(_, distance, _):
            Label("Endereço confirmado (\(Int(distance)) m do dispositivo)", systemImage: "checkmark.circle.fill")
                .font(PitGoTypography.caption)
                .foregroundStyle(.orange)
                .accessibilityAddTraits(.updatesFrequently)
        case .diverged:
            Label("Divergência encontrada — confirme ou corrija o endereço.", systemImage: "exclamationmark.triangle.fill")
                .font(PitGoTypography.caption)
                .foregroundStyle(.orange)
                .accessibilityAddTraits(.updatesFrequently)
        case let .failure(reason):
            Label(geocodingFailureMessage(reason), systemImage: "xmark.octagon.fill")
                .font(PitGoTypography.caption)
                .foregroundStyle(.red)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    /// Texto de apoio abaixo do CEP — o `.notFound` já vira `ProviderFieldError.notFound` no próprio
    /// campo, então não é repetido aqui.
    private func postalCodeLookupFeedback(_ content: EditingContent) -> (text: String, isError: Bool)? {
        switch content.postalCodeLookup {
        case .idle, .notFound:
            nil
        case .loading:
            ("Buscando endereço…", false)
        case let .found(_, _, appliedFields):
            appliedFields.count >= CepAddressField.allCases.count
                ? nil
                : ("Alguns dados não foram retornados pelo CEP; complete manualmente.", false)
        case let .failure(_, _, reason):
            (postalCodeLookupFailureMessage(reason), true)
        }
    }

    private func postalCodeLookupFailureMessage(_ reason: PostalCodeLookupFailure) -> String {
        switch reason {
        case .offline: "Sem conexão para consultar o CEP. Verifique sua rede e tente novamente."
        case .timeout: "A consulta demorou demais. Tente novamente."
        case .serviceUnavailable: "Serviço de CEP indisponível no momento. Tente novamente."
        case .unexpectedResponse: "Não foi possível consultar o CEP agora. Tente novamente."
        }
    }

    private func divergenceMessage(_ content: EditingContent) -> String {
        if case let .diverged(_, distance, _) = content.addressVerification {
            return "Sua localização atual está a \(Int(distance)) m do endereço informado. Confirmar mesmo assim?"
        }
        return "Confirmar divergência de endereço?"
    }

    private func geocodingFailureMessage(_ reason: GeocodingFailureReason) -> String {
        switch reason {
        case .noMatch: "Endereço não encontrado. Revise os dados."
        case .ambiguousOrPartial: "Endereço incompleto ou ambíguo. Revise os dados."
        case .wrongRegion: "Endereço fora do Brasil."
        case .fixTooOld, .fixTooImprecise: "Localização do dispositivo imprecisa. Tente novamente ao ar livre."
        case .invalidAddress: "Endereço inválido. Revise os dados."
        case .rateLimited: "Muitas tentativas. Aguarde um momento."
        case .upstreamUnavailable: "Serviço de verificação indisponível no momento."
        case .sessionBlocked: "Sua sessão não permite esta ação."
        case .permissionDenied: "Permita o acesso à localização nas Configurações."
        case .serviceDisabled: "Ative os Serviços de Localização nas Configurações do sistema."
        case .timeout: "Não foi possível obter sua localização a tempo. Tente novamente."
        case .offline: "Sem conexão com a internet."
        case .unknown: "Não foi possível verificar o endereço. Tente novamente."
        }
    }

    @ViewBuilder
    private func offersSection(_ content: EditingContent) -> some View {
        switch content.categories {
        case .loading:
            ProgressView("Carregando categorias…")
        case .empty:
            Text("Nenhuma categoria disponível no momento.")
                .foregroundStyle(tokens.textSecondary)
        case .failure:
            VStack(alignment: .leading, spacing: 8) {
                Text("Não foi possível carregar as categorias.")
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
                Button("Tentar novamente") { viewModel.retryCategories() }
            }
        case let .content(categories):
            primaryCategoryField(categories, content: content)

            if content.fieldErrors[.offersList] != nil {
                Text("Adicione ao menos uma oferta.")
                    .font(PitGoTypography.caption)
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if content.draft.primaryCategoryID != nil {
                ForEach(content.draft.offers) { offer in
                    offerRow(offer, content: content)
                }
                Button(action: { viewModel.addOffer() }) {
                    Label("Adicionar serviço", systemImage: "plus.circle")
                }
                .frame(minHeight: 44)
                .disabled(!content.isInputEnabled)
            }
        }
    }

    /// `026` FR-001: categoria principal única do rascunho Fixo — trocar uma categoria com ofertas
    /// já preenchidas pede confirmação (`content.pendingPrimaryCategoryChange`) antes de descartar a
    /// seleção atual.
    @ViewBuilder
    private func primaryCategoryField(_ categories: [ServiceCategory], content: EditingContent) -> some View {
        labeledField("Categoria principal", error: content.fieldErrors[.primaryCategory]) {
            Picker(
                "",
                selection: Binding(
                    get: { content.draft.primaryCategoryID },
                    set: { viewModel.selectPrimaryCategory($0) }
                )
            ) {
                Text("Selecione").tag(UUID?.none)
                ForEach(categories) { category in
                    Text(category.name).tag(UUID?.some(category.id))
                }
            }
            .focused($focusedField, equals: .primaryCategory)
            .disabled(!content.isInputEnabled)
        }
        .confirmationDialog(
            "Trocar a categoria principal descarta os serviços já selecionados. Continuar?",
            isPresented: Binding(
                get: { content.pendingPrimaryCategoryChange != nil },
                set: { if !$0 { viewModel.cancelPrimaryCategoryChange() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Trocar categoria", role: .destructive) { viewModel.confirmPrimaryCategoryChange() }
            Button("Cancelar", role: .cancel) { viewModel.cancelPrimaryCategoryChange() }
        }
    }

    @ViewBuilder
    private func offerRow(_ offer: OfferDraft, content: EditingContent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let categoryID = content.draft.primaryCategoryID {
                serviceField(offer, categoryID: categoryID, content: content)
            }

            Toggle(
                "Serviço gratuito",
                isOn: Binding(get: { offer.isFree }, set: { viewModel.updateOfferFree(offer.id, isFree: $0) })
            )
            .disabled(!content.isInputEnabled)

            if !offer.isFree {
                labeledField("Preço (R$)", error: content.fieldErrors[.offer(localID: offer.id, field: .price)]) {
                    TextField("", text: Binding(get: { offer.priceInput }, set: { viewModel.updateOfferPrice(offer.id, value: $0) }))
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .offer(localID: offer.id, field: .price))
                        .disabled(!content.isInputEnabled)
                }
            }

            labeledField("Duração (minutos)", error: content.fieldErrors[.offer(localID: offer.id, field: .duration)]) {
                TextField("", text: Binding(get: { offer.durationInput }, set: { viewModel.updateOfferDuration(offer.id, value: $0) }))
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .offer(localID: offer.id, field: .duration))
                    .disabled(!content.isInputEnabled)
            }

            labeledField("Descrição comercial (opcional)", error: nil) {
                TextField("", text: Binding(get: { offer.description }, set: { viewModel.updateOfferDescription(offer.id, value: $0) }))
                    .focused($focusedField, equals: .offer(localID: offer.id, field: .description))
                    .disabled(!content.isInputEnabled)
            }

            if content.draft.offers.count > 1 {
                Button(role: .destructive, action: { viewModel.removeOffer(offer.id) }) {
                    Label("Remover serviço", systemImage: "trash")
                }
                .frame(minHeight: 44)
                .disabled(!content.isInputEnabled)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func serviceField(_ offer: OfferDraft, categoryID: UUID, content: EditingContent) -> some View {
        let loadState = content.servicesByCategory[categoryID] ?? .loading
        switch loadState {
        case .loading:
            ProgressView("Carregando serviços…")
        case .empty:
            Text("Nenhum serviço nesta categoria.")
                .foregroundStyle(tokens.textSecondary)
        case .failure:
            VStack(alignment: .leading, spacing: 8) {
                Text("Não foi possível carregar os serviços.")
                    .foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
                Button("Tentar novamente") { viewModel.retryServices(for: categoryID) }
            }
        case let .content(services):
            let usedElsewhere = viewModel.usedServiceIDs(excluding: offer.id)
            labeledField("Serviço", error: content.fieldErrors[.offer(localID: offer.id, field: .service)]) {
                Picker(
                    "",
                    selection: Binding(
                        get: { offer.serviceID },
                        set: { viewModel.updateOfferService(offer.id, serviceID: $0) }
                    )
                ) {
                    Text("Selecione").tag(UUID?.none)
                    ForEach(services) { service in
                        Text(usedElsewhere.contains(service.id) ? "\(service.name) (já usado)" : service.name)
                            .tag(UUID?.some(service.id))
                    }
                }
                .focused($focusedField, equals: .offer(localID: offer.id, field: .service))
                .disabled(!content.isInputEnabled)
            }
        }
    }

    private func submitButton(_ content: EditingContent) -> some View {
        VStack(spacing: 8) {
            Button(action: { viewModel.submit() }) {
                ZStack {
                    if content.isSubmitting {
                        ProgressView().tint(.white)
                    }
                    Text("Cadastrar empresa")
                        .opacity(content.isSubmitting ? 0 : 1)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .foregroundStyle(.white)
            .background(content.canSubmit ? tokens.accent : tokens.textSecondary)
            .clipShape(Capsule())
            .frame(minHeight: 56)
            .disabled(!content.canSubmit)

            if let reason = submitBlockedReason(content) {
                Text(reason)
                    .font(PitGoTypography.caption)
                    .foregroundStyle(tokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }

    /// `canSubmit` não exige mais endereço verificado (ver nota em `EditingContent.canSubmit`) — a
    /// verificação roda sozinha ao tocar em "Cadastrar empresa" quando ainda não foi feita. O único
    /// motivo restante para o botão ficar cinza é a modalidade Móvel/PitTec ainda resolvendo o
    /// serviço implícito do catálogo.
    private func submitBlockedReason(_ content: EditingContent) -> String? {
        guard !content.canSubmit, !content.isSubmitting else { return nil }
        if content.draft.locationMode != .fixed {
            return "Aguarde o serviço da modalidade carregar."
        }
        return nil
    }

    private func message(for reason: ProviderFailureReason) -> LocalizedStringResource {
        switch reason {
        case .timeout: "Não foi possível concluir agora. Tente novamente."
        case .offline: "Sem conexão com a internet. Verifique sua rede e tente novamente."
        case .sessionExpired: "Sua sessão expirou. Entre novamente."
        case .serviceUnavailable: "Não foi possível concluir agora. Tente novamente em instantes."
        case .duplicateService: "Um dos serviços já foi adicionado. Revise as ofertas."
        case .catalogChanged: "Um dos serviços não está mais disponível. Selecione novamente."
        case .geocodeExpired: "A verificação de endereço expirou. Verifique novamente."
        case .divergenceConfirmationRequired: "Confirme a divergência de endereço antes de continuar."
        case .invalidInput: "Alguns dados não puderam ser aceitos. Revise o formulário."
        case .contract: "Alguns dados não puderam ser aceitos. Revise o formulário."
        case .unknown: "Não foi possível concluir o cadastro. Tente novamente."
        }
    }

    // MARK: - Summary (`.alreadyRegistered` / `.success`)

    private func summaryView(_ summary: ProviderSummary, justCreated: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(justCreated ? "Cadastro concluído!" : "Sua empresa já está cadastrada.")
                    .font(PitGoTypography.sectionTitle)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.provider.name).font(PitGoTypography.body).bold()
                    if let description = summary.provider.description, !description.isEmpty {
                        Text(description).font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
                    }
                    Text(summary.provider.email).font(PitGoTypography.caption)
                    Text(BrazilianTextFormatting.formatPhone(summary.provider.phone)).font(PitGoTypography.caption)
                    Text(maskedCNPJ(summary.provider.cnpj)).font(PitGoTypography.caption)
                    Text("Modalidade: \(summary.provider.providerKind?.title ?? (summary.provider.locationMode == .mobile ? "Guincho" : "Empresa"))")
                        .font(PitGoTypography.caption)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Endereço").font(PitGoTypography.categoryTitle).accessibilityAddTraits(.isHeader)
                    Text("\(summary.address.street), \(summary.address.number)")
                    if let complement = summary.address.complement, !complement.isEmpty {
                        Text(complement)
                    }
                    Text("\(summary.address.neighborhood) · \(summary.address.city)/\(summary.address.state)")
                    Text("CEP \(BrazilianTextFormatting.formatCEP(summary.address.zipCode))")
                }
                .font(PitGoTypography.caption)

                if !summary.offers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Serviços").font(PitGoTypography.categoryTitle).accessibilityAddTraits(.isHeader)
                    ForEach(Array(summary.offers.enumerated()), id: \.offset) { _, offer in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(offer.serviceName) · \(offer.categoryName)").font(PitGoTypography.body)
                            if summary.provider.providerKind == .pittec || summary.provider.providerKind == .guincho {
                                Text("Tarifa e duração definidas pela PitGo").font(PitGoTypography.caption)
                            } else {
                                Text(offer.isFree ? "Gratuito" : formattedPrice(offer.price)).font(PitGoTypography.caption)
                                Text("\(offer.durationMinutes) min").font(PitGoTypography.caption)
                            }
                            if let description = offer.description, !description.isEmpty {
                                Text(description).font(PitGoTypography.caption).foregroundStyle(tokens.textSecondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                }

                Button(action: onFinished) {
                    Text("Continuar")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .foregroundStyle(.white)
                .background(tokens.accent)
                .clipShape(Capsule())
                .frame(minHeight: 56)
            }
            .padding(16)
        }
        .background(tokens.background)
        .navigationBarBackButtonHidden(true)
    }

    private func maskedCNPJ(_ value: String) -> String {
        guard value.count == 14 else { return "••••••••••••••" }
        let prefix = value.prefix(2)
        let suffix = value.suffix(2)
        return "\(prefix)••••••••••\(suffix)"
    }

    private func formattedPrice(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: value as NSDecimalNumber) ?? "R$ \(value)"
    }

    // MARK: - Field helpers

    @ViewBuilder
    private func labeledField<Content: View>(
        _ label: LocalizedStringResource,
        error: ProviderFieldError?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(PitGoTypography.caption)
                .foregroundStyle(tokens.textSecondary)
            content()
            if let error {
                Text(fieldErrorMessage(error))
                    .font(PitGoTypography.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func fieldErrorMessage(_ error: ProviderFieldError) -> LocalizedStringResource {
        switch error {
        case .required: "Este campo é obrigatório."
        case .invalidFormat: "Verifique o formato informado."
        case .outOfRange: "Valor fora do intervalo permitido."
        case .unavailable: "Este valor não está disponível."
        case .duplicate: "Este dado já está cadastrado."
        case .notFound: "CEP não encontrado. Verifique o número informado."
        }
    }
}
