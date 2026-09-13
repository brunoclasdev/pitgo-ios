# Research: Contas independentes e localização de prestadores (iOS)

## 0. Backend compartilhado — nenhuma migration/Edge Function nova

**Decision**: reutilizar integralmente `account_roles`, o desacoplamento `providers.id`/
`providers.account_id`, `provider_categories`, os campos de geografia/PostGIS em `addresses`,
`private.provider_geocode_verifications`, `private.provider_ownership_transfers`, `appointments`,
`provider_current_locations`, todas as RPCs (`get_my_account_context`, `create_provider_registration`,
`set_my_provider_mode`/`set_my_provider_availability`, `begin_provider_ownership_migration`/
`claim_provider_ownership_migration`, `list_home_services`, `discover_service_providers`,
`publish_provider_location`/`stop_provider_location`/`get_appointment_provider_location`), o Before
User Created Hook, o trigger de perfil, o Database Broadcast privado e as Edge Functions
`geocode-provider-address`/`refresh-provider-geocodes` já criados e aplicados pela feature Android
equivalente, no mesmo projeto Supabase compartilhado. Nenhuma migration nem Edge Function nova é
criada neste repositório; os contratos exatos estão em `contracts/`.

**Rationale**: mesmo racional de `005`–`007` — schema, funções e Edge Functions (código Deno,
inerentemente independente de plataforma cliente) são compartilhados entre Android e iOS. Duas Edge
Functions Deno já publicadas no projeto Supabase atendem qualquer client autenticado que as invoque
via `client.functions.invoke(...)`, seja `supabase-kt` ou `supabase-swift`.

## 1. Papel de conta autoritativo

**Decision**: consumir `get_my_account_context()` (já existente) a partir de um `AccountContextRepository`
Swift. `AppSessionState` (`006`) ganha os casos que faltam para dois papéis:

```swift
enum AppSessionState {
    case initializing, verifying, offlineVerification
    case unauthenticated(reason: UnauthenticatedReason?)
    case blocked(reason: BlockedReason)
    case authenticatedClient(AccountSnapshot)
    case authenticatedProviderOnboarding(AuthIdentity)
    case authenticatedProviderReady(ProviderSnapshot)
}
```

**Rationale**: idêntico ao Android — `raw_user_meta_data` é editável pelo usuário e nunca autoriza;
a tabela/RPC autoritativa já resolve ambiguidade. Nenhuma decisão nova de backend; o iOS só precisa
mapear a resposta JSON já estável para um `enum` Swift fechado.

## 2. Signup e sessão de empresa

**Decision**: "Sou uma empresa" empurra `UnauthenticatedRoute.providerSignUp` (não
`.signUp(origin:)`, que é removido — ver `contracts/navigation-session.md`). O signup empresarial cria
somente uma conta Auth `PROVIDER` via `client.auth.signUp(email:password:data: ["account_type":
"PROVIDER"])`; o contexto resultante é `.authenticatedProviderOnboarding` até a RPC de cadastro
confirmar o agregado. O signup de cliente (`005`) envia `"account_type": "CLIENT"`. Login continua
único; após `client.auth.signIn`, `AccountContextRepository` decide o destino.

**Rationale**: idêntico ao Android — Auth e Data API não compartilham uma transação; um estado de
onboarding retomável é mais seguro que fingir atomicidade. `SignUpOrigin.provider` (introduzido em
`007`) é removido — o CTA de empresa nunca mais passa pelo SignUp de cliente.

## 3. Identidade estável da empresa e migração legada

**Decision**: nenhuma mudança de schema — `providers.id` (estável) e `providers.account_id`
(substituível) já existem. A migração assistida usa as duas RPCs já existentes
(`begin_provider_ownership_migration`/`claim_provider_ownership_migration`). O desafio de 32 bytes em
texto plano vive **somente em memória**, num pequeno coordinator (`ProviderMigrationCoordinator`,
`@Observable`, escopo de processo) — nunca em `UserDefaults`, `Keychain`, rota ou log. Encerramento do
processo (o app é finalizado) descarta o desafio e exige reiniciar o fluxo a partir da sessão CLIENT
original — mesmo comportamento do Android (que também não sobrevive à morte de processo).

**Rationale**: idêntico ao Android — token de uso único, hash privado no servidor e validade de 15
minutos tornam begin/claim atômicos e idempotentes; o client nunca precisa persistir o segredo.

## 4. Cadastro atômico de provider/categorias/serviços/endereço

**Decision**: nenhuma mudança — `ProviderRegistrationRepository` (de `007`) passa a chamar a versão
atualizada de `create_provider_registration(p_provider:, p_offers:, p_geocode_verification_id:,
p_divergence_confirmed:)`, que deriva owner de `auth.uid()`, exige papel `PROVIDER`, valida tudo antes
do primeiro insert e grava provider/endereço/`provider_categories`/`provider_services` numa única
transação (já existente).

**Rationale**: atomicidade é propriedade de backend; o iOS herda a mesma garantia sem reimplementar
nada, mesmo racional de `007 §7`.

## 5. Geocodificação

