# Phase 0 Research: Mapa OSM com MapLibre e atualização em tempo real (iOS)

## 0. Backend compartilhado — hardening já aplicado

**Decision**: reutilizar a migration de hardening do stream de localização
(`20260821030000_appointment_location_stream_hardening.sql`, já aplicada pela feature Android
equivalente) sem alteração: outcomes fechados `EMPTY`/`LIVE`/`STALE`/`ENDED`, autorização de
participante independente de status terminal, Broadcast privado `ENDED` e remoção da posição
corrente ao término, sem histórico. Nenhuma migration nova é criada por esta feature iOS.

**Rationale**: mesmo racional de `009 §0` — o hardening corrige bugs de ordenação/observabilidade
do stream Realtime, uma propriedade de backend independente da plataforma cliente.

## 1. SDK e integração iOS

**Decision**: usar o Swift Package `MapLibre` (produto de `maplibre/maplibre-native-distribution` ou
o pacote SPM oficial equivalente resolvido para iOS), já indicado na constitution do projeto desde
`009-provider-location-accounts`. Diferente do Android (que precisou escolher explicitamente entre
backend gráfico OpenGL/Vulkan), o binding iOS da MapLibre Native expõe uma única API pública
(`MLNMapView`) sem essa escolha de backend gráfico exposta ao app — o Metal/OpenGL ES interno é
detalhe de implementação do próprio SDK nessa plataforma.

**Rationale**: mesma biblioteca open-source do Android, mantendo o mesmo provedor de tiles
self-hosted e o mesmo Style JSON entre plataformas (decisão já tomada na constitution, não
revisitada aqui).

**Alternatives considered**: `MapKit` nativo com `MKTileOverlay` customizado, rejeitado pela mesma
razão já registrada em `009 research.md §7` (consistência de fornecedor/Style JSON entre Android e
iOS pesa mais que zero-dependência); MapLibre Compose (não aplicável ao iOS, é um wrapper Android).

## 2. Integração SwiftUI e lifecycle nativo

**Decision**: encapsular `MLNMapView` (UIKit) num `UIViewRepresentable` (`MapLibreMapHost`), análogo
direto ao `AndroidView<MapView>` do Android. `makeUIView` cria o `MLNMapView` uma vez, define o
`styleURL` a partir de `ManagedMapStyleConfiguration` (ver §3) e registra o `delegate`
(`MLNMapViewDelegate`) para os callbacks de estilo/erro. `updateUIView` só encaminha o modelo de
dados mais recente e comandos de câmera novos (via uma `revision` incremental, mesmo padrão do
Android) — nunca recria a `MLNMapView` nem reaplica a câmera a cada atualização de estado. O
`Coordinator` do `UIViewRepresentable` guarda o `delegate` e as sources/layers instaladas,
equivalente ao pequeno "controller" que o Android usa por tela.

**Rationale**: `UIViewRepresentable` é o mecanismo oficial do SwiftUI para hospedar uma `UIView`
UIKit — o equivalente iOS exato ao papel do `AndroidView` no Compose. Manter viewport como estado do
ViewModel (não do `Coordinator`) evita depender do ciclo de vida da View SwiftUI e preserva Mapa/
Lista entre recomposições, mesmo racional do Android.

**Alternatives considered**: reimplementar a UI do mapa em SwiftUI puro, inviável — MapLibre não tem
uma API SwiftUI nativa; guardar a `MLNMapView` no ViewModel, rejeitado por vazar UIKit para a camada
de domínio (viola MVVM); recriar a `MLNMapView` a cada atualização, rejeitado por produzir flicker e
perder câmera/recursos instalados.

## 3. Estilo gerenciado e fronteira de configuração

