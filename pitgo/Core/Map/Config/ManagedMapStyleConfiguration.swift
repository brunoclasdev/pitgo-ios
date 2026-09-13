//
//  ManagedMapStyleConfiguration.swift
//  pitgo
//
//  Leitura central e imutável dos quatro campos do estilo de mapa gerenciado, expostos via
//  `Info.plist` (ver contracts/maplibre-style-runtime.md "Build boundary" de `010`). Substitui
//  `MapStyleProvider` (`009`, campo único). Nunca registra URL/token em log — somente
//  `ManagedMapStyleConfiguration.current` lê estas chaves.
//
//  NOTA (escopo, ver tasks.md `010`): o Run Script de validação (`004`/
//  `Scripts/validate-supabase-config.sh`) não foi estendido para rejeitar hosts demo/públicos
//  (`demotiles.maplibre.org`) porque este é justamente o default de avaliação já documentado em
//  `Config/Shared.xcconfig` (`009`) — sem uma credencial real de provedor de tiles gerenciado nesta
//  sessão, endurecer esse gate quebraria o único build local/CI existente. `providerName`/
//  `attribution`/`attributionURL` têm defaults textuais verdadeiros para o estilo de avaliação
//  (créditos reais do MapLibre/OSM), não um placeholder fabricado.
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
