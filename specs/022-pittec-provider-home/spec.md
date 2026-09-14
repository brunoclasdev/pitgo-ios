# Feature Specification: Home do PitTec

**Feature Branch**: `022-pittec-provider-home`

**Created**: 2026-09-14

**Status**: Draft

**Input**: User description: "Melhoria na tela home do pittec logado.
- Deve aparecer o mapa com a localização atual do pitgo, atualizado de tempos em tempos.
- No topo deve aparecer um card informando se o pittec esta disponivel ou indisponivel
- e no bottom deve aparecer uma barra com 4 opções, Mapa, Dados da corrida, Valores e Perfil"

## Clarifications

### Session 2026-09-14

- Q: Na aba "Valores", o PitTec deve conseguir editar o preço do atendimento PitTec por ali, ou a aba só mostra o valor já configurado, sem edição? → A: Só exibir — sem edição por esta tela.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ver minha posição e disponibilidade de relance (Priority: P1)

Um prestador logado como PitTec abre o app e, na tela inicial, vê imediatamente um mapa centralizado na sua própria localização atual e um card no topo dizendo se ele está "Disponível" ou "Indisponível" para receber solicitações — sem precisar rolar a tela ou navegar para outro lugar.

**Why this priority**: É a informação que o PitTec mais precisa confirmar a cada abertura do app — "estou visível pros clientes agora?" e "o app sabe onde eu estou?". Sem isso, o resto da tela não tem contexto.

**Independent Test**: Abrir o app logado como PitTec e verificar que o mapa aparece centralizado na posição atual do dispositivo e que o card de disponibilidade reflete o estado real (disponível/indisponível) sem nenhuma outra ação.

**Acceptance Scenarios**:

1. **Given** um PitTec logado e com permissão de localização concedida, **When** ele abre a tela inicial, **Then** o mapa aparece centralizado na posição atual do dispositivo e o card no topo mostra "Disponível" ou "Indisponível" de acordo com o estado real salvo no servidor.
2. **Given** a tela inicial já aberta e o PitTec disponível, **When** algum tempo passa enquanto o dispositivo se move, **Then** o mapa atualiza a posição exibida periodicamente, sem exigir que o usuário puxe para atualizar ou reabra a tela.
3. **Given** o PitTec está indisponível, **When** ele toca no card de disponibilidade, **Then** ele consegue alternar para disponível diretamente por ali.

---

### User Story 2 - Navegar entre mapa, corrida ativa, valores e perfil (Priority: P2)

Um PitTec usa a barra inferior com 4 opções (Mapa, Dados da corrida, Valores, Perfil) para alternar rapidamente entre a visão do mapa, os detalhes do atendimento em andamento (quando houver um), o preço que ele cobra pelo serviço PitTec, e as informações da sua conta — do mesmo jeito que já funciona hoje no aplicativo Android da mesma empresa.

**Why this priority**: Consolida em um só lugar, sempre acessível, tarefas que hoje exigem navegação avulsa (ex.: sair da conta, ver preço) — mas só faz sentido depois que a tela de mapa (US1) já existe.

**Independent Test**: Com a tela inicial aberta, tocar em cada uma das 4 opções da barra inferior e confirmar que cada uma mostra o conteúdo esperado (mapa / corrida ativa ou aviso de que não há corrida / preço configurado / dados de perfil e opção de sair), mantendo a barra visível em todas elas.

**Acceptance Scenarios**:

1. **Given** a tela inicial aberta na aba "Mapa", **When** o PitTec toca em "Dados da corrida", **Then** a aba muda e mostra os detalhes do atendimento aceito no momento, ou um aviso de que ainda não há nenhum atendimento em andamento.
2. **Given** a tela inicial aberta, **When** o PitTec toca em "Valores", **Then** ele vê o preço configurado para o seu atendimento PitTec.
3. **Given** a tela inicial aberta, **When** o PitTec toca em "Perfil", **Then** ele vê seus dados de conta e consegue encerrar a sessão a partir dali.
4. **Given** o PitTec está em qualquer uma das 4 abas, **When** chega uma nova solicitação de atendimento, **Then** ele é avisado (como já acontece hoje) independentemente de qual aba estiver aberta.

---

### Edge Cases

