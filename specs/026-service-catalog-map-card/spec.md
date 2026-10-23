# Feature Specification: Catálogo de serviços por categoria e mapa PitTec

**Feature Branch**: `026-service-catalog-map-card`

**Created**: 2026-10-22

**Status**: Draft

**Origin**: Porte do `specs/026-service-catalog-map-card` do app Android (mesmo backend Supabase
compartilhado, projeto `eetbrkznuqbdrnybnyhf`). O catálogo, as migrations e as RPCs já existem e já
estão em produção — este documento adapta apenas o comportamento de cliente (iOS/SwiftUI) ao
contrato já vigente, sem repetir trabalho de backend.

**Input**: User description: "Refinamento de serviços e categorias de serviços. Quando o provider
escolher o serviço que vai prestar, deve existir uma lista de serviços dentro da categoria
escolhida. Uma borracharia pode oferecer apenas conserto de pneus ou também venda de rodas, por
exemplo. Para cada categoria haverá vários serviços para o provider escolher, com até 15 serviços
por categoria. Na tela do PitTec, depois que o pagamento for aprovado e o PitTec estiver indo até o
cliente, o card atual fica na frente e atrapalha a visualização do mapa; ajustar isso."

## Clarifications

Herdadas da especificação original (Android, sessão 2026-09-29) — nenhuma nova clarificação foi
necessária para o porte iOS, pois o contrato de backend já está fixado:

- Um prestador fixo escolhe uma única categoria principal; pode selecionar vários serviços dentro
  dela.
- O limite de 15 serviços vale para a carga inicial de cada categoria; a gestão do catálogo pode
  adicionar mais depois.
- No resumo compacto do acompanhamento PitTec, cancelar só fica visível quando o resumo é
  expandido.
- Somente administradores/equipe autorizada do catálogo adicionam, editam ou desativam serviços
  após a carga inicial (fora do app cliente — gerenciado diretamente no backend).
- Até 15 especialidades selecionáveis por categoria na carga inicial, excluindo os serviços
  implícitos Guincho/PitTec da contagem; essas especialidades são ofertas de prestadores fixos.
- Marcadores e rota do PitTec devem se enquadrar na área livre acima do resumo na abertura ou
  recentralização; pan/zoom manual do cliente deve ser preservado nas atualizações.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Prestador escolhe serviços específicos da categoria (Priority: P1)

Como prestador fixo, quero escolher uma categoria e selecionar somente os serviços que realmente
ofereço, para que os clientes encontrem uma oferta precisa e eu não seja apresentado como capaz de
realizar serviços que não presto.

**Why this priority**: A escolha detalhada é a finalidade principal do refinamento do cadastro e
afeta diretamente a qualidade da busca e da comparação de prestadores.

**Independent Test**: Iniciar o cadastro de um prestador fixo no app iOS, escolher a categoria
Borracharia, selecionar dois serviços e concluir o cadastro; verificar que apenas os dois serviços
escolhidos ficam associados ao prestador.

**Acceptance Scenarios**:

1. **Given** um prestador fixo na etapa de serviços, **When** ele escolhe uma categoria principal,
   **Then** a tela apresenta somente os serviços ativos daquela categoria para seleção.
2. **Given** uma categoria com vários serviços, **When** o prestador seleciona alguns e confirma,
   **Then** cada seleção aparece como uma oferta separada e pode receber seus próprios dados de
   atendimento, conforme as regras atuais do cadastro.
3. **Given** um prestador que não oferece todos os serviços da categoria, **When** ele conclui o
   cadastro, **Then** os serviços não selecionados não são associados ao prestador nem exibidos
   como ofertas dele.
4. **Given** um prestador que adicionou uma oferta, **When** ele tenta adicionar o mesmo serviço
   novamente, **Then** o sistema impede a duplicação e informa que o serviço já foi adicionado.
5. **Given** um prestador que já selecionou serviços de uma categoria, **When** ele troca a
   categoria principal, **Then** o app pede confirmação antes de descartar as ofertas atuais; se
   ele cancelar a confirmação, o rascunho permanece intacto.

### User Story 2 - Catálogo mantém opções úteis por categoria (Priority: P1)

Como responsável pelo catálogo, quero que cada categoria comece com uma lista clara de até 15
serviços específicos, para que o prestador consiga escolher com rapidez e o cliente veja nomes
compreensíveis, mantendo a possibilidade de ampliar o catálogo depois.

**Why this priority**: Sem um catálogo consistente, a nova etapa de seleção não produz uma oferta
confiável.

