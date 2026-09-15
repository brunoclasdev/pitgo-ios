//
//  VehicleFormViewModel.swift
//  pitgo
//
//  `userID` nunca é um campo do formulário — vem exclusivamente da sessão atual, no `init` do
//  Repository (ver contracts/navigation.md).
//

import Combine
import Foundation

@MainActor
final class VehicleFormViewModel: ObservableObject {
    @Published private(set) var state: VehicleFormUiState

    private let repository: VehicleRepository
    private let onSaved: (Vehicle) -> Void
    private var focusRequestID = 0

    init(
        repository: VehicleRepository,
        existingVehicleCount: Int,
        origin: VehicleFormOrigin,
        onSaved: @escaping (Vehicle) -> Void
    ) {
        self.repository = repository
        self.onSaved = onSaved
        state = VehicleFormUiState(existingVehicleCount: existingVehicleCount, origin: origin)
    }

    func update(_ field: VehicleField, text: String) {
        guard state.isInputEnabled else { return }
        switch field {
        case .brand: state.input.brand = text
        case .model: state.input.model = text
        case .version: state.input.version = text
        case .manufactureYear: state.input.manufactureYear = text
        case .modelYear: state.input.modelYear = text
        case .plate: state.input.plate = text
        case .renavam: state.input.renavam = text
        case .chassis: state.input.chassis = text
        case .color: state.input.color = text
        case .fuelType: state.input.fuelType = text
        case .transmission: state.input.transmission = text
        case .engine: state.input.engine = text
        case .mileage: state.input.mileage = text
        }
        // Um erro existente só desaparece quando o novo valor daquele campo se torna válido —
        // erros de outros campos e os demais valores permanecem intocados (US2 acceptance #5).
        if state.fieldErrors[field] != nil, isFieldValueValid(field) {
            state.fieldErrors[field] = nil
        }
    }

    private func isFieldValueValid(_ field: VehicleField) -> Bool {
        switch field {
        case .brand:
            return !VehicleValidation.trim(state.input.brand).isEmpty
        case .model:
            return !VehicleValidation.trim(state.input.model).isEmpty
        case .manufactureYear, .modelYear:
            let text = field == .manufactureYear ? state.input.manufactureYear : state.input.modelYear
            guard let parsed = VehicleValidation.parseOptionalInt(text) else { return false }
            guard let year = parsed else { return true } // vazio: opcional, válido
            return VehicleValidation.isValidYear(year)
        case .plate:
            guard let plate = VehicleValidation.normalizedPlate(state.input.plate) else { return true }
            return VehicleValidation.isValidPlate(plate)
        case .renavam:
            guard let renavam = VehicleValidation.normalizedRenavam(state.input.renavam) else { return true }
            return VehicleValidation.isValidRenavam(renavam)
        case .chassis:
            guard let chassis = VehicleValidation.normalizedChassis(state.input.chassis) else { return true }
            return VehicleValidation.isValidChassis(chassis)
        case .mileage:
            guard let parsed = VehicleValidation.parseOptionalInt(state.input.mileage) else { return false }
            guard let mileage = parsed else { return true }
            return VehicleValidation.isValidMileage(mileage)
        case .version, .color, .fuelType, .transmission, .engine:
            return true // sem regra de formato
        }
    }

    func setMakePrimary(_ value: Bool) {
        guard state.isInputEnabled else { return }
        state.input.makePrimary = value
    }

    func submit() {
        guard state.isInputEnabled else { return }

        var errors: [VehicleField: VehicleFieldError] = [:]

        let brand = VehicleValidation.trim(state.input.brand)
        if brand.isEmpty { errors[.brand] = .required }

        let model = VehicleValidation.trim(state.input.model)
        if model.isEmpty { errors[.model] = .required }

        let version = VehicleValidation.normalizedOptionalText(state.input.version)

        let manufactureYear = parseYear(state.input.manufactureYear, field: .manufactureYear, into: &errors)
        let modelYear = parseYear(state.input.modelYear, field: .modelYear, into: &errors)

        let plate = VehicleValidation.normalizedPlate(state.input.plate)
        if let plate, !VehicleValidation.isValidPlate(plate) {
            errors[.plate] = .invalidFormat
        }

        let renavam = VehicleValidation.normalizedRenavam(state.input.renavam)
        if let renavam, !VehicleValidation.isValidRenavam(renavam) {
            errors[.renavam] = .invalidFormat
        }

        let chassis = VehicleValidation.normalizedChassis(state.input.chassis)
        if let chassis, !VehicleValidation.isValidChassis(chassis) {
            errors[.chassis] = .invalidFormat
        }

        let color = VehicleValidation.normalizedOptionalText(state.input.color)
        let fuelType = VehicleValidation.normalizedOptionalText(state.input.fuelType)
        let transmission = VehicleValidation.normalizedOptionalText(state.input.transmission)
        let engine = VehicleValidation.normalizedOptionalText(state.input.engine)

        let mileage = parseMileage(state.input.mileage, into: &errors)

        state.fieldErrors = errors
        guard errors.isEmpty else {
            focusRequestID += 1
            if let field = VehicleField.allCases.first(where: { errors[$0] != nil }) {
                state.focusRequest = VehicleFocusRequest(field: field, requestID: focusRequestID)
            }
            return
        }

        let draft = VehicleDraft(
            brand: brand,
            model: model,
            version: version,
            manufactureYear: manufactureYear,
            modelYear: modelYear,
            plate: plate,
            renavam: renavam,
            chassis: chassis,
            color: color,
            fuelType: fuelType,
            transmission: transmission,
            engine: engine,
            mileage: mileage,
            makePrimary: state.showsPrimaryToggle ? state.input.makePrimary : false
        )

        state.submission = .submitting

        Task { [weak self] in
            guard let self else { return }
            let result = await repository.createVehicle(draft)
            apply(result)
        }
    }

    private func apply(_ result: VehicleFormResult) {
        switch result {
        case let .success(vehicle):
            state.submission = .success(vehicle)
            onSaved(vehicle)
        case let .fieldFailure(field, error):
            // Falha de dado (local ou traduzida do servidor) volta ao estado editável — sem banner
            // geral, CTA reabilitado, e o mesmo mecanismo de foco da validação local se aplica
            // (data-model.md "VehicleFormOperation": `.submitting → .editing` em falha de campo).
            state.fieldErrors[field] = error
            state.submission = .editing
            focusRequestID += 1
            state.focusRequest = VehicleFocusRequest(field: field, requestID: focusRequestID)
        case let .failure(reason):
            state.submission = .failure(reason)
        }
    }

    private func parseYear(_ text: String, field: VehicleField, into errors: inout [VehicleField: VehicleFieldError]) -> Int? {
        guard let parsed = VehicleValidation.parseOptionalInt(text) else {
            errors[field] = .invalidFormat
            return nil
        }
        guard let year = parsed else { return nil }
        guard VehicleValidation.isValidYear(year) else {
            errors[field] = .outOfRange
            return nil
        }
        return year
    }

    private func parseMileage(_ text: String, into errors: inout [VehicleField: VehicleFieldError]) -> Int? {
        guard let parsed = VehicleValidation.parseOptionalInt(text) else {
            errors[.mileage] = .invalidFormat
            return nil
        }
        guard let mileage = parsed else { return nil }
        guard VehicleValidation.isValidMileage(mileage) else {
            errors[.mileage] = .outOfRange
            return nil
        }
        return mileage
    }
}
