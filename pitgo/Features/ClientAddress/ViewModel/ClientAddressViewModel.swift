//
//  ClientAddressViewModel.swift
//  pitgo
//
//  Cadastro/edição do endereço do cliente (`014` US5/US6). Reaproveita `ViaCepAddressLookupRepository`
//  (`011`) para preencher rua/bairro/cidade/UF pelo CEP; a coordenada é uma leitura pontual de GPS
//  no momento de salvar (`DeviceLocationRepository`, `009`) — nunca inventada.
//

import Foundation

@Observable
@MainActor
final class ClientAddressViewModel {
    private(set) var state: ClientAddressUiState = .loading

    private let repository: ClientAddressRepository
    private let postalCodeLookupRepository: ViaCepAddressLookupRepository
    private let locationRepository: DeviceLocationRepository
    private var postalCodeAttemptID: UInt64 = 0
    private var postalCodeLookupTask: Task<Void, Never>?

    init(
        repository: ClientAddressRepository,
        locationRepository: DeviceLocationRepository,
        postalCodeLookupRepository: ViaCepAddressLookupRepository = ViaCepAddressLookupRepository()
    ) {
        self.repository = repository
        self.locationRepository = locationRepository
        self.postalCodeLookupRepository = postalCodeLookupRepository
    }

    func load() {
        state = .loading
        Task { [weak self] in
            guard let self else { return }
            switch await repository.fetch() {
            case let .found(address):
                state = .editing(draft: draft(from: address), fieldErrors: [:], submission: .idle, savedAddress: address)
            case .notFound:
                state = .editing(draft: ClientAddressDraft(), fieldErrors: [:], submission: .idle, savedAddress: nil)
            case .failure:
                state = .editing(draft: ClientAddressDraft(), fieldErrors: [:], submission: .idle, savedAddress: nil)
            }
        }
    }

    private func draft(from address: ClientAddress) -> ClientAddressDraft {
        var draft = ClientAddressDraft()
        draft.street = address.street
        draft.number = address.number
        draft.neighborhood = address.neighborhood
        draft.postalCode = address.zipCode
        draft.city = address.city
        draft.state = BrazilianState(rawValue: address.state)
        draft.complement = address.complement ?? ""
        return draft
    }

    // MARK: - Campos

    func update(_ field: ClientAddressField, text: String) {
        guard case var .editing(draft, errors, submission, saved) = state else { return }
        switch field {
        case .postalCode: draft.postalCode = String(BrazilianInputValidation.digitsOnly(text).prefix(8))
        case .street: draft.street = text
        case .number: draft.number = text
        case .complement: draft.complement = text
        case .neighborhood: draft.neighborhood = text
        case .city: draft.city = text
        case .state: break
        }
        errors[field] = nil
        state = .editing(draft: draft, fieldErrors: errors, submission: submission, savedAddress: saved)
    }

    func updateState(_ value: BrazilianState?) {
        guard case var .editing(draft, errors, submission, saved) = state else { return }
        draft.state = value
        errors[.state] = nil
        state = .editing(draft: draft, fieldErrors: errors, submission: submission, savedAddress: saved)
    }

    func lookupPostalCode() {
        guard case let .editing(draft, _, _, _) = state, draft.postalCode.count == 8, !draft.postalCodeLookup.isLoading else { return }
        postalCodeAttemptID += 1
        let attemptID = postalCodeAttemptID
        let postalCode = draft.postalCode
        updateDraft { $0.postalCodeLookup = .loading(attemptID: attemptID, postalCode: postalCode) }

        postalCodeLookupTask?.cancel()
        postalCodeLookupTask = Task { [weak self] in
            guard let self else { return }
            let result = await postalCodeLookupRepository.lookup(postalCode: postalCode)
            applyPostalCodeLookup(result, attemptID: attemptID, postalCode: postalCode)
        }
    }

