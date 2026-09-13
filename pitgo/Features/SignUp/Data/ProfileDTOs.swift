//
//  ProfileDTOs.swift
//  pitgo
//
//  DTO `Codable` para `public.profiles` (schema já existente, ver contracts/profiles-schema.md).
//  Nunca exposto à View — o Repository é a única fronteira que o manipula. Desde
//  `006-auth-vehicle-registration`, o cadastro não insere/upserta perfil (apenas o trigger de banco
//  cria a linha), então não há mais um DTO de insert aqui.
//

import Foundation

struct ProfileDTO: Decodable {
    let id: UUID
    let name: String
    let email: String
    let phone: String
    let cpf: String?
    let cnpj: String?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, email, phone, cpf, cnpj
        case isActive = "active"
    }
}
