# Research: Experiência mockada de UI do PitTec (iOS)

## 1. Isolamento do fluxo real existente

**Decision**: manter o código das features reais `013`/`015`, mas retirar seu wiring do protótipo.
A rota cliente não cria `PitTecRepository`/`DispatchResumeCoordinator` (`013`/`015`) nem abre
`AppointmentTrackingViewModel` (`009`/`010`/`014`). Para `ProviderLocationMode.pittec`,
`PitGoRootView` não instancia `ProviderDashboardViewModel` real, exclui `.pittec` do
`ProviderLocationTracker` real e encerra qualquer tracking anterior por uma ação puramente local
que não atualiza disponibilidade no servidor.

**Rationale**: idêntico ao racional do Android — compor esses ViewModels já restauraria despacho
via Supabase, iniciaria Realtime/polling ou publicaria localização. Trocar somente as Views deixaria
efeitos reais invisíveis, contrariando FR-033. Preservar as classes reais evita exclusão ampla e
permite reativar `015` depois do protótipo.

**Alternatives considered**: idênticas ao Android — mockar respostas dentro dos Repositories reais
(rejeitado, mistura contratos locais/backend); apagar a implementação real (rejeitado, destrói
trabalho reutilizável); usar uma feature flag remota (rejeitado, adicionaria infraestrutura externa
a um protótipo local).

## 2. Estado de sessão e independência entre perfis

**Decision**: usar dois `@Observable` distintos — `PitTecClientMockViewModel` e
`PitTecProviderMockViewModel` — instanciados uma vez em `pitgoApp.swift`/`PitGoRootView` (owner
acima das rotas, equivalente ao "host-scoped" do Android) e identificados pela sessão atual. Não
usar `UserDefaults`/`SwiftData`/singleton de processo compartilhado entre perfis. Cada instância
mantém sua própria fixture, revisão e atendimento; uma ação de um perfil nunca atualiza o outro.

**Rationale**: idêntico ao racional do Android — um objeto acima das rotas mantém o estado quando a
View é retirada/reaberta na mesma sessão; o encerramento do processo limpa naturalmente a simulação,
que é o limite definido pela spec.

**Alternatives considered**: idênticas ao Android — um coordinator compartilhado entre cliente e
prestador (rejeitado, criaria sincronização que a clarificação exclui); persistir em
`UserDefaults`/`SwiftData` (rejeitado, poderia restaurar o protótipo após reinício do processo e
exigiria serializar uma máquina de estados desnecessariamente).

## 3. Localização real do prestador

**Decision**: reutilizar `DeviceLocationRepository` (`009`). Solicitar `.authorizedWhenInUse` no
momento de uso, mas considerar a Home pronta somente com localização precisa
(`CLAccuracyAuthorization.fullAccuracy`). Modelar explicitamente `.checkingPermission`,
`.permissionRequired`, `.approximateOnly`, `.servicesDisabled`, `.locating`, `.ready(location)` e
`.unavailable`. Sem `.ready`, não compor o mapa. O CTA abre `UIApplication.openSettingsURLString` e
a View revalida permissão/serviços em `.onAppear`/`scenePhase == .active` ao retornar.

**Rationale**: idêntico ao racional do Android — iOS também pode conceder somente "precisão
aproximada" mesmo com autorização concedida (`CLAccuracyAuthorization.reducedAccuracy`), e isso
precisa ser um estado acionável (`requestTemporaryFullAccuracyAuthorization`). O requisito torna a
posição real essencial somente para a Home PitTec do provider, portanto o bloqueio fica localizado
nessa View.

**Alternatives considered**: idênticas ao Android — coordenada mock de fallback (rejeitada pela
decisão explícita do usuário); `allowsBackgroundLocationUpdates`/tracking em background (rejeitado;
a leitura é foreground e não deve publicar nada); espera ilimitada pelo primeiro fix (rejeitada;
timeout leva a `.unavailable` com retry).

## 4. Fixtures, busca progressiva e preço

