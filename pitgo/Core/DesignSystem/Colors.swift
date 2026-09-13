//
//  Colors.swift
//  pitgo
//
//  Paleta de marca do PitGo. Os mesmos valores hexadecimais do app Android
//  (core/design/theme/Color.kt) são reaproveitados aqui para manter paridade visual entre as
//  duas plataformas sobre o mesmo produto.
//

import SwiftUI

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

enum PitGoPalette {
    static let brandPurple = Color(hex: 0x7C32E8)
    static let darkPurple = Color(hex: 0x5520A8)
    static let purpleContainerLight = Color(hex: 0xEFE6FC)
    static let purpleContainerDark = Color(hex: 0x3D2860)

    static let lightBackground = Color(hex: 0xFAF9FD)
    static let white = Color(hex: 0xFFFFFF)
    static let textPrimary = Color(hex: 0x17151D)
    static let textSecondary = Color(hex: 0x6F6B78)

    static let darkBackground = Color(hex: 0x100E13)
    static let darkSurface = Color(hex: 0x1B1821)
    static let darkSurfaceVariant = Color(hex: 0x29252F)
    static let darkTextPrimary = Color(hex: 0xF7F2FA)
    static let darkTextSecondary = Color(hex: 0xCAC4D0)

    static let outlineLight = Color(hex: 0xE2DDE7)
    static let outlineDark = Color(hex: 0x938F99)
}
