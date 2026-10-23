//
//  ProviderRegistrationViewModel.swift
//  pitgo
//
//  `ProviderRegistrationView` só existe dentro do subtree autenticado de `PitGoRootView`
//  (`.authenticatedProviderOnboarding`) — qualquer transição de `SessionStore.state` para fora dali
//  descarta esta View/ViewModel (mesma garantia estrutural de `VehicleFormViewModel` em `006`).
//

import Combine
import Foundation

@MainActor
final class ProviderRegistrationViewModel: ObservableObject {
    @Published private(set) var state: ProviderRegistrationUiState = .loading

    private let repository: ProviderRegistrationRepository
    private let verificationRepository: ProviderAddressVerificationRepository
    private let postalCodeLookupRepository: ViaCepAddressLookupRepository
    private let accountID: UUID
    private let authEmail: String
    private let providerKind: ProviderKind
    private var focusRequestID = 0
    private var submissionTask: Task<Void, Never>?
    private var verificationTask: Task<Void, Never>?
    private var postalCodeLookupTask: Task<Void, Never>?
    private var postalCodeAttemptID: UInt64 = 0

    init(
        repository: ProviderRegistrationRepository,
        verificationRepository: ProviderAddressVerificationRepository,
        accountID: UUID,
        authEmail: String,
        providerKind: ProviderKind,
        postalCodeLookupRepository: ViaCepAddressLookupRepository = ViaCepAddressLookupRepository()
    ) {
        self.repository = repository
        self.verificationRepository = verificationRepository
        self.accountID = accountID
        self.authEmail = authEmail
        self.providerKind = providerKind
        self.postalCodeLookupRepository = postalCodeLookupRepository
    }

    // MARK: - Bootstrap

    func bootstrap() {
        state = .loading
        Task { [weak self] in
            guard let self else { return }
            switch await repository.fetchOwnAggregate(accountID: accountID) {
            case let .complete(summary):
                state = .alreadyRegistered(summary)
            case .none:
                var draft = ProviderRegistrationDraft(company: CompanyDraft(email: authEmail))
                draft.providerKind = providerKind
                draft.locationMode = providerKind.locationMode
                if providerKind == .store {
                    draft.offers = []
                } else if providerKind == .pittec || providerKind == .guincho {
                    var offer = OfferDraft()
                    offer.isFree = true
                    offer.priceInput = "0"
                    offer.durationInput = "60"
                    draft.offers = [offer]
                }
                state = .editing(EditingContent(draft: draft))
                await loadCategories()
                if providerKind != .store { resolveImplicitService(for: providerKind.locationMode) }
            case .inconsistent:
                state = .startupFailure(reason: .unknown)
            case .failure:
                state = .startupFailure(reason: .service)
            }
        }
    }

    func retryStartup() {
        bootstrap()
    }

    private func loadCategories() async {
        let result = await repository.fetchCategories()
        updateEditing { $0.categories = result }
    }

    func retryCategories() {
        updateEditing { $0.categories = .loading }
        Task { [weak self] in
            await self?.loadCategories()
        }
    }

    func retryServices(for categoryID: UUID) {
        updateEditing { $0.servicesByCategory[categoryID] = .loading }
        Task { [weak self] in
            guard let self else { return }
            let result = await repository.fetchServices(categoryID: categoryID)
            updateEditing { $0.servicesByCategory[categoryID] = result }
        }
    }

    // MARK: - Company fields

    func updateCompanyName(_ value: String) {
        updateEditing {
            $0.draft.company.name = value
            $0.fieldErrors[.company(.name)] = nil
        }
    }

    func updateCompanyDescription(_ value: String) {
        updateEditing { $0.draft.company.description = value }
    }

    func updateCompanyEmail(_ value: String) {
        updateEditing {
            $0.draft.company.email = value
            $0.fieldErrors[.company(.email)] = nil
        }
    }

    func updateCompanyPhone(_ rawInput: String) {
        updateEditing {
            $0.draft.company.phone = String(BrazilianInputValidation.digitsOnly(rawInput).prefix(11))
            $0.fieldErrors[.company(.phone)] = nil
        }
    }

    func updateCompanyCNPJ(_ rawInput: String) {
        updateEditing {
            $0.draft.company.cnpj = String(BrazilianInputValidation.normalizeCNPJ(rawInput).prefix(14))
            $0.fieldErrors[.company(.cnpj)] = nil
        }
    }