**Decision**: definir fixtures Swift determinísticas, sem JSON/arquivo externo. Cada cenário contém
candidatos ordenados por faixa de 5km e uma resposta `.accept` ou `.decline`. A tentativa principal
percorre 5, 10 e 15km para demonstrar R$ 60,00, R$ 70,00 e R$ 80,00; uma tentativa posterior esgota
os candidatos e termina em vazio. O preço usa `Int` em centavos:

```swift
let fixedCents = 5000
let bandCents = 1000
let bandCount = perimeterKm / 5
let totalCents = fixedCents + bandCents * bandCount
```

Quando a faixa se esgota após recusa, a mesma busca avança 5km, recalcula e anuncia a nova
composição; não pede uma segunda confirmação.

**Rationale**: idêntico ao racional do Android — fixtures tipadas tornam os cenários reproduzíveis;
centavos (`Int`, não `Decimal`/`Double`) evitam qualquer ambiguidade de arredondamento nesta
representação puramente local. A continuação sem reconfirmação decorre de FR-017.

**Alternatives considered**: idênticas ao Android — distância aleatória (rejeitada, tornaria SC-003/
SC-004 não reproduzíveis); seletor técnico sempre visível (rejeitado, altera a experiência inicial
que FR-011 manda preservar); congelar R$ 60,00 após ampliar para 10/15km (rejeitado, o preço
deixaria de representar a faixa em que o prestador aceito foi encontrado).

## 5. Timers e lifecycle

**Decision**: cada `@Observable` ViewModel mantém no máximo uma `Task` por responsabilidade.
Respostas automáticas bilaterais usam `Task.sleep(for: .seconds(3))` com token de revisão e
continuam mesmo se o usuário trocar de aba (a `Task` não é presa ao ciclo de vida da View, só ao
ViewModel). A simulação publica a posição inicial no aceite e, enquanto a experiência está visível,
usa `Task.sleep(for: .seconds(30))` entre os demais passos; pausa ao ocultar a experiência
(`.onDisappear`) e cancela ao concluir. Ao voltar (`.onAppear`), primeiro recalcula a idade do
último ponto e só então retoma a cadência, sem mascarar um stale. Um `Timer`/`Task` de 1s calcula
stale por `ContinuousClock` (relógio monotônico, equivalente ao `SystemClock.elapsedRealtime()` do
Android) e marca a posição após 35.000ms.

**Rationale**: idêntico ao racional do Android — eventos explícitos de visibilidade (`.onAppear`/
`.onDisappear`) mantêm o trabalho proporcional ao ciclo de vida da View; `ContinuousClock` não é
afetado por alteração manual de data/hora do sistema, ao contrário de `Date()`. Tokens e checagem do
estado impedem que `Task`s antigas apliquem transições depois de retry, recusa ou conclusão.

**Alternatives considered**: idênticas ao Android — `BGTaskScheduler`/timers de sistema (rejeitados,
são persistentes/background e imprecisos para uma demonstração em primeiro plano); loop global
sempre ativo (rejeitado, atualizaria uma View escondida e dificultaria cancelamento); `Date()` civil
para medir idade (rejeitado, ajustes do sistema podem produzir idade negativa ou saltos).

## 6. Pulso roxo e redução de movimento

**Decision**: o ViewModel expõe uma revisão de alerta e se o efeito ainda não foi consumido. A View
marca o efeito como consumido ao iniciá-lo e executa três ciclos de até 1s com
`withAnimation`/`.animation(_:value:)`, mantendo o card roxo visível durante e depois do efeito. Se
`UIAccessibility.isReduceMotionEnabled == true`, não há pulso: o card persistente aparece
imediatamente. Texto, `.accessibilityAddTraits(.isHeader)`/Live Region e botões Aceitar/Recusar
existem nas duas variantes.

**Rationale**: idêntico ao racional do Android — `UIAccessibility.isReduceMotionEnabled` é o
equivalente iOS nativo ao `MotionDurationScale.scaleFactor == 0` do Android, sem exigir nenhuma
dependência adicional. Consumir a revisão no ViewModel evita que a animação seja repetida por
recriação da View ou ao voltar à tela.

