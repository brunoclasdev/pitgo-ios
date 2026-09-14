# Feature Specification: Aceite do PitTec com confirmação de valor e mapa conjunto

**Feature Branch**: `[021-pittec-accept-confirm-tracking]`

**Created**: 2026-09-13

**Status**: Draft

**Input**: User description: "melhoria no fluxo de contratação pitec: - Ao clicar em pitec e depois em chamar pittec, deve buscar um pittec disponivel, ao achar, vai abrir uma tela de notificação para o pittec e ele vai aceitar ou recusar. - Ao aceitar vai mostrar um card pro cliente confirmar os valores, se o cliente der o ok, o mapa vai centralizar o cliente e o pittec no mapa dos dois devices. - a localização do pittec vai ser atualizada de tempos em tempos para mostrar que o pittec esta se aproximando do cliente."

**Nota de escopo**: O pedido original também incluía um ajuste de layout da Home (posição do avatar/nome e
ordem dos cards). Por ser uma mudança visual pequena e completamente independente deste fluxo de
contratação, ela foi deixada fora desta spec — ver seção "Fora de Escopo" abaixo.

## Clarifications

### Session 2026-09-13

- Q: Enquanto o cliente ainda não confirmou o valor, o que a tela do próprio PitTec deve mostrar? →
  A: O PitTec também espera numa tela "aguardando confirmação do cliente" após aceitar; o mapa
  conjunto só aparece para os dois lados juntos, no momento da confirmação (nenhum dos dois vê o
  acompanhamento antes disso).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Confirmar o valor assim que um PitTec aceita (Priority: P1)

Como cliente, ao tocar em "Chamar PitTec" quero que a busca por um prestador comece e, assim que
algum PitTec aceitar atender, quero ver claramente o valor que vou pagar e poder confirmar antes de
qualquer outra coisa acontecer, para ter certeza do que estou aceitando antes do atendimento seguir
adiante.

**Why this priority**: É o núcleo do pedido — hoje o cliente já paga antes mesmo de a busca
começar, sem ver o valor no momento em que alguém de fato aceita atendê-lo; sem essa confirmação
pós-aceite, nenhuma das outras melhorias (mapa conjunto, atualização de posição) tem um momento
claro para começar.

**Independent Test**: Pode ser testado tocando em "Chamar PitTec", aguardando um PitTec aceitar (ou
simulando o aceite) e verificando que um card de confirmação de valor aparece para o cliente antes
do atendimento prosseguir, com opção de confirmar ou recusar.

**Acceptance Scenarios**:

1. **Given** o cliente tocou em "Chamar PitTec" e a busca está em andamento, **When** um PitTec
   elegível aceita a chamada, **Then** o cliente vê um card com o valor do atendimento e as opções
   de confirmar ou recusar, antes de ver qualquer mapa de acompanhamento.
2. **Given** o card de confirmação de valor está visível, **When** o cliente confirma, **Then** o
   atendimento prossegue para a etapa de acompanhamento (mapa conjunto).
3. **Given** o card de confirmação de valor está visível, **When** o cliente recusa, **Then** o
   atendimento é encerrado (sem prosseguir para acompanhamento) e o cliente é informado do
   encerramento.
4. **Given** o PitTec aceitou a chamada, **When** o cliente ainda não confirmou o valor, **Then** a
   tela do PitTec mostra que ele aguarda a confirmação do cliente, sem acesso ao mapa de
   acompanhamento conjunto nesse meio-tempo.
5. **Given** o PitTec está na tela de espera pela confirmação do cliente, **When** o cliente recusa
   o valor, **Then** a tela do PitTec também é encerrada/informada do cancelamento, sem nunca ter
   mostrado o mapa de acompanhamento.

---

### User Story 2 - Ver as duas posições juntas no mapa após a confirmação (Priority: P1)

Como cliente e como PitTec, depois que o cliente confirma o valor, quero que o mapa mostre as duas
posições — a minha e a da outra pessoa — enquadradas juntas na tela, para entender de imediato a
distância entre nós sem precisar mexer no mapa.

**Why this priority**: É o comportamento visual central do acompanhamento pós-aceite; sem as duas
posições enquadradas juntas, cliente e PitTec não conseguem avaliar a aproximação de forma
confiável.

**Independent Test**: Pode ser testado confirmando o valor de um atendimento aceito (em ambos os
aparelhos, cliente e PitTec) e verificando que o mapa de cada um mostra as duas posições
simultaneamente, sem exigir zoom/pan manual para enxergar as duas.

**Acceptance Scenarios**:

1. **Given** o cliente confirmou o valor de um atendimento aceito, **When** a tela de
   acompanhamento é apresentada, **Then** o mapa do cliente mostra sua própria posição e a última
   posição conhecida do PitTec, ambas visíveis ao mesmo tempo sem exigir ajuste manual de zoom.