    func updateVehiclePlate(_ value: String) { updateEditing { $0.draft.vehiclePlate = String(value.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(7)); $0.fieldErrors[.vehicle(.plate)] = nil } }
    func updateVehicleMake(_ value: String) { updateEditing { $0.draft.vehicleMake = value; $0.fieldErrors[.vehicle(.make)] = nil } }
    func updateVehicleModel(_ value: String) { updateEditing { $0.draft.vehicleModel = value; $0.fieldErrors[.vehicle(.model)] = nil } }
    func updateVehicleColor(_ value: String) { updateEditing { $0.draft.vehicleColor = value; $0.fieldErrors[.vehicle(.color)] = nil } }

    /// Móvel/PitTec (`016`) não escolhem serviço: a modalidade tem exatamente um serviço implícito
    /// no catálogo (Guincho/PitTec), resolvido aqui e anexado como a única oferta do rascunho. Cada
    /// troca de modalidade substitui `offers` do zero — nunca mescla com o que valia para outra.
    func updateLocationMode(_ mode: ProviderLocationMode) {
        updateEditing { content in
            content.draft.locationMode = mode
            content.fieldErrors[.locationMode] = nil
            for field in OfferField.allCases {
                for offer in content.draft.offers {
                    content.fieldErrors[.offer(localID: offer.id, field: field)] = nil
                }
            }
            content.fieldErrors[.offersList] = nil

            content.fieldErrors[.primaryCategory] = nil
            content.pendingPrimaryCategoryChange = nil
            content.draft.primaryCategoryID = nil

            switch mode {
            case .fixed:
                content.implicitService = nil
                content.draft.offers = [OfferDraft()]
            case .mobile:
                content.implicitService = .loading
                var offer = OfferDraft()
                offer.priceInput = content.draft.offers.first?.priceInput ?? ""
                offer.durationInput = content.draft.offers.first?.durationInput ?? ""
                offer.isFree = content.draft.offers.first?.isFree ?? false
                content.draft.offers = [offer]
            case .pittec:
                content.implicitService = .loading
                var offer = OfferDraft()
                offer.isFree = true
                offer.priceInput = "0"
                // Duração interna, sem tela nem significado de cobrança (data-model.md `016`).
                offer.durationInput = "30"
                content.draft.offers = [offer]
            }
        }
        guard mode != .fixed else { return }
        resolveImplicitService(for: mode)
    }

    private func resolveImplicitService(for mode: ProviderLocationMode) {
        let dispatchKind: ServiceDispatchKind = mode == .mobile ? .mobileSequential : .pittecAutoSequential
        Task { [weak self] in
            guard let self else { return }
            let result = await repository.fetchImplicitService(dispatchKind: dispatchKind)
            // A pessoa pode ter trocado de modalidade de novo enquanto a busca estava em voo.
            guard case let .editing(content) = state, content.draft.locationMode == mode else { return }
            switch result {
            case let .found(service):
                updateEditing { editing in
                    editing.implicitService = .content(service)
                    guard var offer = editing.draft.offers.first else { return }
                    offer.serviceID = service.id
                    editing.draft.offers = [offer]
                }
            case .missing, .duplicated:
                updateEditing { $0.implicitService = .failure(reason: "catalog") }
            }
        }
    }

    // MARK: - Address fields — qualquer edição invalida a verificação vigente (contracts/
    // geocoding-edge-function.md "iOS state contract").

    func updateStreet(_ value: String) {
        updateEditing {
            $0.draft.address.street = value
            $0.fieldErrors[.address(.street)] = nil
            $0.addressVerification = .unverified
        }
    }

    func updateNumber(_ value: String) {
        updateEditing {
            $0.draft.address.number = value
            $0.fieldErrors[.address(.number)] = nil
            $0.addressVerification = .unverified
        }
    }

    func updateNeighborhood(_ value: String) {
        updateEditing {
            $0.draft.address.neighborhood = value
            $0.fieldErrors[.address(.neighborhood)] = nil
            $0.addressVerification = .unverified
        }
    }

