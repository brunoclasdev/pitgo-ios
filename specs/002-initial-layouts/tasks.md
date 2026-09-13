---

description: "Implementation tasks for the PitGo Welcome and Home layouts (iOS)"
---

# Tasks: Layouts iniciais do PitGo (iOS)

**Input**: Design documents from `specs/002-initial-layouts/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Nenhum teste automatizado foi solicitado. A implementação será verificada por build e
pelos cenários manuais de `quickstart.md`, conforme a constituição.

**Organization**: As tarefas são agrupadas por história de usuário e mantêm os caminhos exatos
para que cada incremento possa ser implementado e validado sem decisões adicionais.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Pode executar em paralelo após as dependências anteriores, pois altera arquivos
  diferentes.
- **[Story]**: História atendida (`US1`, `US2` ou `US3`); setup, fundação e polish não usam rótulo.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirmar o baseline de `001` e impedir dependências desnecessárias antes de alterar
os layouts.

- [X] T001 Confirmar o baseline com `xcodebuild ... clean build` e auditar que nenhum Swift
  Package novo é necessário no projeto `pitgo.xcodeproj`

**Checkpoint**: A configuração atual compila e está preservada para uma implementação sem novas
dependências.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Atualizar o design system compartilhado que será consumido pelas duas telas.

**⚠️ CRITICAL**: Nenhuma história começa antes desta fase terminar.

- [X] T002 [P] Atualizar a paleta de marca Light/Dark, incluindo `#7C32E8`, `#5520A8`, `#FAF9FD`,
  `#17151D`, `#6F6B78` e contrastes escuros em `pitgo/Core/DesignSystem/Colors.swift`
- [X] T003 [P] Estender somente os estilos de tipografia, espaçamento e formas realmente exigidos
  pelos layouts em `pitgo/Core/DesignSystem/Typography.swift`
- [X] T004 Integrar a nova paleta/tokens em `PitGoTheme`, preservando o tema do sistema, em
  `pitgo/Core/DesignSystem/PitGoTheme.swift` (depende de T002 e T003)

**Checkpoint**: A identidade roxa e os papéis semânticos Light/Dark estão centralizados e prontos
para Welcome e Home.

---

## Phase 3: User Story 1 - Conhecer o PitGo e entrar (Priority: P1) 🎯 MVP

**Goal**: Apresentar a Welcome completa, responsiva e acessível como destino inicial, com somente
Entrar navegando uma única vez para a Home e retornando corretamente.

**Independent Test**: Abrir o app, validar wordmark/título/subtítulo/benefícios/ações, confirmar
que Criar conta e Cadastrar permanecem na Welcome, tocar Entrar repetidamente e observar uma única
Home; voltar deve retornar à Welcome e uma nova entrada deve continuar funcionando.

### Implementation for User Story 1

- [X] T005 [P] [US1] Adicionar wordmark, título, subtítulo, três benefícios, três ações e
  descrições acessíveis da Welcome no Strings Catalog `pitgo/Resources/Localizable.xcstrings`
- [X] T006 [P] [US1] Escolher/definir os SF Symbols (ou assets locais quando necessário) dos três
  benefícios em `pitgo/Assets.xcassets`
- [X] T007 [P] [US1] Implementar `WelcomeBenefitID`, `WelcomeBenefit` e a lista local ordenada de
  três benefícios em `pitgo/Features/Welcome/Model/WelcomeBenefit.swift`
- [X] T008 [US1] Implementar `WelcomeUiState` imutável e `WelcomeViewModel` (`@Observable`)
  imediatamente preenchido em `pitgo/Features/Welcome/ViewModel/WelcomeViewModel.swift` (depende
  de T005–T007)
- [X] T009 [US1] Implementar `WelcomeView` stateless com gradiente fixo, `.safeAreaPadding()`,
  `ScrollView` vertical, card de benefício e as três ações em
  `pitgo/Features/Welcome/Views/WelcomeView.swift` (depende de T008)
- [X] T010 [US1] Reduzir o host para Welcome como raiz e Home atrás de `onEnter`, com flag
  reiniciável ao retornar e sem duplicar destino, em `pitgo/Core/Navigation/PitGoRootView.swift`
  e `pitgo/pitgoApp.swift` (depende de T009)
