# Análise: Mapa de localização de providers (estáticos e dinâmicos) — iOS

> Documento só de análise/levantamento — **nada foi implementado**. Adaptado de
> `android/pitgo/specs/008-provider-map/analysis.md`, que também não chegou a virar spec/plan/tasks
> no Android — permaneceu como levantamento até as decisões de produto/schema serem resolvidas.
> Objetivo aqui: mapear o que já existe no client iOS/backend compartilhado, o que falta, e as
> decisões de arquitetura/produto necessárias antes de implementar um mapa que mostre providers
> estáticos (endereço salvo) e providers dinâmicos (localização atualizando em tempo real).

## 1. O que já existe hoje

### 1.1 Dados de endereço do provider (estático) — backend compartilhado, inalterado

A tabela `public.addresses` (migration Android `20260820000000_provider_registration.sql`, já
aplicada no projeto compartilhado — ver `007-provider-registration`) já guarda `latitude`/
`longitude` opcionais por provider:

```sql
latitude numeric(9,6),
longitude numeric(10,6),
constraint addresses_coordinates_pair check ((latitude is null) = (longitude is null)),
constraint addresses_latitude_range check (latitude is null or latitude between -90 and 90),
constraint addresses_longitude_range check (longitude is null or longitude between -180 and 180),
constraint addresses_provider_unique unique (provider_id)
```

- Um endereço por provider (`UNIQUE(provider_id)`), coordenadas opcionais e validadas.
- O formulário iOS (`ProviderRegistrationView`/`AddressDraft`, ver `007`) já coleta `latitude`/
  `longitude` como texto livre — **hoje isso é preenchimento manual**, não captura de GPS nem
  geocoding automático a partir do endereço digitado.
- A RPC `create_provider_registration` (já existente e compartilhada) já normaliza e persiste esses
  campos, para qualquer client (Android ou iOS) que a chame.

Conclusão: a peça "provider estático com pino fixo no mapa" já tem onde guardar o dado — nenhuma
mudança de schema é necessária para isso. Falta capturar/validar a coordenada de forma confiável
(hoje é só um texto que a pessoa digita) e expor essa leitura para outros usuários (ver §2.1 sobre
RLS, também compartilhada).

### 1.2 Localização em tempo real (dinâmico)

**Não existe nada hoje, em nenhuma plataforma.** Do lado iOS especificamente, ainda não há:

- coluna/tabela para posição corrente de um provider (schema compartilhado — a mesma lacuna do
  Android, ver §3.2);
- nenhuma dependência de localização declarada no projeto (`CoreLocation` é um framework do sistema,
  não precisa de Swift Package, mas nenhuma tela/`CLLocationManager` foi integrada ainda);
- nenhuma entrada de privacidade de localização em `Info.plist`
  (`NSLocationWhenInUseUsageDescription`/`NSLocationAlwaysAndWhenInUseUsageDescription`) nem
  capability "Location updates" em Background Modes;
- o produto `Realtime` do `supabase-swift` (usado para *postgres_changes*/broadcast) **não está
  habilitado** no target — hoje só `Auth`/`PostgREST` foram adicionados (`004`–`007`). Diferente do
  Android (que precisaria adicionar o artefato Gradle separado `realtime-kt`), no iOS isso é apenas
  habilitar mais um produto do **mesmo** pacote SPM já resolvido — nenhuma dependência nova entra no
  grafo, só mais uma feature do pacote existente.

### 1.3 Mapa / SDK de mapas

Nenhuma integração de mapa existe no client iOS ainda. Diferente do Android — que precisaria
escolher entre Google Maps Compose (com billing), Mapbox ou osmdroid —, o iOS tem `MapKit` nativo da
Apple (framework do sistema, `import MapKit`, `Map` do SwiftUI desde iOS 17), **sem chave de API e
sem billing**. Essa é uma diferença estrutural real a favor do iOS: a peça "SDK de mapa" tem uma
opção de custo zero e zero dependência externa, o que simplifica a decisão de produto §5.2/§8.3 em
relação ao equivalente Android.

### 1.4 O fluxo de "pedir serviço" hoje é uma demo desconectada dos providers reais

