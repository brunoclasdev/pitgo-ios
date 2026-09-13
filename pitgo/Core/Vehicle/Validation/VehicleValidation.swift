//
//  VehicleValidation.swift
//  pitgo
//
//  Normalização e validação local (feedback imediato). O RPC repete as invariantes decisivas
//  (autoridade final, backend inalterado — ver research.md §6).
//

import Foundation

enum VehicleValidation {
    static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `nil` quando vazio após trim; caso contrário o texto normalizado (sem alterar conteúdo
    /// significativo).
    static func normalizedOptionalText(_ value: String) -> String? {
        let trimmed = trim(value)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedPlate(_ value: String) -> String? {
        let canonical = value.uppercased().filter { $0.isLetter || $0.isNumber }
        return canonical.isEmpty ? nil : canonical
    }

    static func normalizedRenavam(_ value: String) -> String? {
        let digits = value.filter(\.isNumber)
        return digits.isEmpty ? nil : digits
    }

    static func normalizedChassis(_ value: String) -> String? {
        let canonical = value.uppercased().filter { $0.isLetter || $0.isNumber }
        return canonical.isEmpty ? nil : canonical
    }

    /// Placa legado (3 letras + 4 dígitos) ou Mercosul (3 letras + 1 dígito + 1 letra + 2 dígitos).
    static func isValidPlate(_ canonical: String) -> Bool {
        let legado = #"^[A-Z]{3}[0-9]{4}$"#
        let mercosul = #"^[A-Z]{3}[0-9][A-Z][0-9]{2}$"#
        return canonical.range(of: legado, options: .regularExpression) != nil
            || canonical.range(of: mercosul, options: .regularExpression) != nil
    }

    static func isValidRenavam(_ digits: String) -> Bool {
        digits.count == 11
    }

    /// VIN de 17 caracteres alfanuméricos maiúsculos, sem I/O/Q (não usados em VIN por ambiguidade
    /// com 1/0).
    static func isValidChassis(_ canonical: String) -> Bool {
        guard canonical.count == 17 else { return false }
        let forbidden = CharacterSet(charactersIn: "IOQ")
        return canonical.rangeOfCharacter(from: forbidden) == nil
            && canonical.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// 1900 até o próximo ano civil, inclusive.
    static func isValidYear(_ year: Int) -> Bool {
        let nextYear = Calendar.current.component(.year, from: Date()) + 1
        return year >= 1900 && year <= nextYear
    }

    static func isValidMileage(_ mileage: Int) -> Bool {
        mileage >= 0
    }

    /// `nil` para texto vazio (campo opcional); `Int` válido; ou `nil` de erro para texto não vazio
    /// que não converte (a View trata a diferença via `VehicleFieldError`).
    static func parseOptionalInt(_ text: String) -> Int?? {
        let trimmed = trim(text)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = Int(trimmed) else { return nil }
        return .some(value)
    }
}
