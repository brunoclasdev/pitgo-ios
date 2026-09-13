---
description: "Implementation tasks for client UX improvements (iOS)"
---

# Tasks: Melhoria de UX das telas do cliente (iOS)

**Input**: Design documents from `specs/014-client-ux-improvements/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`,
`quickstart.md`

**Tests**: Sem testes automatizados, conforme a governança do projeto.

> **Achados reais desta sessão**: (1) o countdown de `013` (`ClientMobileDispatchView`/
> `ProviderIncomingRequestView`) tinha exatamente o bug que a US1 descreve — o texto nunca lia uma
> propriedade que mudasse a cada segundo, então a `Text` nunca recompunha; corrigido adicionando um
> tick de 1s observável em cada ViewModel. (2) a retomada automática do dashboard do provider
> (`ProviderDashboardViewModel`) reabria a mesma tela após um "voltar" manual sempre que outro
> evento chegava no mesmo canal Realtime — exatamente o bug da US4 — corrigido com um guarda de "já
> dispensado por ID".

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup (Shared Infrastructure)

- [X] T001 Verificado via `pg_get_functiondef` nesta sessão: `client_addresses`/`client_current_locations`
  e `get_my_client_address`/`upsert_my_client_address`/`publish_client_location`/
  `get_appointment_client_location` existem e batem com o desenho esperado
- [ ] T002 [P] **Não feito** — `ViaCepAddressLookupRepository` não foi movido; `ClientAddressViewModel`
  o referencia diretamente em `Features/ProviderRegistration` (mesmo alvo único, sem separação de
  módulo — risco de mover um arquivo em uso por duas features sem necessidade real)

---

## Phase 2: Foundational (Blocking Prerequisites)

**⚠️ CRITICAL**: Nenhuma história começa antes desta fase estar concluída.

- [X] T003 [P] Criado em `pitgo/Features/ClientAddress/Model/ClientAddressModels.swift`
- [X] T004 [P] Criado como `AppAppearance`/`AppearancePreference` (nomes diferentes do task, mesmo
  papel) em `pitgo/Core/Preferences/AppearancePreferences.swift`
- [ ] T005 [P] **Não feito** — ver Phase 6 abaixo (US2/US3 de mapa duplo não foram implementadas
  nesta sessão; os DTOs de `publish_client_location`/`get_appointment_client_location` não chegaram
  a ser necessários)

**Checkpoint**: modelos e preferência de endereço/aparência prontos; a infraestrutura de posição do
cliente para os mapas (US2/US3) fica pendente.

---

## Phase 3: User Story 5 - Início (Home) acionável (Priority: P2, implementada primeiro por ser pré-requisito de dados de US6)

**Independent Test**: Logar com uma conta cliente sem endereço cadastrado e verificar se a Home
oferece um caminho direto para cadastrá-lo.

### Implementation

- [X] T006 [US5] Implementado em
  `pitgo/Features/ClientAddress/Repository/ClientAddressRepository.swift`
- [X] T007 [US5] Implementado em
  `pitgo/Features/ClientAddress/ViewModel/ClientAddressViewModel.swift` — a coordenada exigida pela
  RPC (`p_latitude`/`p_longitude` não opcionais) vem de uma leitura pontual de GPS no momento de
  salvar (`DeviceLocationRepository.requestOneShotFix`), nunca inventada; falha de localização vira
  `.locationRequired` em vez de bloquear silenciosamente
- [X] T008 [US5] Criado `pitgo/Features/ClientAddress/Views/ClientAddressView.swift`
- [X] T009 [US5] Linha de endereço da Home tornada tocável (`PitGoRoute.clientAddress`) em
  `pitgo/Features/Home/Views/HomeView.swift`/`PitGoRootView.swift` — a linha ainda mostra sempre
  "Endereço não cadastrado" independente do estado real (a Home não consulta
  `ClientAddressRepository`); abrir a tela mostra o endereço real, mas o texto da própria Home não
  reflete "cadastrado" quando já existe — gap menor não fechado nesta sessão
