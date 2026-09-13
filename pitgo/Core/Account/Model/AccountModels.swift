//
//  AccountModels.swift
//  pitgo
//
//  Projeção de `public.profiles` (schema já existente, ver contracts/supabase.md) e o snapshot
//  autorizado de conta. CPF/CNPJ nunca são exibidos nesta feature.
//

import Foundation

struct Profile: Decodable {
    let id: UUID
    let name: String
    let email: String
    let phone: String
    let cpf: String?
    let cnpj: String?
    let avatarURL: URL?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, email, phone, cpf, cnpj
        case avatarURL = "avatar_url"
        case isActive = "active"
    }

    var displayName: String { name.trimmingCharacters(in: .whitespaces) }

    var initials: String {
        let words = displayName.split(separator: " ").filter { !$0.isEmpty }
        let letters = words.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}

/// Identidade, perfil e veículo principal validados — a única fonte de dados privados renderizáveis
/// (ver `AppSessionState.authenticatedClient`).
struct AccountSnapshot {
    let userID: UUID
    let authEmail: String
    let profile: Profile
    var primaryVehicle: Vehicle?
    /// `true` quando este profile possui uma empresa legada (modelo anterior a `009`) pendente de
    /// migração assistida (ver `AccountContext.legacyProviderMigrationAvailable`). `false` quando o
    /// snapshot é construído fora do fluxo de `AccountContextRepository` (ex.: `HomeViewModel`, que
    /// não usa esse dado).
    var legacyProviderMigrationAvailable: Bool = false
}