**Decision**: mesmo contrato do Android — `mapStyleUrl`, `mapStyleProviderName`,
`mapStyleAttribution` e `mapStyleAttributionUrl`, obrigatórios, validados em tempo de build (Run
Script Build Phase, mesmo mecanismo de `004-configure-supabase`) e expostos via `Info.plist`
(`MAP_STYLE_URL`, `MAP_PROVIDER_NAME`, `MAP_PROVIDER_ATTRIBUTION`, `MAP_PROVIDER_ATTRIBUTION_URL`),
lidos por `Bundle.main.object(forInfoDictionaryKey:)` — mesmo padrão já estabelecido para
`SUPABASE_URL`/`SUPABASE_KEY` em `004`.

**Rationale**: idêntico ao racional do Android — um Style JSON referencia tiles/sprites/glyphs; um
template isolado não descreve esse grafo. A validação de build (HTTPS absoluta, sem user-info/
fragment/placeholder, host não é um endpoint demo/público) já é o mesmo mecanismo de
`validate-supabase-config.sh`, estendido com uma segunda seção de campos.

**Alternatives considered**: idênticas ao Android — fixar fornecedor no código (inventaria decisão
não dada); baixar/reescrever o Style JSON no momento do build (I/O instável, risco de vazar token);
proxy de tiles via Edge Function (latência/custo desnecessários para uma credencial móvel
publicável); fallback para endpoint demo público (viola FR-004).

## 4. Carregamento, recursos, cache e atribuição

**Decision**: modelar estilo e recursos separadamente (`MapStyleState`, `MapResourceState`, ver
`data-model.md`), usando os callbacks do `MLNMapViewDelegate`
(`mapView(_:didFinishLoading:)`/`mapView(_:didFailToLoadMapWithError:)`) para o estilo e observando
falhas de tile/sprite/glyph reportadas pelo SDK para degradação. Um `NWPathMonitor`
(`Network.framework`) substitui o `ConnectivityObserver` baseado em `ConnectivityManager` do Android,
com a mesma semântica `online|offline`. Retry reaplica o mesmo `styleURL` na mesma `MLNMapView` e
reinstala sources/layers/imagens com o modelo mais recente — nunca recria a View.

**Rationale**: idêntico ao racional do Android — `setStyle` é assíncrono e uma troca destrói as
camadas em runtime; o callback precisa ser idempotente e ler o modelo mais recente, impedindo um
callback antigo de ressuscitar um marcador privado após `Ended`/perda de sessão. `NWPathMonitor` é o
equivalente nativo iOS ao `ConnectivityManager.NetworkCallback` do Android — ambos observam
conectividade sem polling.

**Alternatives considered**: idênticas ao Android — recriar a `MLNMapView` perde câmera/recursos;
limpar o cache do SDK destrói o fallback; um `Bool` único mistura estilo/tiles/dados/rede; expor o
erro nativo bruto pode conter URL/token; confiar somente na atribuição desenhada dentro do mapa
reduz acessibilidade (VoiceOver não alcança conteúdo desenhado no canvas do mapa).

## 5. Providers, clustering e seleção

**Decision**: converter providers válidos numa `MLNShapeSource` (GeoJSON) em memória com clustering
nativo (`shouldCluster: true`, `clusterRadius`, `maximumZoomLevelForClustering` no
`MLNShapeSourceOptions`), camadas de cluster/contagem/provider (`MLNCircleStyleLayer`/
`MLNSymbolStyleLayer`) e seleção data-driven via `mapView(_:didSelect:)`. Coordenadas exatamente
iguais são pré-agrupadas por uma chave estável antes de montar o GeoJSON — mesma estratégia do
Android.

**Rationale**: idêntico ao racional do Android — uma única source atualizável atende até 200
resultados sem annotations individuais; toque consulta apenas as layers da própria app; a lista
textual continua completa e autoritativa para acessibilidade.

