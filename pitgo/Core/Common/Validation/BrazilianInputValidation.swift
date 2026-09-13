//
//  BrazilianInputValidation.swift
//  pitgo
//
//  Validação/normalização brasileira reutilizada por `SignUp` (005) e `ProviderRegistration` (007).
//  `SignUpValidation` delega para cá sem alterar seu comportamento público (ver
//  specs/007-provider-registration/research.md §9). Autoridade final continua nos CHECKs do banco.
//

import Foundation

/// As 27 unidades federativas brasileiras (26 estados + Distrito Federal).
enum BrazilianState: String, CaseIterable, Hashable, Identifiable {
    case ac = "AC", al = "AL", ap = "AP", am = "AM", ba = "BA", ce = "CE", df = "DF", es = "ES"
    case go = "GO", ma = "MA", mt = "MT", ms = "MS", mg = "MG", pa = "PA", pb = "PB", pr = "PR"
    case pe = "PE", pi = "PI", rj = "RJ", rn = "RN", rs = "RS", ro = "RO", rr = "RR", sc = "SC"
    case sp = "SP", se = "SE", to = "TO"

    var id: String { rawValue }
}

enum BrazilianInputValidation {
    // MARK: - Normalization

    static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func digitsOnly(_ value: String) -> String {
        value.filter(\.isNumber)
    }

    static func normalizeEmail(_ value: String) -> String {
        trim(value).lowercased()
    }

    static func normalizeCPF(_ value: String) -> String {
        digitsOnly(value)
    }

    /// Alfanumérico vigente desde julho de 2026 — mantém dígitos e letras maiúsculas.
    static func normalizeCNPJ(_ value: String) -> String {
        value.uppercased().filter { $0.isNumber || ($0.isLetter && $0.isUppercase) }
    }

    // MARK: - Format validation

    static func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    /// 10 ou 11 dígitos com DDD brasileiro válido (11–99); celular de 11 dígitos exige "9" inicial.
    static func isValidBrazilianPhone(_ digits: String) -> Bool {
        guard digits.count == 10 || digits.count == 11 else { return false }
        guard let ddd = Int(digits.prefix(2)), (11...99).contains(ddd) else { return false }
        if digits.count == 11 {
            let firstDigit = digits[digits.index(digits.startIndex, offsetBy: 2)]
            guard firstDigit == "9" else { return false }
        }
        return true
    }

    /// CPF: 11 dígitos, rejeita sequências repetidas, valida os dois DVs por módulo 11.
    static func isValidCPF(_ digits: String) -> Bool {
        guard digits.count == 11, digits.allSatisfy(\.isNumber) else { return false }
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == 11 else { return false }
        if Set(values).count == 1 { return false } // sequência repetida (000.000.000-00 etc.)

        func checkDigit(_ base: [Int], weightsStart: Int) -> Int {
            var sum = 0
            var weight = weightsStart
            for digit in base {
                sum += digit * weight
                weight -= 1
            }
            let remainder = sum % 11
            return remainder < 2 ? 0 : 11 - remainder
        }

        let dv1 = checkDigit(Array(values[0..<9]), weightsStart: 10)
        guard dv1 == values[9] else { return false }
        let dv2 = checkDigit(Array(values[0..<10]), weightsStart: 11)
        return dv2 == values[10]
    }

    /// CNPJ: 14 caracteres — 12 iniciais `[0-9A-Z]` + 2 dígitos verificadores numéricos. Aceita
    /// tanto o formato legado (todo numérico) quanto o alfanumérico vigente desde julho de 2026,
    /// usando `ASCII - 48` para o valor de cada caractere na soma ponderada (regra oficial da
    /// Receita Federal).
    static func isValidCNPJ(_ value: String) -> Bool {
        guard value.count == 14 else { return false }
        let chars = Array(value)
        guard chars.allSatisfy({ $0.isNumber || ($0.isLetter && $0.isUppercase) }) else { return false }
        // Os dois dígitos verificadores são sempre numéricos.
        guard chars[12].isNumber, chars[13].isNumber else { return false }

        let asciiValues = chars.map { Int($0.asciiValue ?? 0) - 48 }

        func checkDigit(_ base: [Int], weights: [Int]) -> Int {
            let sum = zip(base, weights).reduce(0) { $0 + $1.0 * $1.1 }
            let remainder = sum % 11
            return remainder < 2 ? 0 : 11 - remainder
        }

        let dv1Weights = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
        let dv1 = checkDigit(Array(asciiValues[0..<12]), weights: dv1Weights)
        guard dv1 == asciiValues[12] else { return false }

        let dv2Weights = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
        let dv2 = checkDigit(Array(asciiValues[0..<12]) + [dv1], weights: dv2Weights)
        return dv2 == asciiValues[13]
    }

    /// CEP: exatamente oito dígitos (formato brasileiro — FR-005A de `007`).
    static func isValidCEP(_ digits: String) -> Bool {
        digits.count == 8 && digits.allSatisfy(\.isNumber)
    }
}
