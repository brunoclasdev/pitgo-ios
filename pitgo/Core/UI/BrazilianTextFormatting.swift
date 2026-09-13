//
//  BrazilianTextFormatting.swift
//  pitgo
//
//  Máscaras visuais aplicadas ao valor canônico ao editar (sem `OffsetMapping` — dígitos puros no
//  estado, máscara recomputada no `onChange`, ver specs/007-provider-registration/research.md §9).
//  Reutilizada por `SignUp` (005, via `SignUpValidation`) e `ProviderRegistration` (007).
//

import Foundation

enum BrazilianTextFormatting {
    static func formatPhone(_ digits: String) -> String {
        let d = Array(digits.prefix(11))
        guard !d.isEmpty else { return "" }
        var result = "("
        for (index, char) in d.enumerated() {
            if index == 2 { result += ") " }
            if d.count == 11, index == 7 { result += "-" }
            if d.count == 10, index == 6 { result += "-" }
            result.append(char)
        }
        return result
    }

    static func formatCPF(_ digits: String) -> String {
        let d = Array(digits.prefix(11))
        var result = ""
        for (index, char) in d.enumerated() {
            if index == 3 || index == 6 { result += "." }
            if index == 9 { result += "-" }
            result.append(char)
        }
        return result
    }

    static func formatCNPJ(_ value: String) -> String {
        let d = Array(value.prefix(14))
        var result = ""
        for (index, char) in d.enumerated() {
            if index == 2 || index == 5 { result += "." }
            if index == 8 { result += "/" }
            if index == 12 { result += "-" }
            result.append(char)
        }
        return result
    }

    /// CEP: `12345-678`.
    static func formatCEP(_ digits: String) -> String {
        let d = Array(digits.prefix(8))
        var result = ""
        for (index, char) in d.enumerated() {
            if index == 5 { result += "-" }
            result.append(char)
        }
        return result
    }
}
