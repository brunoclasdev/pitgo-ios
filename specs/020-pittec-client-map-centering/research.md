# Phase 0 Research: Mapa do PitTec sempre centralizado na localização do cliente

Nenhum item do Technical Context ficou marcado como `NEEDS CLARIFICATION` — a spec e a exploração
do código existente já eram suficientes para decidir a abordagem técnica. As decisões abaixo
documentam a investigação feita no código atual (não no backend, que não muda).

## 1. Onde obter a posição do cliente para centralizar o mapa

**Decision**: Reaproveitar o fix de localização já obtido por
`PitTecClientViewModel.loadDiscovery()` (`requestOneShotFix(timeout: 15)`), hoje guardado apenas em
`private var lastFix: DeviceLocationFix?`. Expor essa propriedade como `private(set)` para a View
ler, no mesmo padrão já usado por `routeContext` na mesma ViewModel.

**Rationale**: O fix já existe e já é reutilizado por `callPitTec(requestID:)` — não é necessário
pedir um novo fix, uma nova permissão nem introduzir um segundo caminho de obtenção de localização.
`DeviceLocationFix` é uma struct simples (`latitude`/`longitude`/`horizontalAccuracy`/`timestamp`),
sem acoplamento a `CLLocationManager`, segura para a View consumir.

**Alternatives considered**:
- *Pedir um novo fix só para centralizar o mapa*: rejeitado — duplicaria uma chamada já feita,
  adicionaria latência e uma segunda fonte de verdade para a mesma posição.
- *Embutir a coordenada em cada caso do `enum PitTecClientUiState`* (como `ServiceMapUiState.content`
  faz com `MapViewport`): rejeitado para esta correção pontual — exigiria reestruturar todos os
  casos do enum (`discovering`, `content`, `terminal`, `failure`) só para dois deles precisarem da
  coordenada, na contramão do princípio de simplicidade (I). O padrão já existente de expor um
  campo lateral read-only na ViewModel (`routeContext`) resolve com uma mudança muito menor.

## 2. Como apresentar mapa + mensagem de "sem PitTec" ao mesmo tempo

**Decision**: Trocar a exibição de `emptyDiscoveryState` (tela substituta) por `PitGoMapView`
sempre visível, com a mensagem informativa sobreposta (mesmo padrão visual já usado por
`MapAttributionView` como overlay sobre o mapa).

**Rationale**: A spec (FR-003, FR-006) exige que a ausência de PitTec seja comunicada em conjunto
com o mapa, não em substituição a ele. Sobrepor a mensagem preserva o layout existente
(`PitGoMapView` + `callButton` abaixo) sem introduzir um novo tipo de tela.

**Alternatives considered**:
- *Mapa pequeno + texto abaixo em vez de sobreposição*: funcionalmente equivalente; sobreposição foi
  escolhida por reaproveitar o padrão de overlay já usado nesta mesma tela (`MapAttributionView`) em
  vez de introduzir um novo layout.

## 3. Estender a correção ao estado de busca esgotada (`terminal`, `status == .exhausted`)

**Decision**: Sim — `terminalState(_:)` passa a renderizar `PitGoMapView` centralizado no cliente
(via o mesmo `lastFix` exposto) quando `snapshot.status == .exhausted`, mantendo a mensagem/ações
terminais (`"Buscar novamente"`, `"Voltar"`) sobrepostas. Os demais status terminais
(`.completed`, `.cancelled`) continuam com a tela só-texto atual.

**Rationale**: A segunda frase do pedido do usuário ("mesmo que não tiver pittec disponível") e o
Acceptance Scenario 2 da User Story 2 da spec cobrem explicitamente o caso de busca esgotada, que
hoje também não mostra mapa. `lastFix` permanece em memória na ViewModel após a transição de
`.discovering` para `.content`/`.terminal` (nunca é limpo nesse caminho), então nenhum novo fix
precisa ser pedido.

**Alternatives considered**:
- *Deixar a busca esgotada fora de escopo, corrigindo só a descoberta inicial*: rejeitado — contraria
  o pedido explícito do usuário e o Acceptance Scenario 2 da spec.
- *Pedir um novo fix no momento do estado terminal*: rejeitado pelo mesmo motivo do item 1 (fix já
  disponível em memória).

## 4. Escopo em relação ao mapa genérico de outros serviços (`ServiceMapView`)

**Decision**: Não alterar `ServiceMapView`/`ServiceMapViewModel` nesta feature, mesmo having o mesmo
gap (estado `.empty` também substitui o mapa por uma tela só-texto).

**Rationale**: A spec (`Assumptions`) delimita o escopo explicitamente ao mapa do serviço PitTec —
a segunda frase do pedido do usuário cita "pittec" nominalmente. Estender ao mapa genérico exigiria
uma nova decisão de produto (fora desta spec) e um plano de teste próprio.

**Alternatives considered**:
- *Corrigir os dois mapas juntos, já que o bug é idêntico*: rejeitado para esta spec — manteria o
  escopo pequeno e revisável; pode virar uma spec própria depois, reaproveitando esta mesma decisão
  de design (registrado aqui para referência futura).
