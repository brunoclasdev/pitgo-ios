# Phase 1 Data Model: Mapa iOS em paridade de produção com o Android

Esta feature não introduz nem altera entidades de domínio, API ou persistência — é configuração de
build. O único "dado" relevante é a configuração de estilo do mapa, já modelada em `010`.

## Configuração de estilo do mapa (já existente, `010`)

Representada em runtime por `ManagedMapStyleConfiguration` (`pitgo/Core/Map/Config/`), sem mudança
de forma nesta feature:

| Campo | Tipo | Origem (Build Setting) | Origem (`Info.plist`) |
|---|---|---|---|
| `styleURL` | `URL` (HTTPS absoluta) | `mapStyleUrl` | `MAP_STYLE_URL` |
| `providerName` | `String` (não vazio) | `mapStyleProviderName` | `MAP_PROVIDER_NAME` |
| `attribution` | `String` (não vazio) | `mapStyleAttribution` | `MAP_PROVIDER_ATTRIBUTION` |
| `attributionURL` | `URL?` (HTTPS absoluta) | `mapStyleAttributionUrl` | `MAP_PROVIDER_ATTRIBUTION_URL` |

**Mudança desta feature**: os *valores* passam do default de avaliação (`demotiles.maplibre.org`)
para os valores de produção usados pelo Android, definidos em `Config/Secrets.xcconfig` (local, não
rastreado). Nenhum campo é adicionado, removido ou tem seu tipo alterado.

## Regra de validação de build (nova nesta feature)

Não é uma entidade em runtime — é uma regra aplicada uma única vez, em tempo de build, pelo Run
Script Build Phase estendido. Modelada aqui apenas para deixar explícito o que cada campo aceita/
rejeita (grammar já definida em `specs/010-osm-realtime-map/contracts/maplibre-style-runtime.md`,
implementada agora):

| Campo | Aceita | Rejeita (build falha) |
|---|---|---|
| `mapStyleUrl` | HTTPS absoluta, sem user-info/fragment, host gerenciado | vazio; `http://`; sem host; user-info; fragment; host demo/público conhecido (`demotiles.maplibre.org`, `tile.openstreetmap.org` e subdomínios) |
| `mapStyleProviderName` | texto não vazio | vazio ou só espaços |
| `mapStyleAttribution` | texto não vazio | vazio ou só espaços |
| `mapStyleAttributionUrl` | HTTPS absoluta, sem user-info/fragment | vazio; `http://`; sem host; user-info; fragment |

A mensagem de falha cita o nome do campo e a regra violada, nunca o valor recebido (mesmo padrão de
`validate-supabase-config.sh` para `supabaseUrl`/`supabaseKey`).
