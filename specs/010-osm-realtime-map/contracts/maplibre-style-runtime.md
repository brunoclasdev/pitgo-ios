# Contract: MapLibre Style Runtime (iOS)

## Build boundary

Todas as configurações (Debug/Release) exigem, via `Info.plist` + Build Settings (mesmo mecanismo de
`004-configure-supabase`):

| Chave `Info.plist` | Build Setting | Validação |
|---|---|---|
| `MAP_STYLE_URL` | `mapStyleUrl` | HTTPS absoluta; sem user-info, fragment ou placeholder |
| `MAP_PROVIDER_NAME` | `mapStyleProviderName` | texto público não vazio |
| `MAP_PROVIDER_ATTRIBUTION` | `mapStyleAttribution` | crédito OSM e do provedor, não vazio |
| `MAP_PROVIDER_ATTRIBUTION_URL` | `mapStyleAttributionUrl` | HTTPS absoluta |

Fontes aceitas: `Config/Secrets.xcconfig` local (não rastreado, de `004`) e override de CI via
`-xcconfig`. Exemplo sem valor real:

```text
mapStyleUrl = https:/$()/<managed-provider>/<style>.json?key=<client-token>
mapStyleProviderName = <provider-name>
mapStyleAttribution = © OpenStreetMap contributors · <provider-credit>
mapStyleAttributionUrl = https:/$()/<provider-attribution-page>
```

(A sintaxe `/$()/` escapa `//` em arquivos `.xcconfig`, conforme já documentado em
`004-configure-supabase/quickstart.md`.)

### Falhas obrigatórias

O Run Script Build Phase de validação (estendido do de `004`) falha sem ecoar valores quando um
campo estiver ausente/em branco, a URL não for HTTPS absoluta, existir user-info/fragment/
placeholder, ou o host conhecido for um endpoint demo/público não gerenciado. Uma fonte de maior
precedência inválida não cai silenciosamente para outra.

O build não baixa o Style JSON. CI/pre-release deve inspecionar manualmente o estilo escolhido e
confirmar: sources, TileJSON, sprites e glyphs em HTTPS e autorizados pelo provedor; atribuição
correta em cada source; token móvel publicável/restrito; ausência de `tile.openstreetmap.org`,
demotiles ou credencial administrativa.

`Info.plist` expõe os quatro campos resolvidos; somente `ManagedMapStyleConfiguration` os lê.

## Dependency boundary

- Adicionar o Swift Package `MapLibre` (produto `MapLibre`) ao target `pitgo`.
- Nenhum outro SDK de mapa (`MapKit` com terceiros, Google Maps para iOS, etc.) é adicionado nesta
  feature nem mantido como fallback.
- `CLLocationManager` (posição do dispositivo, de `009`), `supabase-swift` e as Edge Functions de
  geocodificação permanecem inalterados.
- A revisão de dependências do projeto (`File > Packages > Resolve Package Versions` / inspeção do
  `Package.resolved`) deve provar uma única dependência de renderização de mapa.

## Runtime initialization and lifecycle

Cada `MapLibreMapHost` (`UIViewRepresentable`):

1. cria uma `MLNMapView` em `makeUIView`, define `styleURL` a partir de
   `ManagedMapStyleConfiguration`;
2. registra o `MLNMapViewDelegate` (no `Coordinator`) antes de o estilo carregar;
3. o `UIViewRepresentable` já delega o ciclo de vida da `UIView` ao próprio UIKit/SwiftUI — não há
   callbacks manuais de `onStart/onResume/onPause/onStop` a encaminhar, diferente do Android (o
   sistema gerencia isso automaticamente para qualquer `UIView` hospedada);
4. aplica `updateUIView` somente quando mapa/estilo estiverem prontos, usando a `revision` mais
   recente do modelo;
5. `dismantleUIView` remove o delegate/observadores; a `MLNMapView` é liberada pelo ARC quando a
   `View` sai da hierarquia — nenhum `onDestroy` manual é necessário;
6. nunca expõe `MLNMapView`/`MLNStyle`/`CLLocationCoordinate2D` a ViewModel ou Repository.

Câmera programática só aplica uma `revision` nova. Gestos atualizam o viewport sem serem
sobrescritos por uma atualização de estado do SwiftUI.

## Style and layer lifecycle

- `mapView.styleURL = ...` é assíncrono (equivalente ao `setStyle` do Android).
- Ao carregar (`mapView(_:didFinishLoading:)`), o `Coordinator` reinstala idempotentemente imagens,
  `MLNShapeSource`s e layers.
- O `Coordinator` sempre publica o `latestRenderModel` do ViewModel, não o modelo capturado quando a
  requisição de estilo começou.
- Retry incrementa a `revision` e reaplica o mesmo `styleURL` na mesma `MLNMapView`.
- Retry não limpa providers, seleção, câmera, posição autorizada ou o cache padrão do SDK.
- Um callback antigo/atrasado não pode vencer uma revisão mais nova nem restaurar um marcador após
  `Ended`/sessão expirada.

## Resource state

- Estilo começou a carregar: `.loading`.
- Estilo carregou (`didFinishLoading`): `.ready`, instala as layers.
- Falha antes de pronto (`didFailToLoadMapWithError`): `.failed`.
- Erro de tile repetido, falha de sprite/glyph/render: `.degraded(kind)`.
- Um tile isolado com erro ou cancelamento durante pan não gera outage.
- Ausência de conectividade (`NWPathMonitor`) domina como `.offline`.
- Sucesso posterior recupera `.ready`.

Mensagens e logs do app nunca incluem URL/token/mensagem nativa bruta. Em produção, qualquer logging
verboso de URL de request do SDK deve ficar desabilitado.

## Cache and attribution

Usar somente o cache padrão/limitado do SDK; não criar download offline manual, prefetch em massa ou
limpeza no retry. Manter os controles nativos de logo/atribuição do MapLibre habilitados (
`mapView.logoView`, `mapView.attributionButton`) e garantir uma ação SwiftUI acessível adicional com
`© OpenStreetMap contributors` e o crédito/link do provedor. Cards, sheets e safe areas não podem
ocultar permanentemente essa atribuição.

## GeoJSON renderer contract

- IDs de source/layer/imagem são estáveis por View.
- Discovery usa uma source clusterizada e layers de cluster/contagem/não-clusterizado/selecionado.
- Tracking usa uma source não clusterizada com zero ou uma feature.
- Atualizações chamam `source.shape = ...`; nunca recriam a `UIView`, o estilo ou a layer.
- Somente propriedades opacas `id`, `kind`, `selected` e `groupKey` entram no GeoJSON.
- Um reload de estilo reinstala os recursos e reaplica a coleção atual.