**Alternatives considered**: idênticas ao Android — animação infinita (rejeitada, distrai e excede o
requisito); inferir redução de movimento por VoiceOver ativo (rejeitado, leitor de tela não
equivale a preferência de animação); depender apenas da cor (rejeitado por acessibilidade, FR-006/
FR-031).

## 7. Mapa, distância e câmera

**Decision**: reutilizar `MapLibreMapHost`, os modelos de `MapSurfaceModels` e o
`Coordinator` de participantes já promovido/generalizado em `010`/`014` (mapa de dois pontos). O
primeiro frame aceito e o botão "Centralizar" emitem um comando de câmera revisionado para os dois
pontos. Atualizações de 30s nunca emitem comando de câmera; atualizam somente marcador, linha
direta, distância e timestamp. A distância é haversine/local e apresentada como estimada; não existe
chamada de rota real (diferente de `015`, que usa a Edge Function `pittec-route` real).

**Rationale**: idêntico ao racional do Android — o host já mantém viewport separado de comandos e
preserva gestos; não é necessário detectar o motivo do movimento, basta não gerar comando automático
nos ticks. O `Coordinator` de participantes de `014` já desenha cliente/PitTec/stale/linha
tracejada, portanto reaproveitá-lo evita duplicar integração MapLibre.

**Alternatives considered**: idênticas ao Android — reenquadrar a cada tick (rejeitado, rouba a
câmera após pan/zoom manual); reutilizar `AppointmentTrackingViewModel` real (rejeitado, ele chama
backend/rota externa reais, o que viola o isolamento desta feature); implementar roteamento mock
via Edge Function (rejeitado; linha direta e distância estimada atendem ao protótipo).

## 8. Bottom navigation e informações da sessão

**Decision**: estender `PitGoBottomTabs`/`TabView` (`002`) com uma variante `PitTecProviderTabs`
para o shell do provider PitTec, reutilizando o mesmo componente visual. O shell do provider mantém
Mapa, Dados da corrida, Valores e Perfil como conteúdos de uma única `View` com `TabView` interna
(ou um `Picker`/segmented control acima do conteúdo, mantendo a mesma identidade visual). Dados e
Valores derivam do mesmo `currentOrLastAppointment`; Perfil mostra os dados básicos já disponíveis
no `ProviderSnapshot` e logout.

**Rationale**: idêntico ao racional do Android — uma única superfície com abas preserva naturalmente
a simulação, evita quatro rotas artificiais e mantém a estrutura visual já usada pelas demais áreas
do app. O `ProfileView` do cliente (`006`/`014`) não é reutilizável porque inclui veículo, endereço
e migração específicos do cliente.

**Alternatives considered**: idênticas ao Android — quatro rotas e quatro ViewModels (rejeitadas,
fragmentariam estado local); reutilizar `ProfileView` cliente (rejeitado, dados/ações incorretos
para o provider); criar histórico/saldo (rejeitado, FR-010A exclui ambos).

## 9. Limite de rede observável

**Decision**: consideradas permitidas somente as dependências já existentes fora do protótipo:
autenticação, catálogo e carregamento do estilo/tiles do mapa (MapLibre). Nenhum evento novo do
fluxo PitTec pode chamar RPCs de descoberta/despacho, Realtime, publicação de localização, Edge
Function de rota, notificação local ou pagamento.

**Rationale**: idêntico ao racional do Android — o app ainda precisa estar autenticado e o mapa
gerenciado depende de rede para tiles; declarar essa fronteira evita prometer um app completamente
offline, enquanto garante que os dados/transições/efeitos da nova jornada sejam demonstravelmente
locais.

**Alternatives considered**: idênticas ao Android — tornar autenticação/catálogo/tiles offline
(rejeitado, fora do escopo); aceitar chamadas de leitura ao dispatch real (rejeitado, criaria
dependência e possível redirecionamento externo mesmo sem escrita).
