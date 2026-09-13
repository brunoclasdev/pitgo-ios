# Feature Specification: Mapa do PitTec sempre centralizado na localização do cliente

**Feature Branch**: `[020-pittec-client-map-centering]`

**Created**: 2026-09-13

**Status**: Draft

**Input**: User description: "ao clicar na opção pitgo: - O mapa deve centralizar na localização atual do cliente - mesmo que não tiver pittec disponivel, o mapa deve aparecer com localização do cliente centralizado."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ver o mapa centralizado ao encontrar PitTecs disponíveis (Priority: P1)

Como cliente, ao tocar no card do serviço PitTec na Home, quero que o mapa abra já centralizado na
minha localização atual, mostrando também os PitTecs elegíveis próximos, para entender de imediato
onde estou em relação aos prestadores disponíveis.

**Why this priority**: É o caminho principal do fluxo de solicitação do PitTec; sem essa
centralização o cliente não consegue avaliar a distância real até os prestadores exibidos.

**Independent Test**: Pode ser testado abrindo o mapa do PitTec em um cenário com localização
concedida e ao menos um PitTec elegível na região, verificando que a tela mostra o mapa centralizado
na posição do cliente junto com os marcadores dos prestadores, sem depender do cenário de ausência
de PitTec.

**Acceptance Scenarios**:

1. **Given** o cliente concedeu localização válida e existem PitTecs elegíveis na região, **When**
   toca no card PitTec, **Then** o mapa é apresentado já centralizado na posição atual do cliente,
   com sua própria posição identificável de forma distinta dos marcadores aproximados dos
   prestadores.
2. **Given** o mapa do PitTec já está centralizado na posição do cliente, **When** novos PitTecs
   elegíveis passam a existir na região durante a mesma sessão de busca, **Then** os novos
   marcadores aparecem no mapa sem que a posição centralizada do cliente seja perdida ou alterada.

---

### User Story 2 - Ver o mapa centralizado mesmo sem nenhum PitTec disponível (Priority: P1)

Como cliente, ao tocar no card do serviço PitTec quando não há nenhum prestador disponível na minha
região, quero ver o mapa centralizado na minha localização atual (em vez de uma tela sem mapa), para
confirmar que o app reconheceu minha posição corretamente e entender visualmente a área coberta pela
busca.

**Why this priority**: É o comportamento explicitamente solicitado e hoje ausente: sem PitTec
disponível, o cliente não vê mapa nenhum, apenas uma mensagem de texto, perdendo a referência de
onde está e de qual área foi pesquisada.

**Independent Test**: Pode ser testado abrindo o mapa do PitTec em um cenário com localização
concedida e nenhum PitTec elegível na região (tanto no início da busca quanto ao final de uma busca
que se esgota sem encontrar prestador), verificando que o mapa aparece centralizado na posição do
cliente mesmo sem nenhum marcador de prestador.

**Acceptance Scenarios**:

1. **Given** o cliente concedeu localização válida e não existe nenhum PitTec elegível na região,
   **When** toca no card PitTec, **Then** o mapa é apresentado centralizado na posição atual do
   cliente, sem nenhum marcador de prestador e sem nenhuma indicação textual de disponibilidade —
   a tela não informa proativamente se há ou não PitTec, apenas o mapa e o botão "Chamar PitTec".
2. **Given** o cliente está vendo o mapa centralizado sem nenhum PitTec disponível, **When** a busca
   percorre toda a área de cobertura sem encontrar nenhum prestador (busca esgotada), **Then** o
   mapa permanece visível e centralizado na posição do cliente junto com a mensagem de esgotamento,
   em vez de uma tela somente de texto.

---

### Edge Cases

- O que acontece quando a localização do cliente ainda não foi obtida (permissão pendente, GPS
  indisponível ou tempo esgotado) ao abrir o mapa do PitTec? O comportamento de bloqueio e
  recuperação já existente para localização ausente permanece inalterado; esta funcionalidade só se
  aplica a partir do momento em que uma localização válida do cliente está disponível.
- O que acontece se o cliente se mover fisicamente enquanto o mapa sem PitTec disponível está
  aberto? A recentralização automática contínua não é exigida por esta funcionalidade; apenas a
  centralização ao apresentar o mapa (e ao atualizar a lista de prestadores) é garantida.