**Independent Test**: No app iOS, abrir a seleção de categoria no cadastro e confirmar que a
mesma lista já publicada pelo backend (compartilhado com o Android) é apresentada, sem necessidade
de nenhuma migration adicional neste porte.

**Acceptance Scenarios**:

1. **Given** uma categoria ativa, **When** o catálogo é consultado pelo app iOS, **Then** seus
   serviços ativos são listados agrupados nessa categoria, sem serviços de outra categoria.
2. **Given** uma categoria sem serviços ativos, **When** o prestador abre a seleção, **Then** a
   tela informa que não há opções disponíveis e não permite concluir uma oferta vazia.
3. **Given** uma seleção que deixou de existir entre a leitura e o envio, **When** o prestador
   confirma o cadastro, **Then** o app recebe `CATALOG_CHANGED` do backend e orienta o prestador a
   revisar a oferta, sem reescrever a RPC já existente.

### User Story 3 - Cliente acompanha o PitTec com mapa desobstruído (Priority: P1)

Como cliente, depois de pagar e enquanto o PitTec se desloca até mim, quero enxergar o mapa e o
trajeto com clareza, mantendo apenas o resumo necessário do atendimento disponível para consulta.

**Why this priority**: A visualização do deslocamento é a principal informação desse estado; um
card grande sobre o mapa reduz a confiança e dificulta acompanhar a chegada.

**Independent Test**: No app iOS, criar uma solicitação PitTec, aprovar o pagamento e abrir o
acompanhamento enquanto o prestador está em `ACCEPTED`; verificar que o mapa permanece visível e
que o resumo não encobre os marcadores nem o trajeto principal.

**Acceptance Scenarios**:

1. **Given** o pagamento aprovado e o PitTec em deslocamento, **When** a tela de acompanhamento é
   exibida, **Then** o mapa ocupa a área principal e o resumo aparece em formato compacto na borda
   inferior, com os marcadores e a rota enquadrados na área livre acima do resumo ao abrir ou
   recentralizar o mapa.
2. **Given** o resumo compacto visível, **When** o cliente toca nele, **Then** o sistema expande os
   detalhes do atendimento sem sair do mapa e oferece uma ação clara para recolhê-los novamente.
3. **Given** o cliente movimentou ou aproximou o mapa, **When** a posição do PitTec é atualizada,
   **Then** a atualização não força o mapa de volta para uma posição que esconda a visualização
   escolhida pelo cliente.
4. **Given** a solicitação muda para chegada, andamento ou estado terminal, **When** o estado é
   atualizado, **Then** o resumo muda para o texto e as ações correspondentes sem recuperar o
   layout obstrutivo do estado anterior.

### Edge Cases

- Se uma categoria ultrapassar 15 serviços depois da expansão autorizada do catálogo (já feita no
  backend compartilhado), o app iOS exibe todos os serviços ativos recebidos, sem lógica de corte
  no cliente.
- Se um serviço selecionado for desativado ou removido do catálogo antes do envio do cadastro, o
  envio deve ser bloqueado (`CATALOG_CHANGED`) e o prestador deve ser orientado a revisar a
  seleção.
- Se o catálogo não carregar, o prestador deve receber uma mensagem compreensível e não pode
  concluir o cadastro com uma seleção não validada.
- Se o mapa não tiver rota pronta ou perder temporariamente a localização, o mapa deve continuar
  utilizável, mostrar o estado aproximado quando possível e manter o resumo compacto.
- Se o cliente tocar em uma ação enquanto o card estiver expandido, a ação deve permanecer
  acessível e o resultado deve ser comunicado sem esconder o mapa de forma permanente.
- No estado compacto do PitTec, o cliente deve ver o status e a informação de deslocamento; a ação
  de cancelar só deve aparecer após a expansão do resumo.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O app DEVE apresentar, na etapa de cadastro de prestador fixo, uma única categoria
  principal por prestador e, somente após escolhida, os serviços pertencentes a ela.
- **FR-002**: O app DEVE permitir que o prestador selecione um ou mais serviços da categoria
  escolhida, respeitando as validações atuais de preço, duração e serviço obrigatório.
- **FR-003**: O app DEVE impedir que o mesmo serviço seja adicionado mais de uma vez ao mesmo
  cadastro e DEVE permitir remover uma seleção antes do envio.
- **FR-004**: O app DEVE enviar à RPC existente (`create_provider_registration`) somente os serviços
  selecionados pelo prestador, sem campo de categoria por oferta (a categoria é resolvida pelo
  backend a partir do `service_id`, já é assim no contrato vigente).
