//
//  ProviderRegistrationValidation.swift
//  pitgo
//
//  Normalização e validação puramente locais (data-model.md "Ordem de validação e foco"). A
//  autoridade final continua sendo `create_provider_registration`/`geocode-provider-address` no
//  backend compartilhado. Nunca produz um comando com ID de owner/provider/categoria.
//

import Foundation

enum ProviderRegistrationValidation {
    /// Valida empresa, endereço (texto) e ofertas para o submit final. Até esta sessão, o texto do
    /// endereço não era revalidado aqui — a suposição era que a coordenada já vinha travada por uma
    /// verificação usável, então só o UUID da prova era enviado à RPC. Achado em device físico real:
    /// a RPC `create_provider_registration` de verdade recebe o texto do endereço direto (`p_address`,
    /// junto do `verification_token`), não um `p_geocode_verification_id` — ver nota em
    /// `ProviderAddressVerificationState`. Por isso o endereço agora é validado igual aos outros
    /// campos.
    static func validate(_ draft: ProviderRegistrationDraft) -> (command: ProviderRegistrationCommand?, errors: [ProviderField: ProviderFieldError]) {
        var errors: [ProviderField: ProviderFieldError] = [:]
        let company = validateCompany(draft.company, into: &errors)
        let address = validateAddress(draft.address, into: &errors)
        // `026` FR-001: só o prestador Fixo escolhe categoria principal — Móvel/PitTec recebem o
        // serviço implícito e nunca passam por aqui.
        if draft.providerKind != .store, draft.locationMode == .fixed, draft.primaryCategoryID == nil {
            errors[.primaryCategory] = .required
        }
        let offers = draft.providerKind == .store ? [] : validateOffers(draft.offers, providerKind: draft.providerKind, into: &errors)
        var vehicle: NormalizedProviderVehicle?
        if draft.providerKind == .guincho {
            let plate = draft.vehiclePlate.uppercased().filter { $0.isLetter || $0.isNumber }
            let make = BrazilianInputValidation.trim(draft.vehicleMake)
            let model = BrazilianInputValidation.trim(draft.vehicleModel)
            let color = BrazilianInputValidation.trim(draft.vehicleColor)
            if plate.range(of: "^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$", options: .regularExpression) == nil { errors[.vehicle(.plate)] = .invalidFormat }
            if make.isEmpty { errors[.vehicle(.make)] = .required }
            if model.isEmpty { errors[.vehicle(.model)] = .required }
            if draft.guinchoSizeID == nil { errors[.vehicle(.size)] = .required }
            if color.isEmpty { errors[.vehicle(.color)] = .required }
            if errors[.vehicle(.plate)] == nil && errors[.vehicle(.make)] == nil && errors[.vehicle(.model)] == nil && errors[.vehicle(.color)] == nil {
                vehicle = NormalizedProviderVehicle(plate: plate, make: make, model: model, color: color, guinchoSizeID: draft.guinchoSizeID)
            }
        }

        guard let company, let address, let offers,
              !(draft.providerKind != .store && draft.locationMode == .fixed && draft.primaryCategoryID == nil),
              (draft.providerKind != .guincho || vehicle != nil),
              errors.isEmpty else {
            return (nil, errors)
        }
        return (ProviderRegistrationCommand(company: company, address: address, providerKind: draft.providerKind, vehicle: vehicle, locationMode: draft.locationMode, offers: offers), errors)
    }

    /// Valida os campos de endereço antes de disparar `geocode-provider-address` — usada pelo botão
    /// "Verificar endereço" (T029), independente da validação de submit acima.
    static func validateAddressForVerification(_ address: AddressDraft) -> (address: NormalizedAddress?, errors: [ProviderField: ProviderFieldError]) {
        var errors: [ProviderField: ProviderFieldError] = [:]
        let normalized = validateAddress(address, into: &errors)
        return (normalized, errors)
    }

    /// Primeiro campo inválido em ordem visual: empresa → endereço → modalidade → "ao menos uma
    /// oferta" → cada oferta (na ordem em que aparece no rascunho).
    static func firstInvalidField(errors: [ProviderField: ProviderFieldError], offerOrder: [UUID]) -> ProviderField? {
        let companyOrder: [ProviderCompanyField] = [.name, .email, .phone, .cnpj, .description]
        for field in companyOrder where errors[.company(field)] != nil {
            return .company(field)
        }

        let addressOrder: [ProviderAddressField] = [.postalCode, .street, .number, .complement, .neighborhood, .city, .state]
        for field in addressOrder where errors[.address(field)] != nil {
            return .address(field)
        }

        for field in [ProviderVehicleField.plate, .make, .model, .color] where errors[.vehicle(field)] != nil {
            return .vehicle(field)
        }

        if errors[.locationMode] != nil { return .locationMode }
        if errors[.primaryCategory] != nil { return .primaryCategory }
        if errors[.offersList] != nil { return .offersList }

        let offerFieldOrder: [OfferField] = [.service, .price, .duration, .description]
        for localID in offerOrder {
            for field in offerFieldOrder {
                let key = ProviderField.offer(localID: localID, field: field)
                if errors[key] != nil { return key }
            }
        }

        return nil
    }

    // MARK: - Empresa