**Decision**: chamar a Edge Function `geocode-provider-address` (já publicada) via
`client.functions.invoke("geocode-provider-address", options: .init(body: payload))` do
`supabase-swift`. O payload/resposta são exatamente os documentados em
[contracts/geocoding-edge-function.md](contracts/geocoding-edge-function.md) — nenhuma mudança de
contrato HTTP. O fix do dispositivo usado no payload vem de `CLLocationManager`
(`requestLocation()`/`CLLocationUpdate.liveUpdates` em modo `.default` com `desiredAccuracy =
kCLLocationAccuracyBest`), nunca de `lastKnownLocation` como autoridade — mesma exigência de
"one-shot high accuracy" do Android (`getCurrentLocation`, não `lastLocation`).

**Rationale**: a Edge Function já esconde a chave Google Geocoding do client, criptografada em
Supabase Secrets — não há chave nenhuma no bundle iOS, nem publishable nem restrita, diferente da
chave de mapa Android (`MAPS_API_KEY`) que precisava de placeholder de manifest. Como o iOS usa
MapLibre Native (ver §7) para o mapa em si, **não existe uma segunda chave de SDK de mapa a
gerenciar no client iOS** — outra simplificação estrutural real frente ao Android.

**Alternatives considered**: `CLGeocoder` nativo do iOS para geocoding client-side, rejeitado pelo
mesmo motivo do Android rejeitar o `Geocoder` do Android — não garante disponibilidade/qualidade
consistente para um cadastro obrigatório, e uma chamada direta a uma API paga exporia a chave no
bundle. A Edge Function server-side já resolvida pelo Android é reaproveitada tal como está.

## 6. Comparação endereço/dispositivo

**Decision**: exigir autorização `.authorizedWhenInUse` (mínimo) e um fix com `horizontalAccuracy
<= 100` metros e idade `<= 30s` (`Date().timeIntervalSince(location.timestamp)`), obtido via
`CLLocationManager.requestLocation()` (one-shot) com timeout de 15 segundos implementado no
ViewModel (`Task` com `withTimeout`-like helper, já que `CLLocationManager` não tem timeout nativo).
Até 500m aceitar; acima disso exigir confirmação explícita — mesma regra de negócio do backend
(inalterada). Editar qualquer campo do endereço invalida a prova/confirmação no ViewModel local
(mesma regra client-side do Android).

**Rationale**: idêntico ao racional do Android — precisão/idade objetivas tornam "qualidade
suficiente" verificável tanto no client quanto na Edge Function (que já valida os mesmos limites,
inalterada).

## 7. Mapa e consulta espacial

**Decision**: usar **MapLibre Native iOS** (Swift Package `MapLibre`, produto de
`maplibre/maplibre-native-distribution` ou equivalente resolvido pelo SPM), conforme já decidido na
constitution do projeto ("MapLibre Native iOS para manter o mesmo provedor de mapa self-hosted já
usado no Android, em vez de MapKit"). A Home carrega UUIDs reais do catálogo (via `list_home_services()`,
já existente) e navega para `PitGoRoute.serviceMap(serviceID:)`. `ServiceMapRepository` chama a RPC
PostGIS `discover_service_providers` (já existente), que exige sessão CLIENT, filtra serviço e
categoria exatos, provider/owner ativos e disponíveis e endereço geocodificado vigente, retornando
somente a projeção pública mínima (`ServiceMapResult`), por raio/viewport, no máximo 200 itens.
Clustering de marcadores usa o suporte nativo do MapLibre Style Spec (`cluster: true` na fonte
GeoJSON), e uma lista acessível equivalente (`Mapa | Lista`) cobre o caso sem depender só de pinos.

**Rationale**: MapLibre Native é a mesma biblioteca open-source usada no Android (fork ativo do antigo
Mapbox GL Native, distribuído separadamente do SDK Mapbox proprietário) e tem binding iOS oficial via
SPM — permite reutilizar o mesmo provedor de tiles self-hosted/gerenciado (§5 do research Android,
inalterado) e o mesmo Style JSON entre as duas plataformas, sem depender de billing de terceiros
(Google Maps) nem exigir uma segunda infraestrutura de tiles por plataforma. Diferente do que a
análise exploratória de `008-provider-map` havia considerado (`MapKit` nativo, sem dependência), a
constitution já registrou essa troca deliberadamente: consistência de fornecedor de mapa entre
Android e iOS pesa mais que a conveniência de zero-dependência do `MapKit` nativo.

**Alternatives considered**: `MapKit` nativo com `MKTileOverlay` customizado apontando para o mesmo
provedor OSM, teria zero dependência SPM, mas foi descartado pela constitution em favor de manter o
mesmo SDK/Style JSON do Android (facilita evoluir estilo/clustering uma única vez); Google Maps SDK
para iOS, rejeitado pela mesma razão do Android (billing, e o requisito de produto FR-036 exclui
qualquer SDK de mapa proprietário).

## 8. Permissões e atualização em background

