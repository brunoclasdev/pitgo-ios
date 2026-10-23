//
//  EnvironmentConfig.swift
//  pitgo
//
//  `027` (porte do app Android): identifica o ambiente ativo (`DEV`/`HOMOL`/`PROD`) a partir de
//  `ENVIRONMENT_ID`, exposto via Info.plist pelo build setting homônimo definido em
//  Config/Dev.xcconfig/Homol.xcconfig/Prod.xcconfig (mesmo padrão de `ManagedMercadoPagoConfiguration`/
//  `ManagedMapStyleConfiguration`). Só Dev usa pagamento simulado — Homol e Prod compartilham o
//  mesmo backend e a mesma integração Mercado Pago (ver Homol.xcconfig).
//

import Foundation

enum EnvironmentID: String {
    case dev = "DEV"
    case homol = "HOMOL"
    case prod = "PROD"
}

enum PaymentMode {
    case simulated
    case integrated
}

struct EnvironmentConfig {
    let id: EnvironmentID
    let paymentMode: PaymentMode
    /// Texto curto para diagnóstico em tela (Perfil) — nunca inclui URL, chave ou token (FR-003/FR-012).
    let label: String
    /// Usado só para detectar troca de ambiente no mesmo dispositivo (`EnvironmentStateRepository`)
    /// — nunca exibido, nunca enviado a um servidor.
    let fingerprint: String

    var simulated: Bool { paymentMode == .simulated }

    /// Ambiente desconhecido ou ausente (ex.: Info.plist corrompido) cai em `.prod` com pagamento
    /// integrado — nunca em `.dev`/simulado, que seria a direção insegura de uma falha silenciosa.
    static let current: EnvironmentConfig = {
        let rawID = (Bundle.main.object(forInfoDictionaryKey: "ENVIRONMENT_ID") as? String)?
            .trimmingCharacters(in: .whitespaces).uppercased()
        let id = rawID.flatMap(EnvironmentID.init(rawValue:)) ?? .prod
        let paymentMode: PaymentMode = id == .dev ? .simulated : .integrated
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let projectRef = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PROJECT_REF") as? String) ?? ""
        return EnvironmentConfig(
            id: id,
            paymentMode: paymentMode,
            label: "\(id.rawValue.lowercased()) • \(version)",
            fingerprint: "\(id.rawValue):\(projectRef):1"
        )
    }()
}

/// `027` FR-003/SC-007: exibido em `ProfileView` — texto curto o bastante para a pessoa de QA
/// distinguir o ambiente em até 10 segundos, nunca uma URL/chave/token.
enum EnvironmentDiagnostics {
    static var label: String {
        let mode = EnvironmentConfig.current.simulated ? "simulado" : "integrado"
        return "\(EnvironmentConfig.current.label) • \(mode)"
    }
}
