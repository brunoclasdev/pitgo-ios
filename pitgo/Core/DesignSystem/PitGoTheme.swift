//
//  PitGoTheme.swift
//  pitgo
//
//  Tokens de cor semânticos por tema. O tema escuro NÃO é uma inversão automática do claro — cada
//  um define sua própria paleta (ver Colors.swift), conforme a constituição do app. Esta feature
//  respeita apenas `colorScheme` do sistema; um seletor manual (Claro/Escuro/Padrão do sistema)
//  pertence a uma feature futura.
//

import SwiftUI

struct PitGoColorTokens {
    let accent: Color
    let background: Color
    let surface: Color
    /// Superfície de destaque roxo-claro (ex.: card de diagnóstico); mais clara que `background`
    /// em ambos os temas, nunca uma cor sólida hardcoded fora do design system.
    let purpleContainer: Color
    let textPrimary: Color
    let textSecondary: Color
    let outline: Color

    static let light = PitGoColorTokens(
        accent: PitGoPalette.brandPurple,
        background: PitGoPalette.lightBackground,
        surface: PitGoPalette.white,
        purpleContainer: PitGoPalette.purpleContainerLight,
        textPrimary: PitGoPalette.textPrimary,
        textSecondary: PitGoPalette.textSecondary,
        outline: PitGoPalette.outlineLight
    )

    static let dark = PitGoColorTokens(
        accent: PitGoPalette.darkPurple,
        background: PitGoPalette.darkBackground,
        surface: PitGoPalette.darkSurface,
        purpleContainer: PitGoPalette.purpleContainerDark,
        textPrimary: PitGoPalette.darkTextPrimary,
        textSecondary: PitGoPalette.darkTextSecondary,
        outline: PitGoPalette.outlineDark
    )
}

private struct PitGoTokensKey: EnvironmentKey {
    static let defaultValue = PitGoColorTokens.light
}

extension EnvironmentValues {
    var pitGoTokens: PitGoColorTokens {
        get { self[PitGoTokensKey.self] }
        set { self[PitGoTokensKey.self] = newValue }
    }
}

private struct PitGoThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let tokens = colorScheme == .dark ? PitGoColorTokens.dark : PitGoColorTokens.light
        content
            .environment(\.pitGoTokens, tokens)
            .tint(tokens.accent)
            .background(tokens.background.ignoresSafeArea())
    }
}

extension View {
    /// Aplica os tokens de cor do PitGo (claro/escuro) e o acento roxo de marca à subárvore.
    func pitGoTheme() -> some View {
        modifier(PitGoThemeModifier())
    }
}
