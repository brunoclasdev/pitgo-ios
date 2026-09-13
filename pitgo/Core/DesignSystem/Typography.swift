//
//  Typography.swift
//  pitgo
//
//  Estilos de texto baseados nos text styles nativos do sistema (Dynamic Type), nunca em tamanhos
//  fixos, para escalar corretamente com a configuração de acessibilidade do usuário.
//

import SwiftUI

enum PitGoTypography {
    static let sectionTitle: Font = .system(.title2, design: .rounded).weight(.bold)
    static let categoryTitle: Font = .system(.headline, design: .rounded).weight(.semibold)
    static let body: Font = .system(.body)
    static let caption: Font = .system(.caption)
}
