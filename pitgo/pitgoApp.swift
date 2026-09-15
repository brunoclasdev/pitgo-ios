//
//  pitgoApp.swift
//  pitgo
//
//  Created by Bruno César on 12/09/26.
//

import CoreMethods
import SwiftUI

@main
struct pitgoApp: App {
    @StateObject private var sessionStore = SessionStore(client: SupabaseClientProvider.client)
    @AppearancePreference private var appearance

    init() {
        // `018`: só inicializa o SDK nativo do Mercado Pago quando há uma Public Key real
        // configurada (`Config/Secrets.xcconfig`) — sem ela, `PaymentMethodsView` mostra cadastro de
        // cartão indisponível em vez de chamar um SDK sem chave (que travaria em `assert`, ver
        // `ManagedMercadoPagoConfiguration`). Pix não depende disto.
        if let configuration = ManagedMercadoPagoConfiguration.current {
            MercadoPagoSDK.shared.initialize(
                MercadoPagoSDK.Configuration(publicKey: configuration.publicKey, country: .BRA)
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            PitGoRootView(client: SupabaseClientProvider.client)
                .environmentObject(sessionStore)
                .task { sessionStore.start() }
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}
