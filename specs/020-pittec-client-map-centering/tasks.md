---

description: "Task list template for feature implementation"
---

# Tasks: Mapa do PitTec sempre centralizado na localização do cliente

**Input**: Design documents from `/specs/020-pittec-client-map-centering/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Não solicitados para esta feature (regra V da constituição) — validação manual via
`quickstart.md`, referenciada na Fase de Polish.

**Organization**: Tarefas agrupadas por user story para implementação e teste independentes.

**Nota sobre fases**: não há Fase de Setup — a feature reaproveita infraestrutura já existente
(`PitGoMapView`, `DeviceLocationRepository`) e não introduz projeto, dependência ou ferramenta
nova (ver `plan.md`/`research.md`). A numeração começa direto na Fase Foundational.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Pode rodar em paralelo (arquivos diferentes, sem dependência entre si)
- **[Story]**: A qual user story a tarefa pertence (US1, US2)
- Caminhos de arquivo exatos em cada descrição

---

## Phase 1: Foundational (Blocking Prerequisites)

**Purpose**: Expor a posição do cliente já obtida para que qualquer estado de UI possa centralizar
o mapa nela. Bloqueia as duas user stories.

**⚠️ CRITICAL**: Nenhuma tarefa de user story pode começar antes desta fase.

- [X] T001 Expor o fix de localização já obtido para descoberta como `private(set) var lastFix: DeviceLocationFix?` (era `private var`) em `pitgo/Features/PitTec/ViewModel/PitTecClientViewModel.swift`, no mesmo padrão já usado por `routeContext` na mesma classe — nenhuma outra mudança de comportamento nesta tarefa.

**Checkpoint**: `viewModel.lastFix` pode ser lido pela View — as duas user stories podem começar.

---

## Phase 2: User Story 1 - Ver o mapa centralizado ao encontrar PitTecs disponíveis (Priority: P1) 🎯 MVP

**Goal**: Ao abrir o mapa do PitTec com ao menos um prestador elegível na região, o mapa aparece
centralizado na posição atual do cliente junto com os marcadores aproximados dos prestadores.

**Independent Test**: Abrir o mapa do PitTec com localização concedida e ≥1 PitTec elegível na
região; verificar que o mapa aparece centralizado na posição do cliente com os marcadores de
prestador visíveis, sem depender do cenário sem PitTec (US2).

### Implementation for User Story 1

- [X] T002 [US1] No branch com marcadores (`!markers.isEmpty`) de `discoveringState(_:)` em `pitgo/Features/PitTec/Views/PitTecClientView.swift`, passar `centerCoordinate: CLLocationCoordinate2D(latitude:longitude:)` construído a partir de `viewModel.lastFix` e `showsUserLocation: true` para o `PitGoMapView` existente, mantendo os marcadores de `PitTecMarker` já mapeados em `annotations`.

**Checkpoint**: User Story 1 completa e testável de forma independente — o mapa centraliza no
cliente sempre que há PitTec elegível, incluindo quando novos marcadores chegam durante a mesma
sessão (consequência direta de `centerCoordinate` permanecer estável em `PitGoMapView`, sem tarefa
adicional).

---

## Phase 3: User Story 2 - Ver o mapa centralizado mesmo sem nenhum PitTec disponível (Priority: P1)

**Goal**: Quando não existe PitTec elegível — na descoberta inicial ou ao final de uma busca
esgotada — o mapa aparece centralizado na posição do cliente junto com a mensagem informativa, em
vez de uma tela só de texto sem mapa.

**Independent Test**: Abrir o mapa do PitTec com localização concedida e nenhum PitTec elegível na
região (cenário inicial) e, separadamente, levar uma busca já iniciada até o esgotamento; em ambos,
verificar que o mapa aparece centralizado na posição do cliente com a mensagem correspondente
sobreposta, sem depender do cenário com PitTec disponível (US1).

### Implementation for User Story 2

- [X] T003 [US2] Adicionar um helper de View privado e reutilizável (ex.: `mapCenteredOnClient(message:actions:)`) em `pitgo/Features/PitTec/Views/PitTecClientView.swift` que renderiza `PitGoMapView` sem marcadores de prestador — `centerCoordinate` a partir de `viewModel.lastFix`, `showsUserLocation: true` — com uma mensagem (e ações opcionais) sobrepostas ao mapa, reaproveitado pelas duas tarefas seguintes.
- [X] T004 [US2] No branch vazio (`markers.isEmpty`) de `discoveringState(_:)` em `pitgo/Features/PitTec/Views/PitTecClientView.swift`, substituir o uso de `emptyDiscoveryState` pelo helper de T003 com a mensagem "Nenhum PitTec disponível nesta região agora.", e remover a propriedade `emptyDiscoveryState` (não fica mais em uso).
- [X] T005 [US2] Em `terminalState(_:)` de `pitgo/Features/PitTec/Views/PitTecClientView.swift`, quando `snapshot.status == .exhausted`, renderizar o helper de T003 com a mensagem de `terminalMessage(.exhausted)` e as ações "Buscar novamente"/"Voltar" já existentes sobrepostas ao mapa, preservando `terminalState` inalterado para `.completed` e `.cancelled`.

**Checkpoint**: User Stories 1 e 2 funcionam de forma independente — o mapa do PitTec está sempre
centralizado no cliente, com ou sem prestador disponível, na descoberta e na busca esgotada.

---

## Phase 4: Polish & Cross-Cutting Concerns

**Purpose**: Validação final da feature completa.

- [ ] T006 Executar os 3 cenários e a checagem de regressão de `specs/020-pittec-client-map-centering/quickstart.md` (sem PitTec disponível, com PitTec disponível, busca esgotada, e os estados inalterados: localização negada, atendimento aceito, busca concluída/cancelada).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Foundational (Phase 1)**: sem dependências — pode começar imediatamente.
- **User Story 1 (Phase 2)**: depende de T001 (Foundational).
- **User Story 2 (Phase 3)**: depende de T001 (Foundational). Independente de User Story 1 — pode
  ser implementada em paralelo por outra pessoa, mesmo tocando o mesmo arquivo (`PitTecClientView.swift`) em regiões diferentes (`discoveringState`/`terminalState` vs. helper novo).
- **Polish (Phase 4)**: depende da conclusão de User Story 1 e User Story 2.

### Dentro de cada User Story

- US1: T002 é a única tarefa — sem dependência interna.
- US2: T003 (helper) bloqueia T004 e T005, que o consomem.

### Parallel Opportunities

- T002 (US1) e T003 (US2) podem começar em paralelo assim que T001 terminar — ambas tocam
  `PitTecClientView.swift`, mas em regiões distintas (branch com marcadores vs. novo helper); não
  marcadas `[P]` por estarem no mesmo arquivo (risco de conflito de merge), mas não têm dependência
  lógica entre si.
- T004 e T005 dependem de T003 e não são paralelizáveis entre si (mesmo arquivo, mesma tarefa de
  origem).

---

## Implementation Strategy

### MVP First (User Story 1)

1. Completar Phase 1: Foundational (T001).
2. Completar Phase 2: User Story 1 (T002).
3. **Parar e validar**: abrir o mapa do PitTec com ≥1 prestador elegível e confirmar centralização.
4. Entregar/demonstrar se suficiente como incremento.

### Incremental Delivery

1. Foundational → base pronta (T001).
2. User Story 1 → testar independentemente → demo (mapa centralizado com PitTec disponível).
3. User Story 2 → testar independentemente → demo (mapa centralizado sem PitTec disponível e em
   busca esgotada).
4. Polish → rodar `quickstart.md` completo (T006) antes de considerar a feature concluída.
