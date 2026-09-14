# Research: Home do PitTec

Sem itens `NEEDS CLARIFICATION` pendentes no Technical Context — todas as decisões abaixo se
apoiam em infraestrutura já existente no app, confirmada por leitura direta do código nesta sessão.

## 1. Fonte da posição exibida no mapa

**Decision**: reaproveitar o mesmo fluxo de localização já usado por `ProviderDiscoveryTracker`
para publicar a posição do PitTec no servidor (`DeviceLocationRepository.
startHighPrecisionUpdates()`), expondo o último `DeviceLocationFix` recebido como
`private(set)` na própria tracker (ou em um wrapper fino da nova `PitTecHomeViewModel`).

**Rationale**: `ProviderDiscoveryTracker` já mantém um `Task` consumindo o `AsyncStream` de fixes
enquanto o PitTec está disponível (`updatesTask`, publicando a cada 10s via `publishInterval`). Pedir
um segundo fluxo de localização (ex.: um novo `CLLocationManager`/stream paralelo só para exibição)
duplicaria permissão, bateria e uma segunda fonte de verdade para "onde o PitTec está agora" — a
Assumption do spec.md já veta isso explicitamente.

**Alternatives considered**:
- Um `DeviceLocationRepository.requestOneShotFix` disparado pela própria View a cada abertura de
  tela: rejeitado — não atualiza "de tempos em tempos" (FR-002) sem um timer adicional, duplicando
  o timer que a tracker já tem.
- Ler a posição de volta do servidor (`provider_discovery_locations`) via poll: rejeitado — adiciona
  uma chamada de rede redundante só para mostrar uma posição que o próprio dispositivo já sabe com
  mais precisão e menos atraso do que o round-trip ao servidor.

## 2. Card de disponibilidade

**Decision**: reaproveitar `ProviderDashboardRepository.setAvailability(_:)` (já usado por
`ProviderDashboardViewModel.setAvailability`) a partir da nova `PitTecHomeViewModel`, e reaproveitar
`ProviderSnapshot.provider.available` como fonte de verdade — sem nova RPC nem novo campo.

**Rationale**: é a mesma coluna (`providers.available`) e a mesma RPC de configurações já usada na
tela atual; a única mudança é de apresentação (card fixo no topo em vez de `Toggle` no meio de um
`ScrollView`).

**Alternatives considered**: nenhuma — não há ambiguidade técnica aqui, só de layout.

## 3. Preço exibido em "Valores"

**Decision**: nova `PitTecPricingRepository` fina que lê `provider_services` diretamente via
Postgrest (mesmo padrão de `ProviderRegistrationRepository.fetchOwnAggregate`), filtrando pelo
`provider_id` do PitTec e pelo serviço cujo `services.dispatch_kind = PITTEC_AUTO_SEQUENTIAL`
(reaproveitando `ProviderRegistrationRepository.fetchImplicitService` como referência de como esse
filtro já é feito). Somente leitura, conforme a clarificação registrada em spec.md.

**Rationale**: a modalidade PitTec sempre tem exatamente um serviço implícito por design (`016`),
então não há necessidade de paginação nem de uma tela de lista — uma única leitura basta.

**Alternatives considered**:
- Expor edição de preço nesta mesma tela: descartado pela clarificação (fora de escopo desta
  entrega).
- Reaproveitar `ProviderRegistrationRepository.fetchOwnAggregate` inteiro (que também traz
  endereço e todos os serviços): rejeitado — traria dados e chamadas desnecessários para o que é
  só "qual o preço do meu PitTec", violando a simplicidade/YAGNI.

## 4. "Dados da corrida"

**Decision**: a aba mostra um resumo do atendimento PitTec ativo (`PENDING`,
`AWAITING_CLIENT_CONFIRMATION`, `AWAITING_PAYMENT`, `ACCEPTED` ou `IN_PROGRESS`) obtido do mesmo
`PitTecRepository.getActiveDispatch()` já usado por `ProviderDashboardViewModel.checkPitTecIncoming`,
ou uma mensagem vazia quando não há nenhum. Uma solicitação **nova** (`PENDING`) continua dirigindo o
usuário para a tela de aceitar/recusar já existente (`PitTecIncomingRequestView`, hoje aberta via
push automático) — a aba não substitui esse fluxo, só reflete o estado quando ele já foi aberto e
está em andamento.

**Rationale**: preserva 100% o comportamento de notificação/aceite já existente (FR-010, SC-004) e
evita duplicar a tela de aceitar/recusar dentro de uma aba, o que exigiria repensar como um
`swipe`/toque em outra aba interage com um cronômetro de resposta ativo — risco de regressão sem
benefício adicional.

**Alternatives considered**: embutir a tela de aceitar/recusar inteira dentro da aba (sem navegação
separada) — rejeitado por aumento de complexidade sem ganho descrito no spec; o pedido original só
fala em "aparecer" as 4 opções, não em redesenhar o fluxo de aceite.

## 5. Barra inferior de 4 abas

**Decision**: generalizar `Core/UI/PitGoBottomTabs` para aceitar qualquer tipo de item (protocolo
com `title`/`symbolName`/`CaseIterable`/`Hashable`) em vez do `BottomItemID` fixo de 5 itens do
cliente, e criar um novo `PitTecHomeTab: CaseIterable, Hashable` com os 4 casos desta feature.

**Rationale**: o componente já é estruturalmente genérico (só a assinatura força o enum do
cliente) — generalizar é uma mudança pequena e sem risco (o cliente continua usando exatamente o
mesmo `BottomItemID` de hoje) e evita duplicar toda a montagem de `TabView`/`tabItem`/`Label` numa
segunda cópia quase idêntica, o que a constituição desencoraja (DRY quando a duplicação não tem
responsabilidade própria).

**Alternatives considered**: duplicar `PitGoBottomTabs` como `PitTecBottomTabs` — rejeitado por
duplicação sem responsabilidade distinta, indo contra a constituição.

## 6. Onde decidir PitTec vs Fixo/Móvel

**Decision**: o ponto de decisão fica em `PitGoRootView`, no mesmo `case let
.authenticatedProviderReady(snapshot)` que hoje sempre instancia `ProviderDashboardView` — passa a
checar `snapshot.provider.locationMode == .pittec` e instanciar `PitTecHomeView` nesse caso,
mantendo `ProviderDashboardView` para os demais.

**Rationale**: é o único lugar que já monta todas as dependências do provider (repositories,
`accountID`, `providerID`) a partir da sessão — inserir a bifurcação ali evita duplicar essa
montagem em um segundo ponto de entrada.

**Alternatives considered**: bifurcar dentro da própria `ProviderDashboardView`: rejeitado — essa
View já tem uma responsabilidade única (dashboard de Fixo/Móvel) e misturar dois layouts totalmente
diferentes (scroll simples vs. `TabView` de 4 abas) no mesmo `body` prejudicaria a legibilidade sem
necessidade, já que `PitGoRootView` já é o lugar natural para escolher a "casca" certa por sessão
(mesmo padrão usado para escolher entre `ClientMainTabView` e telas de auth/onboarding).