    func updatePostalCode(_ rawInput: String) {
        let newCode = String(BrazilianInputValidation.digitsOnly(rawInput).prefix(8))
        updateEditing { content in
            let previousCode = content.draft.address.postalCode
            content.draft.address.postalCode = newCode
            content.fieldErrors[.address(.postalCode)] = nil
            content.addressVerification = .unverified

            guard newCode != previousCode else { return }

            // CEP alterado após uma consulta: invalida somente os campos preenchidos por ela,
            // preservando Número e qualquer campo nunca tocado pelo ViaCEP (data-model.md
            // "Transições").
            if let provenance = content.cepAutofillProvenance, provenance.postalCode == previousCode {
                for field in provenance.fields {
                    switch field {
                    case .street: content.draft.address.street = ""
                    case .complement: content.draft.address.complement = ""
                    case .neighborhood: content.draft.address.neighborhood = ""
                    case .city: content.draft.address.city = ""
                    case .state: content.draft.address.state = nil
                    }
                }
            }
            content.cepAutofillProvenance = nil
            content.postalCodeLookup = .idle
        }
        postalCodeLookupTask?.cancel()
    }

    // MARK: - Busca de endereço por CEP (011)

    /// Também serve como "Tentar novamente" após `.failure` — mesma ação, novo `attemptID`
    /// (data-model.md "Transições").
    func lookupPostalCode() {
        guard case let .editing(content) = state, content.isInputEnabled, !content.isSubmitting else { return }
        let postalCode = content.draft.address.postalCode
        guard postalCode.count == 8 else { return }
        guard !content.postalCodeLookup.isLoading else { return }

        postalCodeAttemptID += 1
        let attemptID = postalCodeAttemptID
        updateEditing {
            $0.postalCodeLookup = .loading(attemptID: attemptID, postalCode: postalCode)
            $0.fieldErrors[.address(.postalCode)] = nil
        }

        postalCodeLookupTask?.cancel()
        postalCodeLookupTask = Task { [weak self] in
            guard let self else { return }
            let result = await postalCodeLookupRepository.lookup(postalCode: postalCode)
            if Task.isCancelled { return }
            applyPostalCodeLookup(result, attemptID: attemptID, postalCode: postalCode)
        }
    }

    private func applyPostalCodeLookup(_ result: PostalCodeLookupResult, attemptID: UInt64, postalCode: String) {
        // Só aplica se a tentativa, o CEP capturado e o CEP atualmente exibido coincidirem — impede
        // uma resposta tardia de reviver um endereço trocado, mesmo no ciclo A → B → A.
        guard case let .editing(content) = state,
              case let .loading(currentAttempt, currentCode) = content.postalCodeLookup,
              currentAttempt == attemptID, currentCode == postalCode,
              content.draft.address.postalCode == postalCode else { return }

        switch result {
        case let .found(address):
            var appliedFields: Set<CepAddressField> = []
            if address.street != nil { appliedFields.insert(.street) }
            if address.complement != nil { appliedFields.insert(.complement) }
            if address.neighborhood != nil { appliedFields.insert(.neighborhood) }
            appliedFields.insert(.city)
            appliedFields.insert(.state)

            updateEditing { editing in
                if let street = address.street { editing.draft.address.street = street }
                if let complement = address.complement { editing.draft.address.complement = complement }
                if let neighborhood = address.neighborhood { editing.draft.address.neighborhood = neighborhood }
                editing.draft.address.city = address.city
                editing.draft.address.state = address.state
                editing.fieldErrors[.address(.street)] = nil
                editing.fieldErrors[.address(.neighborhood)] = nil
                editing.fieldErrors[.address(.city)] = nil
                editing.fieldErrors[.address(.state)] = nil
                editing.addressVerification = .unverified
                editing.cepAutofillProvenance = CepAutofillProvenance(postalCode: postalCode, fields: appliedFields)
                editing.postalCodeLookup = .found(attemptID: attemptID, postalCode: postalCode, appliedFields: appliedFields)
            }

            guard case let .editing(updated) = state else { return }
            let requiredOrder: [ProviderAddressField] = [.street, .neighborhood, .city, .state]
            let firstEmpty = requiredOrder.first { field in
                switch field {
                case .street: updated.draft.address.street.trimmingCharacters(in: .whitespaces).isEmpty
                case .neighborhood: updated.draft.address.neighborhood.trimmingCharacters(in: .whitespaces).isEmpty
                case .city: updated.draft.address.city.trimmingCharacters(in: .whitespaces).isEmpty
                case .state: updated.draft.address.state == nil
                default: false
                }
            }
            focusRequestID += 1
            let requestID = focusRequestID
            updateEditing { $0.focusRequest = ProviderFocusRequest(field: .address(firstEmpty ?? .number), requestID: requestID) }

        case .notFound:
            updateEditing {
                $0.postalCodeLookup = .notFound(attemptID: attemptID, postalCode: postalCode)
                $0.fieldErrors[.address(.postalCode)] = .notFound
            }

        case let .failure(reason):
            updateEditing {
                $0.postalCodeLookup = .failure(attemptID: attemptID, postalCode: postalCode, reason: reason)
            }
        }
    }

