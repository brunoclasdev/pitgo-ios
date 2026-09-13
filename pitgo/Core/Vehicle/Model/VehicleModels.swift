//
//  VehicleModels.swift
//  pitgo
//
//  Mapeia `public.vehicles` (schema já aplicado, ver contracts/supabase.md). `VehicleDraft` é criado
//  somente no submit do formulário e nunca persistido localmente.
//

import Foundation

struct Vehicle: Decodable, Identifiable, Hashable {
    let id: UUID
    let userID: UUID
    let brand: String
    let model: String
    let version: String?
    let manufactureYear: Int?
    let modelYear: Int?
    let plate: String?
    let renavam: String?
    let chassis: String?
    let color: String?
    let fuelType: String?
    let transmission: String?
    let engine: String?
    let mileage: Int?
    let isPrimary: Bool
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case brand, model, version
        case manufactureYear = "manufacture_year"
        case modelYear = "model_year"
        case plate, renavam, chassis, color
        case fuelType = "fuel_type"
        case transmission, engine, mileage
        case isPrimary = "is_primary"
        case active
    }

    /// "Marca Modelo · ano-modelo · PLACA" com segmentos ausentes omitidos.
    var summaryLine: String {
        var parts: [String] = []
        if let modelYear { parts.append(String(modelYear)) }
        if let plate, !plate.isEmpty { parts.append(plate) }
        return parts.joined(separator: " · ")
    }
}

/// Entrada normalizada criada somente no submit; nunca contém `id`/`userID`/`active`/`isPrimary`.
struct VehicleDraft {
    var brand: String
    var model: String
    var version: String?
    var manufactureYear: Int?
    var modelYear: Int?
    var plate: String?
    var renavam: String?
    var chassis: String?
    var color: String?
    var fuelType: String?
    var transmission: String?
    var engine: String?
    var mileage: Int?
    var makePrimary: Bool
}

enum VehicleField: Hashable, CaseIterable {
    case brand, model, version, manufactureYear, modelYear
    case plate, renavam, chassis, color, fuelType, transmission, engine, mileage
}

enum VehicleFieldError: Hashable {
    case required
    case invalidFormat
    case outOfRange
    case unavailable
}

/// `.fieldFailure` cobre tanto violação local quanto remota já traduzida por
/// `contracts/vehicle-rpcs.md` (P2001..P2013) — a View trata as duas fontes da mesma forma, marcando
/// somente o campo responsável. `.failure` nunca marca campo (ver `VehicleFormFailureReason`).
enum VehicleFormResult {
    case success(Vehicle)
    case fieldFailure(VehicleField, VehicleFieldError)
    case failure(VehicleFormFailureReason)
}