`RequestServiceUiState`/`DemoServiceCatalog` (`Core/Common/Model/DemoServiceCatalog.swift`, ver
`003`) são uma lista **estática, fixa no app**, de serviços (`.battery`, `.oilChange`, `.tires`...)
com preço fixo. O tempo de chegada mostrado na View é literalmente um texto fixo (`"20-40 min"`).

Ou seja: hoje não existe nenhum vínculo entre "o cliente pede um serviço" e "um provider real
cadastrado no banco" — igual ao Android, porque essa lacuna é de produto/dados, não de plataforma. O
RLS reforça essa separação: os providers só conseguem ler a própria linha.

### 1.5 RLS atual bloqueia qualquer leitura cross-user — backend compartilhado, inalterado

```sql
create policy providers_select_own on public.providers
for select to authenticated using ((select auth.uid()) = id);
create policy addresses_select_own on public.addresses
for select to authenticated using ((select auth.uid()) = provider_id);
```

Um cliente autenticado — Android ou iOS — **não consegue** hoje listar providers de terceiros nem
seus endereços; só o próprio provider vê a própria linha. Um mapa visível para clientes exige uma
política nova, que precisaria ser criada uma única vez (no repositório Android, fonte de verdade do
schema) e valeria para as duas plataformas automaticamente.

### 1.6 Arquitetura atual (onde a feature se encaixaria no iOS)

- Injeção simples por `init`/`Environment` (sem framework de DI), estabelecida desde `006`
  (`SessionStore` injetado via `.environment`) — um novo `ProviderMapRepository`/
  `ProviderLocationRepository` entraria do mesmo jeito que `ProviderRegistrationRepository` (`007`).
- Navegação centralizada em `PitGoRootView`/`PitGoRoute`/`UnauthenticatedRoute`. Uma tela de mapa
  nova seria mais uma rota autenticada, plugável na `TabView` (Home ou uma futura aba "Mapa") ou
  empurrada a partir de `RequestServiceView` (`003`).
- iOS 17+ como alvo mínimo (constitution) — relevante para permissões de localização: desde
  iOS 13 a autorização "Always" (equivalente a `ACCESS_BACKGROUND_LOCATION`) é solicitada
  separadamente da autorização "When In Use", e a Apple exige justificativa textual detalhada
  (`NSLocationAlwaysAndWhenInUseUsageDescription`) revisada no processo de App Review, de forma
  análoga à declaração de uso de localização em background exigida pela Play Store no Android.

## 2. Requisito do usuário, decomposto

> "mostra a localização dos providers no mapa, vai ter providers dinâmicos (não estáticos), pega a
> localização deles em tempo real e vai atualizando no mapa; os que salvar endereço aparecem
> estático"

Isso implica **dois modos de provider coexistindo no mesmo mapa** — decisão de produto/schema
independente de plataforma:

| Modo | Fonte da posição | Atualização | Exemplo de caso de uso |
|---|---|---|---|
| **Estático** | `addresses.latitude/longitude` (endereço cadastrado) | Nunca (até o provider editar o endereço — feature de edição ainda nem existe) | Oficina fixa, loja de peças |
| **Dinâmico** | GPS do dispositivo do provider, enviado periodicamente | Tempo real (segundos) enquanto o provider estiver "ativo"/em rota | Mecânico/guincho que vai até o cliente |

Como em nenhum lugar do schema existe hoje o conceito de "modo do provider", essa é uma decisão de
produto que precisa ser explícita — ver §3.1 (idêntica à análise Android, pois é schema
compartilhado).

## 3. Lacunas de dados e proposta de modelagem (backend compartilhado)

Toda esta seção é **idêntica à análise Android** — o schema é único e compartilhado; qualquer
migration resultante destas decisões deve ser autorada uma única vez, no repositório Android (fonte
de verdade estabelecida desde `005-create-user-account §0`), e reutilizada pelo iOS sem duplicação.

### 3.1 Marcar o "modo" do provider

```sql
alter table public.providers
  add column location_mode text not null default 'STATIC'
  check (location_mode in ('STATIC', 'DYNAMIC'));
```

Perguntas em aberto (produto, não técnicas): é uma escolha fixa no cadastro ou pode alternar a
qualquer momento? Um provider "dinâmico" ainda tem endereço-base como fallback quando offline?

### 3.2 Onde guardar a posição em tempo real