- O que acontece se a permissão de localização for negada ou os serviços de localização estiverem desligados? O card de disponibilidade e o mapa devem comunicar isso claramente, sem travar a tela num carregamento infinito.
- O que acontece se o PitTec estiver com um atendimento em andamento (aceito) e tocar na aba "Mapa"? O mapa continua mostrando a posição do próprio PitTec (não substitui a tela dedicada de acompanhamento do atendimento).
- O que acontece se a localização não puder ser obtida por alguns instantes (ex.: sinal de GPS fraco)? O mapa deve manter a última posição conhecida em vez de ficar em branco.
- O que acontece se o PitTec estiver numa modalidade diferente de PitTec (Fixo ou Móvel)? Essa tela com abas é exclusiva de quem está na modalidade PitTec — outras modalidades continuam com a tela atual.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A tela inicial de um prestador na modalidade PitTec MUST exibir um mapa centralizado na localização atual do próprio dispositivo do prestador.
- **FR-002**: O mapa MUST atualizar a posição exibida periodicamente enquanto a tela estiver aberta, refletindo o deslocamento real do dispositivo, sem exigir uma ação manual do usuário para atualizar.
- **FR-003**: A tela inicial MUST exibir, no topo, um card indicando claramente se o prestador está "Disponível" ou "Indisponível" para receber novas solicitações, sempre refletindo o estado atual salvo no servidor.
- **FR-004**: O card de disponibilidade MUST permitir alternar entre disponível e indisponível diretamente, sem navegar para outra tela.
- **FR-005**: A tela inicial MUST exibir uma barra de navegação fixa na parte inferior com exatamente 4 opções, nesta ordem: Mapa, Dados da corrida, Valores, Perfil.
- **FR-006**: A opção "Mapa" MUST mostrar o mapa com a localização atual descrito em FR-001/FR-002 e o card de disponibilidade descrito em FR-003/FR-004.
- **FR-007**: A opção "Dados da corrida" MUST mostrar os detalhes do atendimento PitTec aceito no momento (se houver um em andamento) ou uma mensagem indicando que não há nenhum atendimento em andamento.
- **FR-008**: A opção "Valores" MUST mostrar, somente para consulta (sem edição por esta tela), o preço configurado para o atendimento PitTec do prestador.
- **FR-009**: A opção "Perfil" MUST mostrar os dados de conta do prestador e permitir encerrar a sessão.
- **FR-010**: Notificações de novas solicitações de atendimento MUST continuar chegando ao prestador independentemente de qual das 4 opções esteja em primeiro plano no momento.
- **FR-011**: Quando a localização não estiver disponível (permissão negada, serviço desligado, ou sinal momentaneamente perdido), a tela MUST comunicar esse estado no lugar do mapa/card de disponibilidade em vez de ficar carregando indefinidamente, mantendo a última posição conhecida quando existir uma.
- **FR-012**: Esta tela com as 4 opções é exclusiva de prestadores na modalidade PitTec — prestadores nas modalidades Fixo ou Móvel MUST continuar vendo a tela inicial atual, sem as 4 opções.

### Key Entities *(include if feature involves data)*

- **Disponibilidade do prestador**: estado (disponível/indisponível) já existente hoje na conta do prestador — esta tela apenas o exibe com mais destaque e permite alterá-lo do mesmo lugar.
- **Localização atual do prestador**: posição geográfica do próprio dispositivo do prestador, já capturada hoje para fins de despacho — esta tela apenas a exibe visualmente num mapa.
- **Atendimento PitTec ativo**: o atendimento aceito em andamento (se houver), incluindo seus dados principais para exibição em "Dados da corrida".
- **Preço do PitTec**: o valor configurado que o prestador cobra pelo atendimento PitTec, exibido em "Valores" apenas para consulta (a edição desse valor, se vier a existir, fica fora do escopo desta melhoria).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Um PitTec consegue confirmar sua disponibilidade atual e ver sua posição no mapa em menos de 2 segundos após abrir o app, sem nenhum toque adicional.
- **SC-002**: A posição exibida no mapa reflete a localização real do dispositivo com no máximo alguns segundos de atraso, mesmo com o dispositivo em movimento.
- **SC-003**: Um PitTec consegue alternar entre as 4 opções da barra inferior e voltar para o mapa em menos de 3 toques no total, a partir de qualquer uma delas.
- **SC-004**: 100% das notificações de novas solicitações continuam chegando ao PitTec independentemente de qual das 4 opções ele estava usando no momento.

## Assumptions

- Esta melhoria se aplica somente à modalidade PitTec (`location_mode = PITTEC`); prestadores nas modalidades Fixo e Móvel continuam com a tela inicial atual, sem alterações.
- A captura e o envio periódico da localização do prestador para fins de despacho já existem hoje no sistema; esta funcionalidade reaproveita essa mesma posição para exibição visual, sem criar uma nova fonte de localização.
- O aviso de novas solicitações de atendimento (hoje já existente) continua funcionando como está — esta melhoria não altera como/quando o prestador é avisado, só onde ele consegue ver o restante das informações.
- "Dados da corrida" mostra, no máximo, um atendimento ativo por vez (o modelo atual já não permite mais de um atendimento aceito simultâneo por prestador).