- [ ] T011 [US1] Executar e registrar os cenários Welcome content, Welcome responsiveness e
  Welcome actions and navigation de `specs/002-initial-layouts/quickstart.md` — **bloqueado neste
  ambiente**: exige simulador/dispositivo iniciado (mesma causa registrada em `001`/T019: só o
  runtime iOS 26.2 Simulator está baixado, mas o Xcode 26.5 instalado resolve SDKROOT 26.5)

**Checkpoint**: A User Story 1 funciona como MVP visual e de navegação, ainda que a Home mantenha
temporariamente o conteúdo de `001` até a próxima fase.

---

## Phase 4: User Story 2 - Visualizar o contexto do atendimento (Priority: P2)

**Goal**: Substituir o conteúdo anterior da Home por saudação, avatar, veículo, endereço e card de
diagnóstico demonstrativos, mantendo a tela rolável e pronta para o catálogo.

**Independent Test**: Abrir a Home e confirmar Rafael/R, BMW 320i M Sport, `2020 · PGO-2A20`,
endereço, ícones e diagnóstico, sem depender do catálogo ou de fonte externa.

### Implementation for User Story 2

- [X] T012 [P] [US2] Adicionar saudação, perfil, rótulo/modelo/ano/placa/endereço do veículo,
  título principal, diagnóstico e descrições acessíveis no Strings Catalog
- [X] T013 [P] [US2] Escolher/definir os SF Symbols de veículo, localização e diagnóstico em
  `pitgo/Assets.xcassets`
- [X] T014 [P] [US2] Implementar os modelos imutáveis `DemoProfile`, `DemoVehicle` e
  `DiagnosticPrompt` em `pitgo/Features/Home/Model/HomeContent.swift`
- [X] T015 [US2] Substituir o estado de `001` por `HomeUiState` com perfil, veículo e diagnóstico
  locais em `pitgo/Features/Home/ViewModel/HomeViewModel.swift` (depende de T012–T014)
- [X] T016 [US2] Reescrever `HomeView` com cabeçalho/avatar, card de veículo, endereço, título e
  card de diagnóstico tocável, sem navegação, em `pitgo/Features/Home/Views/HomeView.swift`
  (depende de T015)
- [ ] T017 [US2] Executar e registrar o cenário Home demonstrative content e a parte de
  contexto/diagnóstico dos cenários Home interactions e Accessibility de `quickstart.md` —
  **bloqueado neste ambiente**: mesma causa de T011

**Checkpoint**: A User Story 2 é verificável diretamente na Home e não contém mais o layout do
catálogo de `001`.

---

## Phase 5: User Story 3 - Explorar serviços disponíveis (Priority: P3)

**Goal**: Completar a Home com seis serviços/preços em duas colunas fixas e uma `TabView` de cinco
abas, todos com feedback sem continuidade.

**Independent Test**: Abrir a Home, confirmar serviços/valores/ordem, duas colunas e barra fixa;
rolar até Carro não liga e tocar cards/abas sem alterar destino nem seleção Início.

### Implementation for User Story 3

- [X] T018 [P] [US3] Substituir textos obsoletos de categorias/prestadores de `001` e adicionar
  seis serviços, preços, cinco rótulos de aba e descrições acessíveis finais no Strings Catalog
- [X] T019 [P] [US3] Escolher/definir os SF Symbols dos seis serviços e das cinco abas em
  `pitgo/Assets.xcassets`
- [X] T020 [P] [US3] Estender `HomeContent` com `DemoServiceID`, seis `DemoService`,
  `BottomItemID` e invariantes de ordem/preço em `pitgo/Features/Home/Model/HomeContent.swift`
- [X] T021 [US3] Estender `HomeUiState`/`HomeViewModel` com os seis serviços em
  `pitgo/Features/Home/ViewModel/HomeViewModel.swift` (depende de T018–T020)
- [X] T022 [US3] Adicionar título, `ServiceCard`, `LazyVGrid` de duas colunas fixas, `TabView` com
  as cinco abas (`Início` selecionada e com conteúdo; demais sem conteúdo funcional) em
  `pitgo/Features/Home/Views/HomeView.swift` (depende de T021)
