//
//  GarageUiModels.swift
//  pitgo
//

import Foundation

enum GarageFailureReason {
    case offline
    case service
    case unknown
}

enum GarageUiState {
    case loading
    case empty
    case content([Vehicle], changingPrimaryVehicleID: UUID?)
    case failure(GarageFailureReason)
}

enum VehicleFormOrigin {
    case onboarding
    case garage
}

/// Falhas gerais (`012` — contracts/vehicle-rpcs.md "Contrato de erros sanitizados") — nenhuma
/// marca campo; violações de dado conhecidas viram `VehicleFormResult.fieldFailure` em vez disto.
enum VehicleFormFailureReason {
    case offline
    case timeout
    case sessionExpired
    case rpcUnavailable
    case serviceUnavailable
    case vehicleUnavailable
    case contract
    case unknown
}

enum VehicleFormSubmissionState: Equatable {
    case editing
    case submitting
    case success(Vehicle)
    case failure(VehicleFormFailureReason)

    static func == (lhs: VehicleFormSubmissionState, rhs: VehicleFormSubmissionState) -> Bool {
        switch (lhs, rhs) {
        case (.editing, .editing), (.submitting, .submitting):
            true
        case let (.success(a), .success(b)):
            a.id == b.id
        case let (.failure(a), .failure(b)):
            a == b
        default:
            false
        }
    }
}

extension VehicleFormFailureReason: Equatable {}

/// Texto bruto do formulário, em memória; convertido para `VehicleDraft` normalizado somente no
/// submit (ver data-model.md §5).
struct VehicleFormRawInput {
    var brand: String = ""
    var model: String = ""
    var version: String = ""
    var manufactureYear: String = ""
    var modelYear: String = ""
    var plate: String = ""
    var renavam: String = ""
    var chassis: String = ""
    var color: String = ""
    var fuelType: String = ""
    var transmission: String = ""
    var engine: String = ""
    var mileage: String = ""
    var makePrimary: Bool = false
}

struct VehicleFocusRequest: Equatable {
    let field: VehicleField
    let requestID: Int
}

struct VehicleFormUiState {
    var input = VehicleFormRawInput()
    var fieldErrors: [VehicleField: VehicleFieldError] = [:]
    var focusRequest: VehicleFocusRequest?
    var existingVehicleCount: Int
    var submission: VehicleFormSubmissionState = .editing
    let origin: VehicleFormOrigin

    var isInputEnabled: Bool {
        if case .submitting = submission { return false }
        return true
    }

    var isSubmitting: Bool {
        if case .submitting = submission { return true }
        return false
    }

    var showsPrimaryToggle: Bool { existingVehicleCount > 0 }
}
