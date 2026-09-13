//
//  AppearancePreferences.swift
//  pitgo
//
//  Preferência de aparência do app (`014` FR-008) — Claro/Escuro/Padrão do sistema, persistida
//  localmente via `@AppStorage`. Não é um dado de conta (não sincroniza entre dispositivos); a
//  constituição do produto já previa esta opção, esta feature só a torna acessível no Perfil.
//

import SwiftUI

enum AppAppearance: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var label: String {
        switch self {
        case .system: "Padrão do sistema"
        case .light: "Claro"
        case .dark: "Escuro"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@propertyWrapper
struct AppearancePreference: DynamicProperty {
    @AppStorage("pitgo.appearance") private var rawValue: String = AppAppearance.system.rawValue

    var wrappedValue: AppAppearance {
        get { AppAppearance(rawValue: rawValue) ?? .system }
        nonmutating set { rawValue = newValue.rawValue }
    }

    var projectedValue: Binding<AppAppearance> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}
