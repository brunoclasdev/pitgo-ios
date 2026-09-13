//
//  MapAttributionView.swift
//  pitgo
//
//  Ação SwiftUI acessível adicional de atribuição — o SDK já mantém `mapView.attributionButton`
//  nativo habilitado (contracts/maplibre-style-runtime.md "Cache and attribution" de `010`); este
//  controle garante que o crédito OSM/provedor permaneça legível e tocável mesmo quando um card/
//  sheet cobre parte do mapa.
//

import SwiftUI

struct MapAttributionView: View {
    @Environment(\.openURL) private var openURL
    private let configuration = ManagedMapStyleConfiguration.current

    var body: some View {
        Button(action: {
            if let url = configuration.attributionURL {
                openURL(url)
            }
        }) {
            Text(configuration.attribution)
                .font(PitGoTypography.caption)
                .underline(configuration.attributionURL != nil)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityLabel("Atribuição do mapa: \(configuration.attribution)")
    }
}