    func updateCity(_ value: String) {
        updateEditing {
            $0.draft.address.city = value
            $0.fieldErrors[.address(.city)] = nil
            $0.addressVerification = .unverified
        }
    }

    func updateState(_ value: BrazilianState?) {
        updateEditing {
            $0.draft.address.state = value
            $0.fieldErrors[.address(.state)] = nil
            $0.addressVerification = .unverified
        }
    }

    func updateComplement(_ value: String) {
        updateEditing {
            $0.draft.address.complement = value
            $0.addressVerification = .unverified
        }
    }

    // MARK: - Verificação de endereço

    func verifyAddress() {
        guard case let .editing(content) = state, content.isInputEnabled else { return }

        let (normalized, errors) = ProviderRegistrationValidation.validateAddressForVerification(content.draft.address)
        guard let normalized else {
            updateEditing { $0.fieldErrors.merge(errors) { _, new in new } }
            focusRequestID += 1
            if let field = errors.keys.first {
                let requestID = focusRequestID
                updateEditing { $0.focusRequest = ProviderFocusRequest(field: field, requestID: requestID) }
            }
            return
        }

        updateEditing { $0.addressVerification = .geocoding }
        verificationTask?.cancel()
        verificationTask = Task { [weak self] in
            guard let self else { return }
            let result = await verificationRepository.verify(address: normalized)
            if Task.isCancelled { return }
            apply(result)
        }
    }

    private func apply(_ result: ProviderAddressVerificationRepository.VerifyResult) {
        switch result {
        case let .matched(token, expiresAt):
            updateEditing { $0.addressVerification = .matched(token: token, expiresAt: expiresAt) }
        case let .failure(reason):
            updateEditing { $0.addressVerification = .failure(reason: reason) }
        }
    }

    /// Confirmação explícita exigida quando a distância excede 500m (FR-015B) — na prática nunca
    /// mais é alcançada (ver nota em `ProviderAddressVerificationState`), mantida por paridade
    /// estrutural com o Android.
    func confirmDivergence() {
        guard case let .editing(content) = state,
              case let .diverged(token, distance, expiresAt) = content.addressVerification,
              expiresAt > Date() else { return }
        updateEditing { $0.addressVerification = .confirmedDivergence(token: token, distanceMeters: distance, expiresAt: expiresAt) }
    }

    // MARK: - Offers

    func addOffer() {
        updateEditing {
            $0.draft.offers.append(OfferDraft())
            $0.fieldErrors[.offersList] = nil
        }
    }

    func removeOffer(_ id: UUID) {
        updateEditing { content in
            content.draft.offers.removeAll { $0.id == id }
            for field in OfferField.allCases {
                content.fieldErrors[.offer(localID: id, field: field)] = nil
            }
        }
    }

    /// `026` FR-001: categoria principal única do rascunho Fixo. Trocar uma categoria que já tem
    /// ofertas com dado preenchido exige confirmação explícita (contracts/provider-service-selection
    /// .md "Troca de categoria e compatibilidade") — a troca em si só é aplicada por
    /// `confirmPrimaryCategoryChange()`.
    func selectPrimaryCategory(_ categoryID: UUID?) {
        guard case let .editing(content) = state, categoryID != content.draft.primaryCategoryID else { return }
        if content.draft.offersHaveMeaningfulContent {
            updateEditing { $0.pendingPrimaryCategoryChange = PendingPrimaryCategoryChange(newCategoryID: categoryID) }
        } else {
            applyPrimaryCategoryChange(categoryID)
        }
    }

    func confirmPrimaryCategoryChange() {
        guard case let .editing(content) = state, let pending = content.pendingPrimaryCategoryChange else { return }
        applyPrimaryCategoryChange(pending.newCategoryID)
    }