- [X] T010 [US5] Confirmado sem alteração — o card "Nenhum veículo selecionado" já era tocável desde
  `009` (`onOpenGarage`)

**Checkpoint**: Home reage ao endereço real e oferece cadastro direto.

---

## Phase 4: User Story 6 - Perfil completo e autoexplicativo (Priority: P3)

**Independent Test**: Abrir a aba Perfil e confirmar que endereço, veículo padrão e tema podem ser
vistos e alterados a partir dali.

### Implementation

- [ ] T011 [US6] **Não feito como `ProfileViewModel` dedicado** — `ProfileView` permanece stateless
  (usa `@AppearancePreference` diretamente e `snapshot.primaryVehicle`/`ClientAddressRepository` já
  injetados por `PitGoRootView`), mesma simplicidade já usada por outras Views desta feature; nenhum
  agregador novo foi introduzido
- [X] T012 [US6] `ProfileView` estendida com seções de endereço (abre `ClientAddressView`), veículo
  padrão (`onOpenGarage`) e aparência (`Picker` segmentado) em
  `pitgo/Features/Profile/Views/ProfileView.swift`
- [X] T013 [US6] `.preferredColorScheme(appearance.colorScheme)` aplicado na raiz em
  `pitgo/pitgoApp.swift`
- [X] T014 [US6] Confirmado sem alteração

**Checkpoint**: Perfil gerencia endereço, veículo e aparência sem sair da aba.

---

## Phase 5: User Story 1 - Feedback claro durante a solicitação de serviço (Priority: P1)

**Independent Test**: Solicitar um serviço e observar cada estado (buscando, proposta encontrada,
aguardando prestador, aceito, recusado/expirado, sem prestador disponível).

### Implementation

- [X] T015 [US1] Já existia desde `013` (`actionLabel` com `ProgressView` em Solicitar/Próximo); o
  cancelamento pós-aceite mostra o carregamento dentro do próprio `.sheet`
  (`DispatchCancellationSheet.isSubmitting`)
- [X] T016 [P] [US1] Já existia desde `013` (Aceitar/Recusar com `actionLabel`)
- [X] T017 [US1] Implementado — abaixo de 50m o texto vira "Muito próximo de você" em vez de um
  valor tipo "A 0 m de você", em `ClientMobileDispatchView.swift`
- [X] T018 [US1] Corrigido nesta sessão, não apenas confirmado: o countdown de `013` tinha o bug
  exato que esta história descreve (texto travado) — ver nota no topo deste arquivo

**Checkpoint**: feedback de carregamento e distância claros; o bug real de countdown travado (US1)
foi corrigido, não apenas confirmado como já correto.

---

## Phase 6: User Story 2 - Cliente acompanha o guincho se movimentando no mapa (Priority: P1)

**Independent Test**: Aceitar um atendimento com um provider `MOBILE` publicando localização e
observar, na tela de acompanhamento do cliente, a própria posição centralizada e o marcador do
guincho se deslocando.

### Implementation

- [ ] T019 [US2] **Não feito** — `AppointmentTrackingRepository` (guincho móvel, `009`/`013`) não foi
  tocado nesta sessão. Este é o gap mais significativo de `014` deixado nesta entrega: o mapa de
  acompanhamento do CLIENTE para um guincho móvel continua mostrando só a posição do prestador,
  sem a posição própria centralizada
- [ ] T020 [US2] **Não feito** — ver T019
- [ ] T021 [US2] **Não feito** — ver T019
- [ ] T022 [US2] **Não feito** — ver T019

**Checkpoint não alcançado**: o mapa do cliente para atendimentos de guincho móvel (`013`) não
recebeu a posição própria nesta sessão. O equivalente para PitTec (`015`) foi resolvido de forma
autocontida em `PitTecClientView` (fora do escopo desta tarefa, mas cobrindo a mesma necessidade de
produto para a modalidade nova).

---

## Phase 7: User Story 3 - Guincho vê o cliente e a si mesmo no mapa em tempo real (Priority: P1)

