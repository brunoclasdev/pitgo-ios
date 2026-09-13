# Quickstart: validar MapLibre e atualização em tempo real (iOS)

## 1. Configuração

Além das propriedades Supabase existentes, fornecer em `pitgo/Config/Secrets.xcconfig` (local, não
rastreado):

```text
mapStyleUrl = https:/$()/<managed-provider>/<style>.json?key=<client-token>
mapStyleProviderName = <provider-name>
mapStyleAttribution = © OpenStreetMap contributors · <provider-credit>
mapStyleAttributionUrl = https:/$()/<provider-attribution-page>
```

CI usa um `.xcconfig` gerado com os mesmos nomes, injetado via `xcodebuild -xcconfig`. Somente
token público/restrito; nenhum valor real em arquivo versionado, argumento de linha de comando, log
ou artefato.

## 2. Backend compartilhado (somente verificação)

```bash
supabase link
supabase db diff
```

Confirmar que o hardening já aplicado (`20260821030000_appointment_location_stream_hardening.sql`,
ver `009 §0`) continua presente: `EMPTY` para atendimento ativo, `ENDED` terminal, topic/snapshot
somente para participante, publish terminal negado e ausência de histórico. Nenhuma migration nova é
criada ou aplicada por esta feature iOS.

## 3. Build/dependências

```bash
xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'platform=iOS Simulator,name=iPhone 16' clean build

xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'generic/platform=iOS' clean build
```

Esperado: ambos sucedem; o Swift Package `MapLibre` resolve; nenhuma outra dependência de mapa é
adicionada.

```bash
grep -rn "MapKit\|GoogleMaps\|GMSMapView" pitgo/ 2>/dev/null
```

Esperado vazio — nenhum SDK de mapa concorrente foi introduzido. Revisar `Package.resolved` para
confirmar `MapLibre` como única dependência de renderização de mapa.

## 4. Style gate

Validar que o Run Script Build Phase falha sem ecoar valores para campo ausente, URL não-HTTPS,
user-info/fragment, ou host demo/público. Antes de produção, inspecionar manualmente o Style JSON e
confirmar sources/TileJSON/sprites/glyphs em HTTPS gerenciados, pt-BR quando suportado e atribuição
completa.

## 5. Descoberta

Em simulador e dispositivo físico:

1. Abrir um serviço e conferir marcadores no endereço empresarial para FIXED/MOBILE.
2. Provider sem coordenada válida não aparece posicionado.
3. Mapa/Lista selecionam o mesmo provider e abrem o mesmo resumo.
4. Resumo mostra somente dados públicos e o CTA.
5. CTA navega com `serviceID`/`providerID`, sem nome/preço na rota.
6. Testar clusters próximos e coordenadas iguais; todos acessíveis por sheet/lista.
7. Pan/zoom/busca rápida não aceita resposta antiga nem reseta a câmera.
8. Negar localização mantém a região alternativa.
9. O cadastro empresarial (`007`/`009`) não instancia mapa.

## 6. Style/resources/lifecycle

1. Estilo válido carrega e a atribuição OSM/provedor permanece visível/tocável.
2. Estilo inválido/401 falha com retry e a lista é preservada.
3. Erro de tile 401/429 repetido, falha de sprite/glyph e recuperação produzem o banner correto.
4. Um tile isolado/cancelado durante pan não vira outage.
5. Modo avião preserva dados e recursos cacheados quando disponíveis.
6. Retry mantém câmera, seleção e o último marcador; não recria a `MLNMapView` nem limpa o cache.
7. Retry seguido de `Ended`/expiração de sessão não ressuscita o marcador num callback tardio.
8. Alternar Mapa/Lista, rotacionar e navegar repetidamente não deixa mais de uma `MLNMapView`/
   conjunto de observadores vivo (verificar com Instruments/Memory Graph se necessário).

## 7. Realtime

1. Atualizações novas movem o mesmo marcador/source.
2. Revisão 5 seguida de 4 não regride.
3. `DELETE`/tombstone seguido de evento igual/antigo não ressuscita.
4. Reinserção com `version = 1` e `publishedAt` posterior é aceita.
5. Broadcast entre subscribe/snapshot vence um snapshot atrasado.
6. Após 30s, o marcador permanece stale com a última atualização.
7. Offline mantém stale; reconectar refaz subscribe + snapshot.
8. COMPLETED/CANCELLED recebe `ENDED`, limpa marcador/canal e bloqueia publish.
9. Sessão expirada/trocada limpa a coordenada antes do gate.
10. Um terceiro usuário não recebe snapshot/topic.

## 8. Responsividade/acessibilidade

- iPhone compacto, landscape e Dynamic Type grande; sem corte de ação.
- VoiceOver opera Mapa/Lista, provider, resumo e CTA.
- A `MLNMapView` não é a única representação.
- Controles `>=44×44pt`; CTA `>=56pt`.
- Cluster coincidente possui lista completa.
- Live/stale/ended comunicados por texto/ícone, sem anúncio a cada atualização.
- A atribuição nunca fica permanentemente coberta.

## 9. Gate de produção

Registrar fornecedor de tiles, SLA/limites, atribuição e restrições do token. Validar política de
logs (sem verbose de URL/token do SDK em produção). Confirmar que nenhum fallback silencioso para
outro renderizador foi introduzido.