2. **Given** o PitTec teve sua oferta aceita e o cliente confirmou o valor, **When** o PitTec abre a
   tela de acompanhamento desse atendimento, **Then** seu mapa mostra sua própria posição e a
   posição do cliente, ambas visíveis ao mesmo tempo sem exigir ajuste manual de zoom.

---

### User Story 3 - Acompanhar o PitTec se aproximando (Priority: P2)

Como cliente, enquanto aguardo o PitTec confirmado, quero ver a posição dele no mapa sendo
atualizada conforme ele se aproxima, para saber que o atendimento está de fato a caminho.

**Why this priority**: Reforça a confiança do cliente durante a espera; depende das User Stories 1 e
2 já estarem completas (confirmação e mapa conjunto), por isso vem depois na prioridade.

**Independent Test**: Pode ser testado observando o mapa do cliente por alguns minutos após a
confirmação, com o dispositivo do PitTec se movendo, e verificando que o marcador do PitTec se
desloca no mapa do cliente ao longo do tempo, sem exigir que o cliente atualize a tela manualmente.

**Acceptance Scenarios**:

1. **Given** o cliente está na tela de acompanhamento de um atendimento confirmado, **When** o
   PitTec muda de posição real, **Then** o marcador do PitTec no mapa do cliente se atualiza para
   refletir a nova posição em até o intervalo padrão já usado pelo sistema para publicação de
   localização, sem exigir nenhuma ação do cliente.

---

### Edge Cases

- O que acontece se o PitTec cancelar depois de aceitar, mas antes de o cliente confirmar o valor?
  O atendimento é encerrado da mesma forma que um cancelamento pelo prestador já é tratado hoje após
  o aceite, e o cliente é informado do cancelamento em vez de ficar preso no card de confirmação.
- O que acontece se o cliente recusar o valor confirmado? O atendimento aceito é encerrado
  reaproveitando a mesma política de cancelamento/estorno já existente para atendimentos aceitos
  (ver Assumptions).
- O que acontece se nenhum PitTec aceitar depois de esgotar toda a busca? Comportamento inalterado
  em relação ao já existente (mapa centralizado no cliente com a mensagem de busca esgotada,
  `020-pittec-client-map-centering`).
- O que acontece se a conexão do cliente ou do PitTec cair durante a espera da confirmação de valor?
  Ao reconectar, cada lado retoma o mesmo estado (card de confirmação, ou acompanhamento se a
  confirmação já tiver ocorrido do outro lado) sem duplicar cobrança ou atendimento.
- O que acontece se o PitTec ficar temporariamente sem atualizar sua posição (sinal fraco, app em
  segundo plano)? O mapa do cliente mantém a última posição conhecida do PitTec até uma nova
  atualização chegar, sem quebrar o enquadramento conjunto.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Ao tocar em "Chamar PitTec", o sistema DEVE iniciar a busca por um PitTec elegível
  disponível na região do cliente.
- **FR-002**: *(Revisado — ver nota abaixo)* A busca por um PitTec NÃO DEVE exigir nenhuma cobrança
  prévia. A cobrança do valor ofertado só DEVE ocorrer depois que o cliente confirmar o orçamento
  do atendimento aceito (FR-005/FR-006), nunca antes.

  > **Nota de implementação (2026-09-13)**: esta FR foi decidida inicialmente como "cobrança
  > continua antes da busca, como hoje" (Opção A da clarificação desta sessão), assumindo que a
  > cobrança fixa de plataforma já implementada permanecia inalterada. Durante a implementação,
  > uma migration do backend compartilhado (`20260913010000_pittec_call_tracking.sql`, já escrita
  > pelo time Android mas ainda não aplicada) foi encontrada e aplicada à nuvem nesta mesma sessão
  > — ela already redesenha o fluxo real do PitTec exatamente como a Opção B descartada na
  > clarificação: sem cobrança antes da busca, orçamento dinâmico por atendimento
  > (`quoted_price`/`quote_version`), e pagamento só depois da confirmação (`AWAITING_PAYMENT`).
  > Como o backend compartilhado com o Android é a fonte de verdade, esta FR foi atualizada para
  > refletir o comportamento real implantado, substituindo a decisão anterior.
- **FR-003**: Enquanto a busca estiver em andamento, o sistema DEVE notificar o próximo PitTec
  elegível ainda não consultado, apresentando a ele uma tela dedicada com as ações "Aceitar" e
  "Recusar" (comportamento já existente, preservado por esta funcionalidade).