    private func applyPostalCodeLookup(_ result: PostalCodeLookupResult, attemptID: UInt64, postalCode: String) {
        guard case let .editing(draft, _, _, _) = state,
              case let .loading(currentAttempt, currentCode) = draft.postalCodeLookup,
              currentAttempt == attemptID, currentCode == postalCode, draft.postalCode == postalCode else { return }

        switch result {
        case let .found(address):
            var applied: Set<CepAddressField> = []
            updateDraft { editing in
                if let street = address.street { editing.street = street; applied.insert(.street) }
                if let complement = address.complement { editing.complement = complement; applied.insert(.complement) }
                if let neighborhood = address.neighborhood { editing.neighborhood = neighborhood; applied.insert(.neighborhood) }
                editing.city = address.city; applied.insert(.city)
                editing.state = address.state; applied.insert(.state)
                editing.cepAutofillProvenance = CepAutofillProvenance(postalCode: postalCode, fields: applied)
                editing.postalCodeLookup = .found(attemptID: attemptID, postalCode: postalCode, appliedFields: applied)
            }
            clearErrors([.street, .neighborhood, .city, .state])
        case .notFound:
            updateDraft { $0.postalCodeLookup = .notFound(attemptID: attemptID, postalCode: postalCode) }
            setError(.postalCode, .notFound)
        case let .failure(reason):
            updateDraft { $0.postalCodeLookup = .failure(attemptID: attemptID, postalCode: postalCode, reason: reason) }
        }
    }

    private func updateDraft(_ mutate: (inout ClientAddressDraft) -> Void) {
        guard case var .editing(draft, errors, submission, saved) = state else { return }
        mutate(&draft)
        state = .editing(draft: draft, fieldErrors: errors, submission: submission, savedAddress: saved)
    }

    private func setError(_ field: ClientAddressField, _ error: ClientAddressFieldError) {
        guard case var .editing(draft, errors, submission, saved) = state else { return }
        errors[field] = error
        state = .editing(draft: draft, fieldErrors: errors, submission: submission, savedAddress: saved)
    }

    private func clearErrors(_ fields: [ClientAddressField]) {
        guard case var .editing(draft, errors, submission, saved) = state else { return }
        for field in fields { errors[field] = nil }
        state = .editing(draft: draft, fieldErrors: errors, submission: submission, savedAddress: saved)
    }

    // MARK: - Salvar

    func save() {
        guard case let .editing(draft, _, submission, saved) = state, submission != .submitting else { return }

        var errors: [ClientAddressField: ClientAddressFieldError] = [:]
        let street = BrazilianInputValidation.trim(draft.street)
        if street.isEmpty { errors[.street] = .required }
        let number = BrazilianInputValidation.trim(draft.number)
        if number.isEmpty { errors[.number] = .required }
        let neighborhood = BrazilianInputValidation.trim(draft.neighborhood)
        if neighborhood.isEmpty { errors[.neighborhood] = .required }
        let city = BrazilianInputValidation.trim(draft.city)
        if city.isEmpty { errors[.city] = .required }
        if draft.postalCode.count != 8 { errors[.postalCode] = .invalidFormat }
        guard let state = draft.state else {
            errors[.state] = .required
            self.state = .editing(draft: draft, fieldErrors: errors, submission: submission, savedAddress: saved)
            return
        }
        guard errors.isEmpty else {
            self.state = .editing(draft: draft, fieldErrors: errors, submission: submission, savedAddress: saved)
            return
        }

        self.state = .editing(draft: draft, fieldErrors: [:], submission: .submitting, savedAddress: saved)
        Task { [weak self] in
            guard let self else { return }
            switch await locationRepository.requestOneShotFix(timeout: 15) {
            case let .success(fix):
                let result = await repository.save(draft, latitude: fix.latitude, longitude: fix.longitude)
                apply(result, draft: draft, previousSaved: saved)
            default:
                self.state = .editing(draft: draft, fieldErrors: [:], submission: .failure(.locationRequired), savedAddress: saved)
            }
        }
    }

    private func apply(_ result: ClientAddressSaveResult, draft: ClientAddressDraft, previousSaved: ClientAddress?) {
        switch result {
        case let .success(address):
            state = .editing(draft: self.draft(from: address), fieldErrors: [:], submission: .idle, savedAddress: address)
        case .invalidInput:
            state = .editing(draft: draft, fieldErrors: [:], submission: .failure(.invalidInput), savedAddress: previousSaved)
        case .sessionExpired:
            state = .sessionExpired
        case .offline:
            state = .editing(draft: draft, fieldErrors: [:], submission: .failure(.offline), savedAddress: previousSaved)
        case .service:
            state = .editing(draft: draft, fieldErrors: [:], submission: .failure(.service), savedAddress: previousSaved)
        case .unknown:
            state = .editing(draft: draft, fieldErrors: [:], submission: .failure(.unknown), savedAddress: previousSaved)
        }
    }
}