    /// Cancelar a confirmação conserva o rascunho — a categoria e as ofertas atuais não são tocadas.
    func cancelPrimaryCategoryChange() {
        updateEditing { $0.pendingPrimaryCategoryChange = nil }
    }

    private func applyPrimaryCategoryChange(_ categoryID: UUID?) {
        updateEditing { content in
            content.draft.primaryCategoryID = categoryID
            content.draft.offers = [OfferDraft()]
            content.pendingPrimaryCategoryChange = nil
            content.fieldErrors[.primaryCategory] = nil
            content.fieldErrors[.offersList] = nil
            for field in OfferField.allCases {
                for offer in content.draft.offers {
                    content.fieldErrors[.offer(localID: offer.id, field: field)] = nil
                }
            }
        }

        guard let categoryID, needsServiceLoad(for: categoryID) else { return }
        updateEditing { $0.servicesByCategory[categoryID] = .loading }
        Task { [weak self] in
            guard let self else { return }
            let result = await repository.fetchServices(categoryID: categoryID)
            // `026`: respostas de carregamento são armazenadas pela categoria solicitada e não
            // mudam a categoria atualmente selecionada — guarda contra troca enquanto a busca voava.
            updateEditing { $0.servicesByCategory[categoryID] = result }
        }
    }

    private func needsServiceLoad(for categoryID: UUID) -> Bool {
        guard case let .editing(content) = state else { return false }
        return content.servicesByCategory[categoryID] == nil
    }

    func updateOfferService(_ id: UUID, serviceID: UUID?) {
        updateEditing { content in
            guard let index = content.draft.offers.firstIndex(where: { $0.id == id }) else { return }
            content.draft.offers[index].serviceID = serviceID
            content.fieldErrors[.offer(localID: id, field: .service)] = nil
        }
    }

    func updateOfferFree(_ id: UUID, isFree: Bool) {
        updateEditing { content in
            guard let index = content.draft.offers.firstIndex(where: { $0.id == id }) else { return }
            content.draft.offers[index].isFree = isFree
            if isFree { content.draft.offers[index].priceInput = "" }
            content.fieldErrors[.offer(localID: id, field: .price)] = nil
        }
    }

    func updateOfferPrice(_ id: UUID, value: String) {
        updateEditing { content in
            guard let index = content.draft.offers.firstIndex(where: { $0.id == id }) else { return }
            content.draft.offers[index].priceInput = value
            content.fieldErrors[.offer(localID: id, field: .price)] = nil
        }
    }

    func updateOfferDuration(_ id: UUID, value: String) {
        updateEditing { content in
            guard let index = content.draft.offers.firstIndex(where: { $0.id == id }) else { return }
            content.draft.offers[index].durationInput = String(BrazilianInputValidation.digitsOnly(value).prefix(5))
            content.fieldErrors[.offer(localID: id, field: .duration)] = nil
        }
    }

    func updateOfferDescription(_ id: UUID, value: String) {
        updateEditing { content in
            guard let index = content.draft.offers.firstIndex(where: { $0.id == id }) else { return }
            content.draft.offers[index].description = value
        }
    }

    /// Serviços já escolhidos por outra oferta — usado pela View para desestimular duplicidade no
    /// `Picker` (a rejeição definitiva continua no submit e no UNIQUE do banco).
    func usedServiceIDs(excluding offerID: UUID) -> Set<UUID> {
        guard case let .editing(content) = state else { return [] }
        return Set(content.draft.offers.filter { $0.id != offerID }.compactMap(\.serviceID))
    }

    // MARK: - Submit

    func submit() {
        guard case let .editing(content) = state, content.canSubmit, !content.postalCodeLookup.isLoading else { return }

        let (command, errors) = ProviderRegistrationValidation.validate(content.draft)
        updateEditing { $0.fieldErrors = errors }

        guard let command else {
            focusFirstInvalid(errors: errors, offerOrder: content.draft.offers.map(\.id))
            return
        }

        if content.addressVerification.isUsableForSubmit, let token = content.addressVerification.verificationToken {
            performSubmit(command: command, verificationToken: token)
            return
        }

        // Endereço ainda não verificado (ou a prova expirou) — verifica na hora em vez de exigir
        // que o usuário tenha tocado em "Verificar endereço" antes (mesma UX já usada no Android,
        // que nunca travou o botão nisso: `ProviderRegistrationViewModel.geocodeAndSubmit`).
        verifyAddressThenSubmit(command: command)
    }

