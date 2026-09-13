---

description: "Implementation tasks for the Request Service screen (iOS)"
---

# Tasks: Solicitar Atendimento (iOS)

**Input**: Design documents from `specs/003-request-service/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Nenhum teste automatizado solicitado. Verificação por build e pelos cenários manuais de
`quickstart.md`.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup (Shared Resources)

- [X] T001 Adicionar título, labels, mocks, opções de pagamento, CTA, aviso, erro e descrições
  acessíveis de RequestService no Strings Catalog
- [X] T002 [P] Escolher/definir os SF Symbols de voltar, check selecionado e relógio em
  `pitgo/Assets.xcassets`

## Phase 2: Foundational (Blocking Prerequisites)

**⚠️ CRITICAL**: Nenhuma história começa antes desta fase terminar.

- [X] T003 Extrair `DemoServiceID`, `DemoService`, o catálogo, `DemoVehicle` para
  `pitgo/Core/Common/Model/DemoServiceCatalog.swift` e `pitgo/Core/Common/Model/DemoVehicle.swift`,
  removendo-os de `pitgo/Features/Home/Model/HomeContent.swift` e atualizando os usos em
  `pitgo/Features/Home/ViewModel/HomeViewModel.swift` e `pitgo/Features/Home/Views/HomeView.swift`
- [X] T004 [P] Extrair `BottomItemID` e a `TabView` compartilhada para
  `pitgo/Core/UI/PitGoBottomTabs.swift`, atualizando o uso em `HomeContent.swift`,
  `HomeViewModel.swift` e `HomeView.swift`
- [X] T005 [P] Definir `PaymentMethod`, `SubmissionStatus` e o `enum` `RequestServiceUiState` com
  `.content`/`.invalidService` em
  `pitgo/Features/RequestService/Model/RequestServiceContent.swift`
- [X] T006 [P] Adicionar `.requestService(serviceID: DemoServiceID?)` a `PitGoRoute` em
  `pitgo/Core/Navigation/PitGoRoute.swift`

**Checkpoint**: Modelos e rota compartilhados prontos; nenhuma feature ainda consome a nova rota.

---

## Phase 3: User Story 1 - Revisar o atendimento selecionado (Priority: P1) 🎯 MVP

**Goal**: Abrir a solicitação a partir de qualquer card da Home com o serviço, veículo, local e
estimativas corretos, ou um estado de erro compreensível para ID ausente.

**Independent Test**: Selecionar cada um dos seis serviços na Home e confirmar título, nome, ícone
e preço corretos na View de solicitação.

### Implementation for User Story 1

- [X] T007 [P] [US1] Implementar `RequestServiceViewModel` (`@Observable`) com lookup exato do
  `DemoServiceID?` recebido, estado `.content` imediato com preço/endereço derivados e
  `.invalidService` sem fallback em
  `pitgo/Features/RequestService/ViewModel/RequestServiceViewModel.swift`
- [X] T008 [P] [US1] Implementar o shell stateless com `NavigationStack`, `ScrollView`, `TabView`
  fixa, `InfoCard`, `EstimateCard`, conteúdo válido responsivo e estado `.invalidService` em
  `pitgo/Features/RequestService/Views/RequestServiceView.swift`
- [X] T009 [US1] Conectar `RequestServiceView` ao `RequestServiceViewModel` (criação e observação)
  em `pitgo/Features/RequestService/Views/RequestServiceView.swift` (depende de T007, T008)
- [X] T010 [US1] Propagar `onServiceTap` em `HomeView` e registrar `.navigationDestination(for:
  PitGoRoute.self)` com guarda de navegação em `pitgo/Features/Home/Views/HomeView.swift` e
  `pitgo/Core/Navigation/PitGoRootView.swift`
- [ ] T011 [US1] Executar e confirmar os cenários manuais 1, 2 e a inspeção de ID inválido do
  cenário 6 em `specs/003-request-service/quickstart.md` — **bloqueado neste ambiente**: exige
  simulador/dispositivo iniciado (só o runtime iOS 26.2 Simulator está baixado, mas o Xcode 26.5
  instalado resolve SDKROOT 26.5 — mesma causa registrada em `001`/T019)

**Checkpoint**: MVP funcional — todos os seis serviços abrem a View correta.

---

## Phase 4: User Story 2 - Informar o problema e o pagamento (Priority: P2)

**Goal**: Descrição opcional multiline e seleção exclusiva de forma de pagamento.

**Independent Test**: Digitar uma descrição de várias linhas e alternar entre PIX/Crédito/Débito,
confirmando exatamente uma seleção a cada troca.

### Implementation for User Story 2

- [X] T012 [P] [US2] Implementar `onProblemDescriptionChanged`/`onPaymentMethodSelected` com
  atualização imutável apenas do caso `.content` em
  `pitgo/Features/RequestService/ViewModel/RequestServiceViewModel.swift`
- [X] T013 [P] [US2] Adicionar `TextEditor` multiline com altura mínima e o grupo de seleção de
  pagamento (estilos selecionado/não selecionado, check visível) em
  `pitgo/Features/RequestService/Views/RequestServiceView.swift`
- [ ] T014 [US2] Executar e confirmar os cenários manuais 3 e 4 em `quickstart.md` —
  **bloqueado neste ambiente**: mesma causa de T011

**Checkpoint**: Descrição e pagamento editáveis e refletidos imediatamente no estado.

---

## Phase 5: User Story 3 - Acionar a solicitação simulada (Priority: P3)

**Goal**: CTA com feedback imediato, execução única do callback mock e aviso de valor variável.

**Independent Test**: Tocar "SOLICITAR PITTECH" repetidamente e confirmar uma única execução.

### Implementation for User Story 3

- [X] T015 [P] [US3] Implementar `onSubmit()` com guarda síncrona `.ready → .triggered` e retorno
  de aceitação única em
  `pitgo/Features/RequestService/ViewModel/RequestServiceViewModel.swift`
- [X] T016 [P] [US3] Adicionar `Button` em largura máxima com gradiente, altura mínima de 56pt,
  `.disabled` após acionamento e aviso centralizado em
  `pitgo/Features/RequestService/Views/RequestServiceView.swift`
- [ ] T017 [US3] Executar e confirmar o cenário manual 5 e as verificações de ausência de
  integrações do cenário 10 em `quickstart.md` — **bloqueado neste ambiente**: mesma causa de T011

**Checkpoint**: Ação simulada protegida contra repetição, sem qualquer efeito colateral real.

---

## Phase 6: User Story 4 - Sair ou mudar de área (Priority: P4)

**Goal**: Retorno previsível à Home e `TabView` consistente com a Home.

**Independent Test**: Abrir a solicitação, voltar e confirmar retorno à mesma Home com a `TabView`
intacta.

### Implementation for User Story 4

- [X] T018 [P] [US4] Conectar a ação de voltar da barra de navegação, o retorno do estado
  `.invalidService` e os callbacks no-op acessíveis das abas em
  `pitgo/Features/RequestService/Views/RequestServiceView.swift`
- [X] T019 [P] [US4] Confirmar fallback seguro para Home quando não há uma entrada anterior válida
  em `pitgo/Core/Navigation/PitGoRootView.swift`
- [ ] T020 [US4] Executar e confirmar os cenários manuais 6 e 7 em `quickstart.md` —
  **bloqueado neste ambiente**: mesma causa de T011

**Checkpoint**: Navegação de saída e `TabView` funcionam identicamente à Home.

---

## Phase 7: Polish & Cross-Cutting Validation

- [X] T021 Revisar Dynamic Type, portrait/landscape, teclado, temas Light/Dark, headings, ordem
  semântica, alvos de 44pt e ausência de informação dependente somente de cor em
  `pitgo/Features/RequestService/Views/RequestServiceView.swift` e no Strings Catalog
- [ ] T022 Executar `xcodebuild -project pitgo.xcodeproj -scheme pitgo clean build` e conferir os
  resultados esperados de `quickstart.md` — **bloqueado neste ambiente**: mesma causa registrada em
  `001`/T019 (Simulator iOS 26.5 não baixado). **Verificação alternativa executada com sucesso**:
  `xcrun -sdk iphoneos swiftc -typecheck -target arm64-apple-ios17.0 -swift-version 6` sobre todos
  os arquivos Swift desta feature, sem erros nem warnings (um warning real de concorrência Swift 6
  na conversão do `Binding` de `TextEditor` foi corrigido anotando o closure como `@MainActor`).
- [ ] T023 Executar integralmente os cenários manuais 1–10, confirmar operação offline e ausência
  de backend, persistência, permissões, cobrança, destinos placeholder e arquivos de teste
  conforme `quickstart.md` — **bloqueado neste ambiente**: mesma causa de T011. Confirmado por
  revisão de código: nenhuma chamada de rede, Repository, persistência ou permissão existe em
  `Features/RequestService/`.

**Checkpoint**: Build limpo, todas as histórias validadas, nenhum item fora do escopo.

---

## Dependencies & Execution Order

```text
Setup → Foundation → US1 (MVP) → US2 → US3 → US4 → Polish
```

- **US1**: depende só da Foundation.
- **US2/US3/US4**: cada uma estende a mesma View/ViewModel de US1, em sequência.

### Within Each User Story

- Modelo/rota antes do ViewModel.
- ViewModel antes da View.
- View antes da integração de navegação (apenas US1).
- Implementação antes da validação manual.

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Setup + Foundational.
2. User Story 1.
3. **STOP AND VALIDATE**: execute T011.

### Incremental Delivery

1. Setup + Foundation → modelos e rota prontos.
2. US1 → MVP navegável.
3. US2 → descrição e pagamento editáveis.
4. US3 → ação simulada protegida.
5. US4 → saída e `TabView` consistentes.
6. Polish → build, acessibilidade e escopo confirmados.

## Notes

- Não criar testes, mocks ou fixtures sem solicitação explícita.
- Não adicionar Swift Package externo, persistência, DI, rede ou funcionalidade fora do escopo.