- O que acontece quando o único PitTec exibido deixa de estar disponível durante a sessão, voltando
  o mapa ao estado sem prestadores? O mapa deve continuar centralizado na posição do cliente, apenas
  sem os marcadores do(s) prestador(es) que saíram.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O sistema DEVE determinar a localização atual do cliente antes de apresentar o mapa do
  serviço PitTec, reaproveitando o mesmo fluxo de permissão e obtenção de localização já usado na
  descoberta do PitTec.
- **FR-002**: O sistema DEVE centralizar o mapa do PitTec na localização atual do cliente assim que
  o mapa é apresentado, independentemente de existir ou não algum PitTec elegível disponível na
  região naquele momento.
- **FR-003**: O sistema DEVE exibir o mapa (nunca apenas uma tela de texto) quando nenhum PitTec
  elegível for encontrado na região do cliente, mantendo a posição do cliente centralizada e
  identificável.
- **FR-004**: O sistema DEVE exibir o mapa centralizado na posição do cliente também quando uma
  busca por PitTecs percorrer toda a área de cobertura e se esgotar sem encontrar nenhum prestador
  disponível, em vez de substituir o mapa por uma mensagem somente de texto.
- **FR-005**: Quando existirem PitTecs elegíveis na região, o sistema DEVE exibi-los no mesmo mapa
  centralizado no cliente, preservando a distinção visual e o nível de anonimização de posição já
  definidos para os marcadores de prestador.
- **FR-006**: O sistema NÃO DEVE comunicar proativamente na tela de descoberta se há ou não PitTec
  elegível — apenas o mapa centralizado e o botão "Chamar PitTec" são exibidos. A ausência de PitTec
  só é comunicada depois que o cliente inicia a chamada e a busca de fato se esgota (FR-004),
  nunca antes disso *(revisado após implementação inicial — a versão anterior desta FR exigia uma
  mensagem sobreposta já na descoberta; feedback do usuário durante a validação trocou isso pela
  descoberta silenciosa aqui descrita)*.
- **FR-007**: Quando novos PitTecs elegíveis surgirem ou os existentes deixarem de estar disponíveis
  durante a mesma sessão de busca, o sistema DEVE atualizar os marcadores de prestador exibidos sem
  perder ou alterar a centralização na posição do cliente.

### Key Entities

- **Localização do Cliente**: posição atual do cliente usada para centralizar o mapa do PitTec;
  existe assim que uma localização válida é obtida, independentemente de haver prestador disponível.
- **Marcador de PitTec**: posição aproximada de um prestador PitTec elegível exibida no mesmo mapa
  centralizado no cliente, podendo estar presente (zero ou mais) ou ausente sem afetar a
  centralização.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Em 100% das aberturas do mapa do PitTec com localização já concedida, o cliente vê sua
  posição atual centralizada no mapa, com ou sem PitTec disponível.
- **SC-002**: Em cenários sem nenhum PitTec disponível na região, o cliente visualiza o mapa
  centralizado em sua posição em 100% dos casos, ante 0% hoje (quando apenas uma mensagem de texto é
  exibida).
- **SC-003**: O tempo entre a localização do cliente ser obtida e o mapa aparecer centralizado não
  aumenta em relação ao tempo observado hoje no cenário em que há PitTec disponível.
- **SC-004**: Quando a disponibilidade de PitTec muda durante a mesma sessão de busca (novo
  prestador surge ou o único prestador existente some), 100% das atualizações preservam a
  centralização na posição do cliente sem exigir nova ação do usuário.

## Assumptions

- Esta funcionalidade se aplica exclusivamente à experiência de mapa do serviço PitTec (aberta a
  partir do card PitTec na Home do cliente); o mapa genérico de busca de outros prestadores/serviços
  não faz parte deste escopo.
- O comportamento já existente para localização negada, desativada ou indisponível (mapa bloqueado
  com ações de recuperação) permanece inalterado; esta funcionalidade só passa a valer a partir do
  momento em que uma localização válida do cliente é obtida.
- Centralizar significa posicionar o mapa na localização atual do cliente ao apresentar a tela e ao
  atualizar a lista de prestadores; não é exigido recentralizar continuamente caso o cliente se
  mova fisicamente com o mapa aberto.
- A mensagem de "nenhum PitTec disponível" e a mensagem de busca esgotada continuam existindo, porém
  apresentadas junto ao mapa centralizado (por exemplo, em um aviso sobreposto ou complementar), e
  não mais como tela substituta sem mapa.