- **FR-004**: Quando o PitTec recusar a chamada ou não responder a tempo, o sistema DEVE continuar a
  busca automaticamente com o próximo PitTec elegível, sem exigir nova ação do cliente
  (comportamento já existente, preservado).
- **FR-005**: Quando um PitTec aceitar a chamada, o sistema DEVE apresentar ao cliente um card de
  confirmação mostrando o valor do atendimento, antes de apresentar qualquer mapa de
  acompanhamento.
- **FR-006**: O sistema DEVE permitir que o cliente confirme ou recuse o valor apresentado nesse
  card.
- **FR-006a**: Enquanto o cliente não confirmar ou recusar o valor, o sistema DEVE manter o PitTec
  numa tela dedicada indicando que aguarda a confirmação do cliente, sem apresentar a ele o mapa de
  acompanhamento conjunto — nenhum dos dois lados vê o acompanhamento antes da confirmação.
- **FR-007**: Quando o cliente recusar o valor apresentado, o sistema DEVE encerrar o atendimento
  aceito (sem prosseguir para o acompanhamento em nenhum dos dois lados), informando tanto o cliente
  quanto o PitTec do encerramento.
- **FR-008**: Quando o cliente confirmar o valor, os mapas do cliente e do PitTec DEVEM passar a
  mostrar as posições de ambos simultaneamente, enquadradas juntas na tela, em vez de mostrar apenas
  uma posição centralizada ou depender do enquadramento padrão do mapa.
- **FR-009**: Depois da confirmação, a posição do PitTec exibida no mapa do cliente DEVE continuar
  sendo atualizada periodicamente conforme ele se desloca em direção ao cliente, reaproveitando o
  mesmo mecanismo e intervalo de publicação de localização já usados hoje para o acompanhamento
  pós-aceite.
- **FR-010**: Um PitTec com uma oferta pendente ou um atendimento aceito NÃO DEVE receber novas
  chamadas até que o atual seja concluído, recusado ou cancelado (comportamento já existente,
  preservado).

### Key Entities

- **Confirmação de valor**: novo passo entre o aceite do PitTec e o início do acompanhamento —
  representa a decisão do cliente (confirmar ou recusar) sobre o valor do atendimento já aceito.
  Existe uma única vez por atendimento aceito e é resolvida antes de qualquer mapa conjunto ser
  mostrado.
- **Atendimento PitTec** *(já existente)*: inalterado em sua identidade; passa a incluir o novo
  passo de confirmação de valor entre os estados "aceito" e "em acompanhamento".
- **Posição do PitTec** *(já existente)*: continua sendo a posição usada tanto para os marcadores de
  descoberta quanto para o acompanhamento pós-confirmação.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Em 100% dos aceites de um PitTec, o cliente vê o valor do atendimento e pode
  confirmar ou recusar antes de qualquer mapa de acompanhamento aparecer.
- **SC-002**: Em 100% das confirmações de valor, tanto o cliente quanto o PitTec veem as duas
  posições (a própria e a da outra pessoa) juntas no mapa, sem precisar ajustar zoom manualmente.
- **SC-003**: A posição do PitTec exibida ao cliente reflete uma atualização real de deslocamento em
  até o mesmo intervalo já usado hoje pelo sistema, sem exigir nenhuma ação do cliente para
  atualizar a tela.
- **SC-004**: Clientes que recusam o valor apresentado veem o atendimento encerrado e uma mensagem
  clara do motivo, em vez de uma tela travada ou sem explicação.

## Assumptions

- O ajuste de layout da Home (posição do avatar/nome, ordem dos cards) mencionado no pedido original
  é uma mudança visual pequena e independente deste fluxo de contratação; fica fora do escopo desta
  spec e deve ser tratado como uma especificação própria.
- A notificação do PitTec sobre uma nova chamada continua usando o mesmo mecanismo já existente
  (atualização em tempo real recebida enquanto o app está aberto); notificação push real com o app
  em segundo plano ou fechado não é um requisito desta funcionalidade.
- *(Revisado)* O valor apresentado no card de confirmação é o orçamento (`quoted_price`) que o
  PitTec ofertou especificamente para este atendimento — não uma tarifa fixa de plataforma —, e
  ainda não foi cobrado nesse momento; a cobrança em si só acontece depois da confirmação (FR-002).
- Recusar o valor no novo card cancela o atendimento com um motivo de sistema já tratado pelo
  próprio backend (`QUOTE_DECLINED`), sem exigir texto do cliente nem reaproveitar a sheet de
  cancelamento com motivo livre já existente para atendimentos em andamento.
- O intervalo de atualização de posição do PitTec ("de tempos em tempos") reaproveita o mecanismo e
  a cadência já implementados hoje para o acompanhamento pós-aceite, sem exigir um valor numérico
  novo.
