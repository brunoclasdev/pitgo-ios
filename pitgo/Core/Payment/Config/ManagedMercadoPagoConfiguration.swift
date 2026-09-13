//
//  ManagedMercadoPagoConfiguration.swift
//  pitgo
//
//  Leitura central da Public Key do Mercado Pago, exposta via `Info.plist` (mesmo padrão de
//  `ManagedMapStyleConfiguration`, `010`). Diferente do mapa, NÃO existe um default de avaliação
//  aqui: uma Public Key inventada falharia de forma confusa dentro do SDK nativo do Mercado Pago
//  (tokenização exige uma chave real de uma aplicação cadastrada). Ausência de chave é modelada como
//  `current == nil` — o app trata isso como "pagamento por cartão indisponível", nunca como uma
//  simulação silenciosa. Pix não depende desta chave (é gerado inteiramente no backend).
//

import Foundation

struct ManagedMercadoPagoConfiguration {
    let publicKey: String

    static let current: ManagedMercadoPagoConfiguration? = {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "MERCADO_PAGO_PUBLIC_KEY") as? String,
            !value.isEmpty
        else {
            return nil
        }
        return ManagedMercadoPagoConfiguration(publicKey: value)
    }()
}