**Alternatives considered**: idênticas ao Android — `MLNPointAnnotation`s individuais escalam pior e
não resolvem overlap; grade customizada duplicaria o clustering nativo do SDK; embutir detalhes
públicos (nome, preço) diretamente nas propriedades GeoJSON duplicaria estado e ampliaria exposição
— só `id`, `kind`, `selected` e `groupKey` (propriedades opacas) entram no GeoJSON.

## 6. Marcador Realtime

**Decision**: uma `MLNShapeSource` separada, sem clustering, contendo no máximo um `MLNPointFeature`.
Cada posição aceita chama apenas `source.shape = updatedFeatureCollection` (equivalente direto ao
`GeoJsonSource.setGeoJson` do Android); uma propriedade `kind = LIVE|STALE` escolhe ícone/semântica
via `MLNSymbolStyleLayer` com `text`/`iconImage` data-driven.

**Rationale**: idêntico ao racional do Android — atualização incremental mantém a `MLNMapView`,
estilo, source e layer intactos; ordenação e recência continuam inteiramente no ViewModel (a mesma
lógica de `LocationRevision`/tombstone do backend hardening), nunca no renderer.

**Alternatives considered**: idênticas ao Android — recriar marcador/estilo causa flicker; animação/
interpolação sugeriria uma rota não observada; usar o indicador nativo de "localização do usuário"
do MapLibre publicaria a posição do próprio dispositivo, não a do provider remoto.

## 7. UI acessível e navegação

**Decision**: manter a alternância Mapa/Lista, um resumo SwiftUI (`.sheet`/painel lateral conforme
`horizontalSizeClass`) e CTA por IDs opacos. O mapa é uma região semântica (`.accessibilityElement`
com rótulo próprio); controles, lista e sheet são SwiftUI nativos e formam a árvore VoiceOver
autoritativa — features dentro do renderer MapLibre não formam uma árvore de acessibilidade
confiável, mesmo problema estrutural do Android com TalkBack. `PitGoRoute.serviceMap(serviceID:)` e
o resumo aceitam apenas `serviceID`/`providerID` opacos; `RequestServiceView` (`003`) precisa aceitar
o UUID real do catálogo e o `providerID`, já que o contrato demo atual não representa o provider
selecionado.

**Rationale**: idêntico ao racional do Android — InfoWindow/callout nativo como única UI prejudicaria
a acessibilidade; passar nome/preço pela rota duplicaria a fonte de verdade.

## 8. Stream Realtime, ordenação e encerramento

**Decision**: `AppointmentTrackingRepository` (`009`, agora endurecido) mantém eventos explícitos e
revisão `(publishedAt, version)` — mesma comparação lexicográfica do Android — inicia a assinatura
do canal antes do snapshot, emite `.snapshot(nil)` explicitamente, interpreta `DELETE` como
tombstone e remove o canal dentro de um `Task` com prioridade que sobrevive ao cancelamento do
escopo pai (equivalente ao `NonCancellable` do Kotlin — em Swift Concurrency isso é obtido isolando a
chamada de remoção do canal numa `Task` própria, desacoplada do `Task` de UI que pode ser
cancelado).

**Rationale**: a troca/adição de renderer não corrige os bugs do stream em si — o hardening (§0,
backend compartilhado) já resolve snapshot vazio preso em loading, janela de perda no subscribe,
regressão de versão e reconexão terminal indistinguível de erro. O client só precisa consumir o
contrato já corrigido corretamente.

## 9. Escopo e limites

**Decision**: nenhuma remoção é necessária no iOS (não havia Google Maps/osmdroid a remover); a
única dependência de mapa do projeto continua sendo MapLibre Native iOS, adicionada nesta feature.
`CLLocationManager` (posição do dispositivo, de `009`) e as Edge Functions de geocodificação
permanecem inalteradas e fora do escopo desta feature.

**Rationale**: idêntico ao racional do Android — uma única dependência de mapa evita renderizadores
concorrentes e cumpre o requisito de produto (FR-002); geocodificação é server-side e explicitamente
fora do escopo desta feature.