    private static func validateCompany(_ company: CompanyDraft, into errors: inout [ProviderField: ProviderFieldError]) -> NormalizedCompany? {
        var isValid = true

        let name = BrazilianInputValidation.trim(company.name)
        if name.isEmpty {
            errors[.company(.name)] = .required
            isValid = false
        }

        let email = BrazilianInputValidation.normalizeEmail(company.email)
        if email.isEmpty {
            errors[.company(.email)] = .required
            isValid = false
        } else if !BrazilianInputValidation.isValidEmail(email) {
            errors[.company(.email)] = .invalidFormat
            isValid = false
        }

        let phoneDigits = BrazilianInputValidation.digitsOnly(company.phone)
        if phoneDigits.isEmpty {
            errors[.company(.phone)] = .required
            isValid = false
        } else if !BrazilianInputValidation.isValidBrazilianPhone(phoneDigits) {
            errors[.company(.phone)] = .invalidFormat
            isValid = false
        }

        let cnpj = BrazilianInputValidation.normalizeCNPJ(company.cnpj)
        if cnpj.isEmpty {
            errors[.company(.cnpj)] = .required
            isValid = false
        } else if !BrazilianInputValidation.isValidCNPJ(cnpj) {
            errors[.company(.cnpj)] = .invalidFormat
            isValid = false
        }

        let description = BrazilianInputValidation.trim(company.description)

        guard isValid else { return nil }
        return NormalizedCompany(
            name: name,
            description: description.isEmpty ? nil : description,
            email: email,
            phone: phoneDigits,
            cnpj: cnpj
        )
    }

    // MARK: - Endereço (texto — sem coordenadas manuais, ver ProviderAddressVerificationState)

    private static func validateAddress(_ address: AddressDraft, into errors: inout [ProviderField: ProviderFieldError]) -> NormalizedAddress? {
        var isValid = true

        let street = BrazilianInputValidation.trim(address.street)
        if street.isEmpty {
            errors[.address(.street)] = .required
            isValid = false
        }

        let number = BrazilianInputValidation.trim(address.number)
        if number.isEmpty {
            errors[.address(.number)] = .required
            isValid = false
        }

        let neighborhood = BrazilianInputValidation.trim(address.neighborhood)
        if neighborhood.isEmpty {
            errors[.address(.neighborhood)] = .required
            isValid = false
        }

        let zipCode = BrazilianInputValidation.digitsOnly(address.postalCode)
        if zipCode.isEmpty {
            errors[.address(.postalCode)] = .required
            isValid = false
        } else if !BrazilianInputValidation.isValidCEP(zipCode) {
            errors[.address(.postalCode)] = .invalidFormat
            isValid = false
        }

        let city = BrazilianInputValidation.trim(address.city)
        if city.isEmpty {
            errors[.address(.city)] = .required
            isValid = false
        }

        guard let state = address.state else {
            errors[.address(.state)] = .required
            return nil
        }

        let complement = BrazilianInputValidation.trim(address.complement)

        guard isValid else { return nil }
        return NormalizedAddress(
            street: street,
            number: number,
            neighborhood: neighborhood,
            zipCode: zipCode,
            city: city,
            state: state.rawValue,
            country: "BR",
            complement: complement.isEmpty ? nil : complement
        )
    }

    // MARK: - Ofertas

    private static func validateOffers(_ offers: [OfferDraft], providerKind: ProviderKind, into errors: inout [ProviderField: ProviderFieldError]) -> [NormalizedOffer]? {
        if providerKind == .guincho || providerKind == .pittec {
            guard let serviceID = offers.first?.serviceID else {
                errors[.offersList] = .required
                return nil
            }
            return [NormalizedOffer(serviceID: serviceID, price: 0, durationMinutes: 60, description: nil, isFree: true)]
        }
        guard !offers.isEmpty else {
            errors[.offersList] = .required
            return nil
        }

        var isValid = true
        var normalized: [NormalizedOffer] = []
        var seenServiceIDs: Set<UUID> = []

        for offer in offers {
            var resolvedServiceID: UUID?
            if let serviceID = offer.serviceID {
                if seenServiceIDs.contains(serviceID) {
                    errors[.offer(localID: offer.id, field: .service)] = .duplicate
                    isValid = false
                } else {
                    seenServiceIDs.insert(serviceID)
                    resolvedServiceID = serviceID
                }
            } else {
                errors[.offer(localID: offer.id, field: .service)] = .required
                isValid = false
            }

            var resolvedPrice: Decimal?
            if offer.isFree {
                resolvedPrice = 0
            } else {
                let priceText = BrazilianInputValidation.trim(offer.priceInput).replacingOccurrences(of: ",", with: ".")
                let scaleParts = priceText.split(separator: ".", omittingEmptySubsequences: false)
                let hasValidScale = scaleParts.count <= 2 && (scaleParts.count < 2 || scaleParts[1].count <= 2)
                if let parsed = Decimal(string: priceText), hasValidScale, parsed > 0 {
                    resolvedPrice = parsed
                } else {
                    errors[.offer(localID: offer.id, field: .price)] = priceText.isEmpty ? .required : .invalidFormat
                    isValid = false
                }
            }

            var resolvedDuration: Int?
            let durationText = BrazilianInputValidation.trim(offer.durationInput)
            if let duration = Int(durationText), duration >= 1, duration <= 10_080 {
                resolvedDuration = duration
            } else {
                errors[.offer(localID: offer.id, field: .duration)] = durationText.isEmpty ? .required : .outOfRange
                isValid = false
            }

            let description = BrazilianInputValidation.trim(offer.description)

            if let serviceID = resolvedServiceID, let price = resolvedPrice, let duration = resolvedDuration {
                normalized.append(NormalizedOffer(
                    serviceID: serviceID,
                    price: price,
                    durationMinutes: duration,
                    description: description.isEmpty ? nil : description,
                    isFree: offer.isFree
                ))
            }
        }

        guard isValid, normalized.count == offers.count else { return nil }
        return normalized
    }
}
