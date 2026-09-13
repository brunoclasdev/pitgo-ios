//
//  SignUpValidation.swift
//  pitgo
//
//  Fachada fina sobre `BrazilianInputValidation`/`BrazilianTextFormatting` (extraídas em `007` para
//  reutilização real com `ProviderRegistration`, ver specs/007-provider-registration/research.md
//  §9). Normalização e validação continuam puramente locais (feedback imediato); a autoridade final
//  continua sendo os CHECKs já aplicados no banco compartilhado (`profiles_cpf_valid`/
//  `profiles_cnpj_valid`, ver contracts/profiles-schema.md).
//

import Foundation

enum SignUpValidation {
    // MARK: - Normalization

    static func trim(_ value: String) -> String {
        BrazilianInputValidation.trim(value)
    }

    static func digitsOnly(_ value: String) -> String {
        BrazilianInputValidation.digitsOnly(value)
    }

    static func normalizeEmail(_ value: String) -> String {
        BrazilianInputValidation.normalizeEmail(value)
    }

    /// CPF: mantém apenas dígitos. CNPJ: mantém dígitos/letras e força maiúsculas (alfanumérico
    /// vigente desde julho de 2026).
    static func normalizeDocument(_ value: String, personType: PersonType) -> String {
        switch personType {
        case .individual:
            BrazilianInputValidation.normalizeCPF(value)
        case .company:
            BrazilianInputValidation.normalizeCNPJ(value)
        }
    }

    // MARK: - Format validation

    static func isValidEmail(_ email: String) -> Bool {
        BrazilianInputValidation.isValidEmail(email)
    }

    static func isValidBrazilianPhone(_ digits: String) -> Bool {
        BrazilianInputValidation.isValidBrazilianPhone(digits)
    }

    static func isValidCPF(_ digits: String) -> Bool {
        BrazilianInputValidation.isValidCPF(digits)
    }

    static func isValidCNPJ(_ value: String) -> Bool {
        BrazilianInputValidation.isValidCNPJ(value)
    }

    // MARK: - Display formatting (mask applied on the raw/canonical value while editing)

    static func formatPhone(_ digits: String) -> String {
        BrazilianTextFormatting.formatPhone(digits)
    }

    static func formatCPF(_ digits: String) -> String {
        BrazilianTextFormatting.formatCPF(digits)
    }

    static func formatCNPJ(_ value: String) -> String {
        BrazilianTextFormatting.formatCNPJ(value)
    }
}
