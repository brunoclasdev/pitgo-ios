//
//  ManagedMapStyleConfiguration.swift
//  pitgo
//
//  Leitura central e imutável dos quatro campos do estilo de mapa gerenciado, expostos via
//  `Info.plist` (ver contracts/maplibre-style-runtime.md "Build boundary" de `010`). Substitui
//  `MapStyleProvider` (`009`, campo único). Nunca registra URL/token em log — somente
//  `ManagedMapStyleConfiguration.current` lê estas chaves.
//
//  NOTA (desde `019`): o Run Script de validação (`004`/`Scripts/validate-supabase-config.sh`)
//  agora também rejeita hosts demo/públicos conhecidos (`demotiles.maplibre.org`,
//  `tile.openstreetmap.org`) para `mapStyleUrl`, além de campo ausente/placeholder — build de
//  produção sem uma configuração de mapa real não compila. O fallback `evaluationFallback` abaixo
//  deixa de ser alcançável em qualquer build que passe por essa validação; ele permanece só como
//  rede de segurança em runtime (não é o mecanismo que garante ausência do estilo de demonstração
//  em produção — o Run Script é). `providerName`/`attribution`/`attributionURL` do fallback têm
//  defaults textuais verdadeiros para o estilo de avaliação (créditos reais do MapLibre/OSM), não
//  um placeholder fabricado.
//

import Foundation

struct ManagedMapStyleConfiguration {
    let styleURL: URL
    let providerName: String
    let attribution: String
    let attributionURL: URL?

    /// Default público de avaliação do MapLibre — nunca usado como infraestrutura de produção (ver
    /// research.md §7 de `009`).
    private static let evaluationFallback = ManagedMapStyleConfiguration(
        styleURL: URL(string: "https://demotiles.maplibre.org/style.json")!,
        providerName: "MapLibre (estilo de avaliação)",
        attribution: "© OpenStreetMap contributors",
        attributionURL: URL(string: "https://www.openstreetmap.org/copyright")
    )

    static let current: ManagedMapStyleConfiguration = {
        guard
            let styleURLValue = Bundle.main.object(forInfoDictionaryKey: "MAP_STYLE_URL") as? String,
            !styleURLValue.isEmpty,
            let styleURL = URL(string: styleURLValue)
        else {
            return evaluationFallback
        }

        let providerName = (Bundle.main.object(forInfoDictionaryKey: "MAP_PROVIDER_NAME") as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? evaluationFallback.providerName

        let attribution = (Bundle.main.object(forInfoDictionaryKey: "MAP_PROVIDER_ATTRIBUTION") as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? evaluationFallback.attribution

        let attributionURL = (Bundle.main.object(forInfoDictionaryKey: "MAP_PROVIDER_ATTRIBUTION_URL") as? String)
            .flatMap { URL(string: $0) } ?? evaluationFallback.attributionURL

        return ManagedMapStyleConfiguration(
            styleURL: styleURL,
            providerName: providerName,
            attribution: attribution,
            attributionURL: attributionURL
        )
    }()
}