**Independent Test**: Aceitar um atendimento do lado do provider e verificar se a tela de
atendimento passa a exibir um mapa com os dois marcadores enquadrados e atualizando.

### Implementation

- [ ] T023 [US3] **Não feito** — `ProviderIncomingRequestView.swift` (guincho móvel, `013`) continua
  sem mapa no estado "atendimento aceito". O equivalente PitTec (`PitTecIncomingRequestView`, `015`)
  já tem mapa com as duas posições; portar o mesmo padrão para o guincho móvel ficou pendente
- [ ] T024 [US3] **Não feito** — ver T023
- [ ] T025 [US3] **Não feito** — ver T023

**Checkpoint não alcançado**: mapa duplo (cliente+provider) só existe hoje no fluxo PitTec (`015`),
não no fluxo de guincho móvel (`013`) que esta história (US3) pedia.

---

## Phase 8: User Story 4 - Voltar sem travar entre as telas do atendimento (Priority: P1)

**Independent Test**: Ter um atendimento ativo e tocar em voltar repetidamente a partir da tela de
acompanhamento/atendimento, tanto como cliente quanto como provider, confirmando que o app permanece
na tela anterior.

### Implementation

- [X] T026 [US4] Implementado como um guarda de "ID já dispensado" (não
  `lastTriggeredRevision`/`DispatchResumeCoordinator` — o bug real encontrado estava em
  `ProviderDashboardViewModel`, que reavalia solicitação/atendimento pendente a cada evento
  Realtime, não em `DispatchResumeCoordinator`, que só roda uma vez no bootstrap): `dismissedIncomingID`/
  `dismissedResumedTrackingID`/`dismissedPitTecID` em
  `pitgo/Features/ProviderDashboard/ViewModel/ProviderDashboardViewModel.swift` — o mesmo ID
  dispensado por um "voltar" manual não reabre a tela sozinho; um ID/atendimento genuinamente novo
  ainda dispara a navegação automática
- [X] T027 [US4] Confirmado: o lado cliente (`ClientMainTabView.task`) só avalia a retomada uma vez
  na montagem (`guard homePath.isEmpty`), sem um listener contínuo equivalente ao do dashboard do
  provider — estruturalmente não sofre o mesmo bug, então nenhuma mudança adicional foi necessária
  ali
- [ ] T028 [US4] **bloqueado neste ambiente** (interação manual)

**Checkpoint**: o bug real de retomada automática sobrescrevendo "voltar" foi identificado e
corrigido no dashboard do provider (a instância concreta encontrada nesta sessão); o lado cliente já
era estruturalmente seguro.

---

## Phase 9: Polish & Cross-Cutting Concerns

- [X] T029 Executado `xcodebuild clean build` em simulador e `generic/platform=iOS` —
  **BUILD SUCCEEDED** nesta sessão
- [ ] T030 **bloqueado neste ambiente** (interação manual)
- [ ] T031 **Não feito** — nenhuma auditoria dedicada de Dynamic Type/landscape/VoiceOver foi
  realizada nesta sessão nas Views alteradas/criadas

---

## Dependencies & Execution Order

```text
Setup → Foundation → US5 → US6 → US1 → US2 → US3 → US4 → Polish
```

- **US5** entrega o dado de endereço que **US6** (Perfil) também consome.
- **US1/US2/US3/US4** são independentes entre si após a Foundation, mas compartilham `013`/`009`
  como base — a ordem sugerida reflete prioridade de produto (todas P1), não uma dependência técnica
  estrita.

### Parallel Opportunities

- Foundation: T003/T004/T005 em paralelo.
- US5: T006→T007→T008 sequencial; T009/T010 após T008.
- US1: T015/T016/T017 podem avançar em paralelo (arquivos distintos).
- US2/US3: podem ser desenvolvidas em paralelo por times diferentes (Views distintas).

## Notes

- Nenhuma migration nova é criada — o backend já existe e é compartilhado com o Android.
- Nenhuma dependência nova é adicionada.
- Nenhum teste automatizado é criado; build e `quickstart.md` são os gates de qualidade.
- Commits pequenos por tarefa/grupo lógico.