    private func focusFirstInvalid(errors: [ProviderField: ProviderFieldError], offerOrder: [UUID]) {
        focusRequestID += 1
        if let field = ProviderRegistrationValidation.firstInvalidField(errors: errors, offerOrder: offerOrder) {
            let requestID = focusRequestID
            updateEditing { $0.focusRequest = ProviderFocusRequest(field: field, requestID: requestID) }
        }
    }

    /// Roda a mesma verificação de `verifyAddress()` e só segue para o envio de fato quando ela
    /// resolve `.matched` — `.diverged` continua exigindo confirmação explícita do usuário
    /// (`confirmDivergence()`, FR-015B, já disparada pelo `onChange` da View) e `.failure` mostra o
    /// próprio erro; nenhum dos dois avança sozinho.
    private func verifyAddressThenSubmit(command: ProviderRegistrationCommand) {
        guard case let .editing(content) = state else { return }
        let (normalized, addressErrors) = ProviderRegistrationValidation.validateAddressForVerification(content.draft.address)
        guard let normalized else {
            updateEditing { $0.fieldErrors.merge(addressErrors) { _, new in new } }
            focusFirstInvalid(errors: addressErrors, offerOrder: [])
            return
        }

        updateEditing { $0.addressVerification = .geocoding; $0.submission = .submitting }
        verificationTask?.cancel()
        verificationTask = Task { [weak self] in
            guard let self else { return }
            let result = await verificationRepository.verify(address: normalized)
            if Task.isCancelled { return }
            apply(result)
            guard case let .editing(refreshed) = state else { return }
            if case let .matched(token, _) = refreshed.addressVerification {
                performSubmit(command: command, verificationToken: token)
            } else {
                updateEditing { $0.submission = .idle }
            }
        }
    }

    private func performSubmit(command: ProviderRegistrationCommand, verificationToken: String) {
        updateEditing { $0.submission = .submitting }
        submissionTask?.cancel()
        submissionTask = Task { [weak self] in
            guard let self else { return }
            let result = await repository.submit(
                command,
                accountID: accountID,
                verificationToken: verificationToken
            )
            if Task.isCancelled { return }
            apply(result)
        }
    }

    private func apply(_ result: ProviderRegistrationRepository.SubmissionResult) {
        switch result {
        case let .created(summary), let .alreadyRegistered(summary):
            // Ambos os outcomes limpam o rascunho — um retry que encontra o agregado completo é
            // sucesso reconhecido, não uma segunda criação.
            state = .success(summary)
        case .sessionExpired:
            state = .sessionExpired
        case .emailUnavailable:
            updateEditing { $0.fieldErrors[.company(.email)] = .unavailable; $0.submission = .idle }
        case .cnpjUnavailable:
            updateEditing { $0.fieldErrors[.company(.cnpj)] = .unavailable; $0.submission = .idle }
        case .duplicateVehicle:
            updateEditing { $0.fieldErrors[.vehicle(.plate)] = .duplicate; $0.submission = .idle }
        case .duplicateService:
            updateEditing { $0.submission = .failure(reason: .duplicateService) }
        case .catalogChanged:
            updateEditing { $0.submission = .failure(reason: .catalogChanged) }
        case .geocodeExpired:
            updateEditing {
                $0.addressVerification = .unverified
                $0.submission = .failure(reason: .geocodeExpired)
            }
        case .divergenceConfirmationRequired:
            updateEditing {
                $0.addressVerification = .unverified
                $0.submission = .failure(reason: .divergenceConfirmationRequired)
            }
        case .invalidInput:
            updateEditing { $0.submission = .failure(reason: .invalidInput) }
        case .timeout:
            updateEditing { $0.submission = .failure(reason: .timeout) }
        case .offline:
            updateEditing { $0.submission = .failure(reason: .offline) }
        case .serviceUnavailable:
            updateEditing { $0.submission = .failure(reason: .serviceUnavailable) }
        case .contract:
            updateEditing { $0.submission = .failure(reason: .contract) }
        case .unknown:
            updateEditing { $0.submission = .failure(reason: .unknown) }
        }
    }

    // MARK: - Helpers

    private func updateEditing(_ mutate: (inout EditingContent) -> Void) {
        guard case var .editing(content) = state else { return }
        mutate(&content)
        state = .editing(content)
    }
}