- **FR-005**: Trocar a categoria principal já selecionada DEVE exigir confirmação explícita do
  prestador antes de descartar as ofertas atuais; cancelar a confirmação preserva o rascunho.
- **FR-006**: O app DEVE revalidar categoria/serviços imediatamente antes do envio, reaproveitando a
  resposta `CATALOG_CHANGED` já tratada pelo repositório existente.
- **FR-007**: As regras existentes para prestadores Móvel e PitTec, que recebem serviço implícito e
  não fazem seleção manual nem escolhem categoria, DEVEM continuar válidas e inalteradas.
- **FR-008**: Após o pagamento aprovado, quando o PitTec estiver em deslocamento no estado
  `ACCEPTED`/`IN_PROGRESS`, a tela DEVE exibir o mapa como conteúdo principal (ocupando toda a área
  disponível) e manter o resumo do atendimento compacto, ancorado na borda inferior, sem reduzir a
  área do mapa.
- **FR-009**: O resumo do acompanhamento DEVE mostrar no estado compacto apenas o status e a
  informação essencial de distância ou chegada; a ação de cancelar e os demais detalhes devem
  ficar disponíveis somente ao expandir.
- **FR-010**: O cliente DEVE conseguir expandir e recolher o resumo tocando nele, sem abandonar o
  mapa; o estado expandido não pode impedir o acesso às ações nem ocultar permanentemente os
  marcadores e o trajeto.
- **FR-011**: A tela DEVE preservar a posição manual do mapa (pan/zoom) durante atualizações de
  localização, reenquadrando os marcadores e a rota somente na abertura inicial do estado
  `ACCEPTED`/`IN_PROGRESS` ou quando o cliente tocar explicitamente em "Centralizar".
- **FR-012**: O enquadramento inicial e o de recentralização DEVEM considerar a altura real do
  resumo (compacto ou expandido) como margem inferior, para não esconder marcadores atrás do
  painel.
- **FR-013**: O mapa e o resumo DEVEM continuar acessíveis com aumento de fonte, descrição de
  conteúdo equivalente ao estado visual (expandido/recolhido) e áreas de toque de ao menos 44pt.

### Key Entities *(include if feature involves data)*

- **Categoria de serviço / Serviço de catálogo / Oferta do prestador**: entidades já existentes no
  backend compartilhado (`service_categories`, `services`, `provider_services`); nenhuma mudança de
  schema é necessária neste porte.
- **Rascunho de cadastro (`ProviderRegistrationDraft`)**: ganha `primaryCategoryID` único,
  substituindo o `categoryID` por oferta usado antes deste porte.
- **Resumo de acompanhamento PitTec**: painel compacto ou expandido (`summaryExpanded`) que
  apresenta status, distância e ações sem substituir o mapa.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Em 100% dos cadastros de prestadores fixos no app iOS, a lista apresentada após
  escolher uma categoria contém somente serviços daquela categoria.
- **SC-002**: Em 100% dos cadastros concluídos, o prestador fica associado somente aos serviços que
  confirmou, sem duplicações.
- **SC-003**: Em 100% dos acompanhamentos PitTec no estado `ACCEPTED`/`IN_PROGRESS`, o cliente
  consegue ver os dois marcadores e a rota/estimativa na área útil livre acima do resumo compacto ao
  abrir ou recentralizar o mapa, quando as localizações estiverem disponíveis.
- **SC-004**: Após pan/zoom manual, a posição escolhida pelo cliente prevalece em atualizações
  subsequentes de localização, mesmo que os marcadores saiam da área visível.
- **SC-005**: O cliente encontra status e distância do acompanhamento em até uma interação a partir
  da tela do mapa, e encontra a ação de cancelar em até uma interação adicional após expandir o
  resumo.

## Assumptions

- O backend (Supabase, projeto `eetbrkznuqbdrnybnyhf`) é compartilhado entre Android e iOS; as
  migrations, RPCs e o catálogo inicial já foram aplicados pelo porte Android original — este
  documento cobre apenas a adaptação do cliente iOS ao contrato já vigente.
- A gestão do catálogo (criar/editar/desativar categorias e serviços) é restrita a administradores e
  é feita fora dos apps cliente (Android/iOS); nenhuma tela de gestão é construída neste porte.
- Preço, duração, serviço gratuito e demais dados da oferta continuam seguindo as validações já
  existentes do cadastro de prestador iOS.