**Não deve** ficar em `addresses` (representa o endereço cadastrado, `UNIQUE(provider_id)`).
Proposta: tabela nova, RLS diferenciada (o provider grava a própria linha; qualquer autenticado lê):

```sql
create table public.provider_live_locations (
  provider_id uuid primary key references public.providers(id) on delete cascade,
  latitude numeric(9,6) not null,
  longitude numeric(10,6) not null,
  heading numeric(5,2),          -- opcional: direção do movimento, para orientar o pino
  accuracy_meters numeric(6,2),  -- opcional: raio de precisão do GPS
  is_online boolean not null default true,
  updated_at timestamptz not null default now()
);
```

Uma linha por provider (upsert contínuo) é mais simples e barato que uma tabela de histórico de
posições; histórico/replay seria uma tabela de eventos separada, fora de escopo até virar requisito.

### 3.3 RLS necessária

- `provider_live_locations`: insert/update só para o próprio provider (`auth.uid() = provider_id`,
  reforçado via check/trigger ou RPC, condicionado a `providers.location_mode = 'DYNAMIC'`); select
  para qualquer `authenticated` (ou restringir por proximidade/serviço — decisão de produto).
- `providers`/`addresses`: a policy atual (`select own`) precisa de uma política adicional de
  leitura pública/autenticada para permitir que clientes vejam provider + endereço de terceiros no
  mapa — hoje isso não é possível em nenhuma plataforma. Precisa decidir quais campos ficam visíveis
  publicamente (nome, categoria de serviço, cidade/bairro aproximado) vs. o que continua privado
  (CNPJ completo, telefone, e-mail); uma leitura pública precisaria de uma *view* própria que já
  mascare/omita esses campos, em vez de liberar `select` direto na tabela crua.

### 3.4 Presença / expiração de dinâmico

Sem heartbeat, um provider que perde conexão fica "grudado" no mapa como se ainda estivesse lá.
Regras possíveis: o client marca `is_online = false` ao sair da tela/app ir para background (best
effort — no iOS isso é `scenePhase` mudando para `.background`, com a mesma limitação de "best
effort" que o Android tem ao fechar o app); o client ignora localmente `updated_at` mais velho que N
minutos; e/ou um job periódico (Supabase Edge Function agendada, ou `pg_cron`) zera `is_online` para
linhas velhas — mais robusto, mas é infraestrutura de backend nova (compartilhada, não específica de
plataforma), hoje não configurada.

## 4. Transporte em tempo real

Duas opções realistas com o stack atual (Supabase, independentes de plataforma):

| Opção | Como funciona | Prós | Contras |
|---|---|---|---|
| **Supabase Realtime — Postgres Changes** | Client assina mudanças na tabela `provider_live_locations` via websocket; cada `UPDATE` chega ao app | Mesma fonte de verdade (Postgres), simples de auditar, sem infra nova além de habilitar o produto `Realtime` do `supabase-swift` já instalado | Precisa habilitar replication na tabela; volume de updates pode gerar bastante tráfego de WAL com muitos providers ativos |
| **Supabase Realtime — Broadcast** (canal efêmero) | Provider publica lat/lng num canal `provider:{id}`; clientes assinam o canal do provider que acompanham | Mais leve para alta frequência; combina com *Presence* para saber quem está online sem heartbeat manual | Perde histórico via SQL; exige lógica própria para descobrir quais canais assinar perto do usuário |

Recomendação de leitura futura (não é decisão, é ponto de partida — idêntica à do Android): usar
**Postgres Changes** para a query inicial + fallback, considerar **Broadcast/Presence** se o volume
por segundo se mostrar problema depois de medir. No iOS, isso significa apenas habilitar o produto
`Realtime` do pacote `supabase-swift` já resolvido (`004`) — nenhuma dependência nova, diferente do
Android, que precisaria adicionar o artefato `realtime-kt` ao catálogo Gradle.

## 5. Client iOS — peças que faltam

### 5.1 Permissões e captura de posição (lado do provider)

- `CLLocationManager` (`CoreLocation`, framework do sistema — sem Swift Package) é o caminho padrão
  para captura de GPS no iOS, equivalente ao `FusedLocationProviderClient` do Android — mas sem
  dependência externa a adicionar.
- `Info.plist` precisa de `NSLocationWhenInUseUsageDescription` (mínimo, para foreground) e
  `NSLocationAlwaysAndWhenInUseUsageDescription` (se o provider precisar continuar transmitindo com
  o app em background) — a segunda vem com justificativa textual revisada pela Apple no App Review,
  análogo à declaração de uso de localização em background do Play Console.
- Se o objetivo for "provider com o app aberto, em rota" já basta autorização "When In Use"; se o
  objetivo for "provider continua visível com o app minimizado", precisa da capability "Background
  Modes → Location updates" no target (equivalente ao Foreground Service com tipo `location` do
  Android) mais autorização "Always".