- [X] T023 [US3] Remover código e recursos supersedidos de `001`:
  `pitgo/Features/Home/Model/ServiceCategory.swift`,
  `pitgo/Features/Provider/Views/ProviderSearchEntryView.swift` e
  `pitgo/Core/Navigation/PitGoRoute.swift` (depende de T022)
- [ ] T024 [US3] Executar e registrar os cenários Grid and fixed bottom tab bar, Home interactions
  e a parte de catálogo/barra de Accessibility de `quickstart.md` — **bloqueado neste ambiente**:
  mesma causa de T011

**Checkpoint**: As três histórias estão funcionais; o aplicativo contém somente Welcome e a nova
Home, sem destinos ou dados antigos de prestadores de `001`.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Auditar o escopo, validar integração e confirmar os requisitos que atravessam as três
histórias.

- [X] T025 Auditar `pitgo.xcodeproj` e `pitgo/` para confirmar ausência de Swift Packages novos,
  código/recursos órfãos de `001`, backend, Supabase, rede, persistência, DI, autenticação,
  localização, placeholders e testes
- [ ] T026 Executar `xcodebuild -project pitgo.xcodeproj -scheme pitgo clean build` e corrigir
  todos os erros/warnings bloqueantes — **bloqueado neste ambiente**: mesma causa registrada em
  `001`/T019 (Simulator iOS 26.5 não baixado). **Verificação alternativa executada com sucesso**:
  `xcrun -sdk iphoneos swiftc -typecheck -target arm64-apple-ios17.0 -swift-version 6` sobre todos
  os arquivos Swift desta feature, sem erros.
- [ ] T027 Executar e registrar o roteiro manual completo de Light/Dark, safe areas, offline,
  portrait/landscape, Dynamic Type, VoiceOver, reentrada e limites de escopo em
  `specs/002-initial-layouts/quickstart.md` — **bloqueado neste ambiente**: mesma causa de T011

**Checkpoint**: Build passa, a validação manual está registrada e nenhum item fora do escopo foi
introduzido.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: começa imediatamente.
- **Foundational (Phase 2)**: depende do Setup; T002 e T003 em paralelo, T004 depende de ambos.
- **User Story 1 (Phase 3)**: depende da Foundation; T005–T007 em paralelo, seguidas por T008–T011.
- **User Story 2 (Phase 4)**: depende da US1 (substitui o conteúdo da Home); T012–T014 em
  paralelo, seguidas por T015–T017.
- **User Story 3 (Phase 5)**: depende da US2; T018–T020 em paralelo, seguidas por T021–T024.
- **Polish (Phase 6)**: depende das histórias desejadas; executar T025, T026 e T027 nessa ordem.

### User Story Dependencies

```text
Setup → Foundation → US1 (MVP) → US2 → US3 → Polish
```

### Within Each User Story

- Textos e recursos visuais antes do modelo.
- Modelo antes do ViewModel.
- ViewModel antes da View.
- View antes da integração no host de navegação (apenas US1).
- Implementação antes da validação manual da história.

### Parallel Opportunities

- T002 e T003 após Setup.
- T005, T006 e T007 após Foundation.
- T012, T013 e T014 após US1.
- T018, T019 e T020 após US2.
- Não paralelizar tarefas que alteram `HomeView.swift` ou o Strings Catalog em fases diferentes.

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Setup + Foundational.
2. Complete User Story 1.
3. **STOP AND VALIDATE**: execute T011.

### Incremental Delivery

1. Setup + Foundation deixam o design system pronto.
2. US1 entrega Welcome → Home navegável (MVP).
3. US2 substitui o conteúdo da Home pelo contexto demonstrativo.
4. US3 completa o catálogo de serviços e a barra inferior fixa.
5. Polish confirma build, acessibilidade, responsividade e limites de escopo.

---

## Notes

- Tarefas `[P]` alteram arquivos distintos no mesmo estágio de dependência.
- Não criar testes, mocks, fixtures ou utilitários de teste sem nova solicitação explícita.
- Não adicionar Swift Package externo, persistência, DI, rede ou funcionalidade fora do escopo
  desta feature.