**Decision**: pedir `.requestWhenInUseAuthorization()` no cadastro/verificação de endereço (não pedir
`.requestAlwaysAuthorization()` nesse momento). O tracking móvel começa por ação visível numa tela de
atendimento aceito e usa `CLLocationManager` com `allowsBackgroundLocationUpdates = true` e a
capability "Background Modes → Location updates" habilitada no target — **não** requer um Foreground
Service nem uma notificação persistente construída manualmente: o iOS já exibe automaticamente um
indicador de sistema (a barra/pílula azul "App está usando sua localização") sempre que uma app
atualiza localização em background, o que cumpre o mesmo objetivo de transparência do Android sem
exigir infraestrutura de notificação própria. Autorização `.authorizedAlways` só é solicitada nesse
momento (ação visível, com o motivo explicado antes do prompt do sistema — mesmo espírito do
"rationale primeiro" do Android). O rastreamento para em toda condição terminal (ver §9), e o app
nunca reinicia rastreamento sozinho após ser finalizado pelo sistema (equivalente ao
`START_NOT_STICKY`/sem boot receiver do Android).

**Rationale**: iOS não tem o conceito de "foreground service" do Android; `CLLocationManager` com
`allowsBackgroundLocationUpdates` é o mecanismo nativo equivalente, e o indicador visual de uso de
localização é fornecido automaticamente pelo sistema — uma simplificação estrutural real: nenhum
canal de notificação, ícone, texto ou ação de notificação precisa ser implementado manualmente.

**Alternatives considered**: usar somente `.authorizedWhenInUse` e aceitar que o tracking pare ao
sair do app (equivalente ao "modo somente tela visível" do Android sem permissão de notificação),
mantido como fallback explícito quando `.authorizedAlways` for negada — mesma degradação graciosa do
Android; `BGTaskScheduler`/`BGAppRefreshTask`, rejeitado porque não entrega atualização a cada ~10s
(desenhado para tarefas oportunistas de minutos/horas, não heartbeat de segundos).

## 9. Aquisição/publicação de posição móvel

**Decision**: `CLLocationManager` com `desiredAccuracy = kCLLocationAccuracyBest`,
`distanceFilter = kCLDistanceFilterNone` e um timer local de ~10 segundos (ou
`CLLocationUpdate.liveUpdates` filtrando por intervalo mínimo) para não publicar mais rápido que o
contrato do backend. Validar precisão `<=100m` e idade `<=30s` antes de chamar
`publish_provider_location` (RPC já existente, inalterada). Offline mantém somente o fix mais recente
em memória (`@Observable var latestFix: CLLocation?`). Um `tracker_instance_id` (`UUID` gerado uma vez
por sessão de tracking) e uma sequência crescente local satisfazem o contrato de
monotonicidade/arbitragem já implementado no servidor.

**Rationale**: idêntico ao racional do Android — heartbeat mantém recência mesmo parado; a arbitragem
já acontece inteiramente no servidor (inalterado), o client só precisa fornecer dados válidos e
monotônicos.

## 10. Realtime privado e recência

**Decision**: habilitar o produto `Realtime` do `supabase-swift` (mesmo pacote já resolvido em `004`,
nenhuma dependência nova — diferente do Android, que precisou trocar o engine Ktor para suportar
WebSocket). `AppointmentTrackingRepository` chama `client.realtime.setAuth()`, cria e assina o canal
privado `appointment-location:<id>` (`isPrivate: true`), busca o snapshot via
`get_appointment_provider_location` **depois** de confirmar a assinatura, e mescla
snapshot/eventos somente quando a `version` recebida for mais nova. Um `Task`/`Timer` local marca o
marcador como `.stale` em `publishedAt + 30s` mesmo sem novo evento.

**Rationale**: Database Broadcast é a mesma escolha do Android, pela mesma razão (escala/segurança,
recomendado pelo Supabase); a RLS de `realtime.messages` (já aplicada) protege o canal
independentemente do SDK cliente. `supabase-swift` expõe Realtime como produto do pacote único, então
não há troca de engine HTTP necessária no iOS (URLSession já suporta WebSocket nativamente).

## 11. Âncora mínima de atendimento

Nenhuma mudança — `appointments` (já existente, mínima, sem UI/RPC de despacho/aceite nesta feature)
é consumida como está. O quickstart usa uma fixture administrativa para inserir um registro
`ACCEPTED`, exatamente como o Android faz.

## 12. Localização do cliente

**Decision**: nenhuma tabela nem tracking em background do lado cliente. A descoberta usa um fix
one-shot (`CLLocationManager.requestLocation()`) mantido em memória, enviado apenas como centro da
consulta RPC; sem permissão, usa a região selecionada/pan do mapa MapLibre. Durante acompanhamento de
atendimento, a captura existe somente enquanto a `View` estiver visível (`.onAppear`/`.onDisappear`
cancelando o `CLLocationManager`), se uma finalidade visível realmente exigir.

**Rationale**: idêntico ao Android — atende busca e privacidade sem histórico; ao sair, trocar de
conta ou de serviço, `Task`s e o canal Realtime são cancelados/removidos.

## Resolution status

Todas as decisões do Technical Context foram resolvidas; não restam pendências.