- Desde 2024, apps que usam APIs sensíveis (incluindo localização) precisam declarar o uso num
  arquivo `PrivacyInfo.xcprivacy` ("Privacy Manifest") — um requisito iOS sem paralelo direto no
  Android atual, a ser cumprido quando esta feature for implementada.

### 5.2 Mapa (lado do cliente)

- `MapKit` nativo (`import MapKit`, `Map` do SwiftUI) é o caminho recomendado — **sem chave de API,
  sem billing**, diferença estrutural favorável ao iOS frente ao Google Maps Compose do Android (que
  exige Google Cloud + billing habilitado mesmo dentro da cota gratuita). Mapbox/tiles OSM
  continuam alternativas caso um estilo de mapa específico seja exigido, mas não há razão de custo
  para evitar o SDK nativo no iOS como há no Android.
- Nova `View` (`Features/ProviderMap/` ou dentro de `RequestService`) com: pinos estáticos (uma
  única consulta PostgREST, sem assinatura); pinos dinâmicos (assinatura Realtime, atualizando
  posição/anotação enquanto a `View` estiver visível — cancelar a assinatura em `.onDisappear`/
  `Task` cancelada para não vazar conexão/bateria); agrupamento de pinos (`MapKit` já oferece
  clustering nativo via `MKClusterAnnotation`, outra vantagem estrutural sobre implementar clustering
  manualmente).

### 5.3 Privacidade / consentimento

- Precisa de uma tela explícita de opt-in para o provider dinâmico ("Compartilhar minha localização
  em tempo real enquanto estiver disponível"), com jeito claro de desligar, já que localização em
  tempo real é dado sensível (LGPD) e a App Store exige fluxo de consentimento específico para apps
  que coletam localização em background (App Store Review Guidelines seção 5.1.1, análoga à política
  de localização em background da Play Store).
- Mesma decisão de produto do Android: localização exata visível para qualquer cliente logado o
  tempo todo, ou só durante um pedido de serviço ativo (padrão "Uber")? Isso muda o desenho de
  RLS/broadcast e depende de uma entidade real de "pedido de serviço" que ainda não existe (§6.3).

## 6. Coisas que precisam existir antes/junto (dependências implícitas do pedido)

Idêntico ao levantamento Android — são lacunas de produto/backend compartilhado, não específicas de
plataforma:

1. **Geocoding do endereço estático**: hoje `latitude`/`longitude` são digitados à mão no cadastro
   (`007`). No iOS, `CLGeocoder` (`CoreLocation`, nativo) poderia resolver geocoding a partir do
   endereço textual sem dependência externa — equivalente nativo ao que o Android buscaria via
   Google Geocoding API ou Nominatim/OSM.
2. **Tela de edição de endereço/provider**: hoje o cadastro (`007`) é *create-once* (a RPC recusa
   recriar se já existe provider completo). Sem edição, um provider estático nunca corrige um pino
   errado depois do cadastro inicial.
3. **Entidade real de "pedido de serviço"**: se a visibilidade da localização em tempo real deve
   depender de um pedido ativo (§5.3), essa tabela/fluxo precisa ser desenhado — hoje não existe em
   nenhuma plataforma (`RequestService`/`003` é 100% mock, sem persistência).
4. **Lista real de providers por serviço/categoria perto do cliente**: o mapa provavelmente nasce
   junto de "buscar provider perto de mim que oferece X" — hoje o catálogo mostrado ao cliente é o
   `DemoServiceCatalog` estático (`003`), desconectado de `service_categories`/`services` (que já
   existem no banco, usados hoje só no cadastro do provider em `007`). Conectar as duas pontas é
   pré-requisito para o mapa fazer sentido no fluxo de pedido.

## 7. Resumo do gap (o que falta, por camada)

| Camada | Existe? | Falta |
|---|---|---|
| Coordenada estática no banco (compartilhado) | ✅ (`addresses.latitude/longitude`) | Geocoding automático; tela de edição |
| Coordenada dinâmica no banco (compartilhado) | ❌ | Tabela `provider_live_locations` + RLS + expiração/presença |
| Marcação estático vs dinâmico (compartilhado) | ❌ | Coluna `providers.location_mode` (ou equivalente) + regra de produto |
| Leitura pública de provider/endereço (compartilhado) | ❌ (RLS só permite "ver a si mesmo") | Política nova + view que mascare dados sensíveis |
| Transporte em tempo real (client iOS) | ❌ | Habilitar produto `Realtime` do `supabase-swift` (já no pacote, sem dependência nova) + canal |
| Captura de GPS no device do provider (client iOS) | ❌ | `CLLocationManager`, entradas de `Info.plist`, `PrivacyInfo.xcprivacy`, tela de opt-in |
| SDK de mapa no client iOS | ❌ | `MapKit` nativo (sem chave de API/billing) |
| Vínculo com pedido de serviço real (compartilhado) | ❌ (`RequestService` é mock) | Modelo de "pedido" persistido, se a visibilidade for por pedido ativo |
| Catálogo de serviços real conectado ao mapa (client iOS) | ❌ (`DemoServiceCatalog` é estático) | Ligar `service_categories`/`services` (já existem) ao fluxo do cliente |

## 8. Perguntas em aberto para decidir antes de implementar

Idênticas às do Android — são decisões de produto/schema compartilhado, não específicas de
plataforma:

1. Provider escolhe estático/dinâmico no cadastro, ou isso é automático (ex.: dinâmico só enquanto
   estiver "em rota" para um pedido específico)?
2. A localização em tempo real fica visível para **qualquer** cliente logado o tempo todo, ou só
   para quem tem um pedido ativo com aquele provider?
3. Confirmar que `MapKit` nativo (sem billing) é aceitável para o iOS — ao contrário do Android, aqui
   não há a mesma pressão de custo/dependência de Google Maps, então a escolha tende a ser mais
   simples neste lado.
4. Precisamos de trilha/histórico de trajeto (replay), ou só a posição atual já resolve?
5. Qual a frequência aceitável de atualização (a cada quantos segundos/metros) — isso define consumo
   de bateria do provider e volume de mensagens realtime, em qualquer plataforma?
6. Vale a pena já entrar com "pedido de serviço" persistido nesta mesma iniciativa, ou o mapa entra
   primeiro como "descobrir providers perto de mim" (sem pedido) e o vínculo com pedido vem depois?

## 9. Ordem sugerida de investigação/implementação (alto nível, não é o plano final)

1. Decisões de produto da seção 8 (compartilhadas entre Android e iOS).
2. Modelagem (`location_mode`, `provider_live_locations`, RLS/view pública) + geocoding do endereço
   estático no cadastro existente — autorada uma única vez na migration do repositório Android.
3. Ligar `RequestService`/Home ao catálogo real (`service_categories`/`services`) em cada client —
   sem isso o mapa fica solto, sem fluxo de negócio real em volta.
4. Client iOS: tela de mapa só com pinos estáticos (`MapKit`, sem realtime) lendo a leitura pública
   nova.
5. Provider (iOS): opt-in + captura de GPS (`CLLocationManager`) + escrita periódica em
   `provider_live_locations` via `PostgREST`.
6. Client iOS: assinatura Realtime dos pinos dinâmicos sobre o mesmo mapa da etapa 4.
7. Expiração/presença, testes com múltiplos providers simultâneos, revisão de bateria e de política
   de privacidade/App Store (Privacy Manifest, App Review Guidelines 5.1.1).

> Nota: como visto em `009-provider-location-accounts` e `010-osm-realtime-map` no repositório
> Android, parte destas decisões já foi resolvida e implementada em specs posteriores — este
> documento é preservado como o levantamento original que antecedeu essas features, e o mesmo
> tratamento (spec/plan/tasks completos) será aplicado a `009`/`010` na sequência da portabilidade
> iOS.
