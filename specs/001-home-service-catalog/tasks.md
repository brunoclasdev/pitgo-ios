---

description: "Dependency-ordered implementation tasks for the Homepage service catalog (iOS)"
---

# Tasks: Catálogo de Serviços na Homepage (iOS)

**Input**: Design documents from `specs/001-home-service-catalog/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`,
`quickstart.md`

**Tests**: Nenhuma tarefa de teste automatizado é gerada — não solicitado explicitamente e a
constituição não exige. Cada história termina com uma tarefa de validação manual do
`quickstart.md`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Pode rodar em paralelo — arquivos diferentes, sem dependência de tarefa não concluída.
- **[Story]**: Mapeia a tarefa para US1/US2 do `spec.md`.
- Toda tarefa nomeia o arquivo exato afetado.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Preparar o projeto Xcode (ainda no template padrão) para a stack Swift 6/SwiftUI.

- [X] T001 [P] Configurar iOS Deployment Target 17.0 e Swift Language Version 6 nas Build Settings
  do alvo `pitgo` em `pitgo.xcodeproj/project.pbxproj` — concorrência estrita já é o padrão do modo
  de linguagem Swift 6, então `SWIFT_STRICT_CONCURRENCY` (flag específica do modo Swift 5) não se
  aplica
- [X] T002 [P] Removido `pitgo/ContentView.swift` inteiramente (em vez de esvaziado) — `pitgoApp.swift`
  passou a instanciar `PitGoRootView` diretamente, igual à árvore de arquivos de `plan.md`, que já
  não lista `ContentView.swift`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Design system mínimo compartilhado por qualquer feature futura.

**⚠️ CRITICAL**: Nenhuma história começa antes desta fase.

- [X] T003 [P] Definir paletas roxas Light/Dark e cores de fundo, superfície e texto em
  `pitgo/Core/DesignSystem/Colors.swift` — mesmos valores hexadecimais de
  `core/design/theme/Color.kt` do app Android, para paridade de marca entre plataformas
- [X] T004 [P] Definir estilos de tipografia compatíveis com Dynamic Type (sem tamanhos fixos que
  quebrem escala) em `pitgo/Core/DesignSystem/Typography.swift`
- [X] T005 Integrar paletas e tipografia em `PitGoTheme`, respeitando `colorScheme` do sistema e
  sem seletor manual nesta feature, em `pitgo/Core/DesignSystem/PitGoTheme.swift` (depende de T003
  e T004)

**Checkpoint**: Design system pronto; nenhuma feature ainda depende dele além do que vem a seguir.

---

## Phase 3: User Story 1 - Visualizar o catálogo principal (Priority: P1) 🎯 MVP

**Goal**: Homepage offline exibindo as cinco categorias, sem interação de navegação ainda.

**Independent Test**: Abrir o app e confirmar as cinco categorias visíveis, legíveis e
identificáveis, mesmo sem tocar em nenhuma.

### Implementation for User Story 1

- [X] T006 [P] [US1] Adicionar nome do app, títulos da homepage, cinco nomes de categoria e
  descrições acessíveis num Strings Catalog (`pitgo/Resources/Localizable.xcstrings`)
- [X] T007 [P] [US1] Criar cinco identificações visuais coerentes e distintas para as categorias —
  resolvido com SF Symbols reais e confirmados (`circle.hexagongrid.fill`, `bolt.car.fill`,
  `battery.100`, `arrow.triangle.2.circlepath`, `wrench.and.screwdriver.fill`), referenciados
  diretamente por nome em `ServiceCategory.swift`; nenhum asset vetorial novo foi necessário em
  `pitgo/Assets.xcassets`
- [X] T008 [P] [US1] Implementar `ServiceCategoryID` (`enum` `Hashable`/`CaseIterable`) e
  `ServiceCategory` com IDs/route values estáveis, recursos locais e ordem 0–4 em
  `pitgo/Features/Home/Model/ServiceCategory.swift` — `Hashable` de `ServiceCategory` implementado
  manualmente por `id` (achado real do type-check: `LocalizedStringResource`, usado em `name`/
  `accessibilityAction`, não conforma a `Hashable`, então a síntese automática não compila)
- [X] T009 [US1] Implementar `HomeUiState` imutável e `HomeViewModel` (`@Observable`,
  `@MainActor`) preenchido imediatamente pelas cinco categorias locais em
  `pitgo/Features/Home/ViewModel/HomeViewModel.swift` (depende de T006–T008)
- [X] T010 [US1] Implementar `HomeView` stateless, heading e `LazyVGrid` adaptável com `id`
  estável por categoria, cards sem truncamento, em `pitgo/Features/Home/Views/HomeView.swift`
  (depende de T009)
- [X] T011 [US1] Substituir o conteúdo padrão por `PitGoTheme` envolvendo `HomeView` em
  `pitgo/pitgoApp.swift` (depende de T005 e T010) — via `PitGoRootView`, já com o `NavigationStack`
  de T016, pois a Home isolada sem host de navegação não é um destino real do produto
- [ ] T012 [US1] Executar e registrar os cenários Offline catalog, Responsive layout e Dynamic
  Type and themes de `specs/001-home-service-catalog/quickstart.md` para validar o MVP visual —
  **bloqueado neste ambiente**: exige simulador/dispositivo iniciado (ver nota em T019)

**Checkpoint**: Build e lint passam; a homepage mostra as cinco categorias offline, em Light/Dark,
respeitando Dynamic Type — sem nenhuma navegação ainda.

---

## Phase 4: User Story 2 - Escolher uma categoria de serviço (Priority: P2)

**Goal**: Tocar numa categoria leva ao destino mínimo de busca de prestadores, com proteção contra
duplicidade e retorno padrão.

**Independent Test**: Selecionar cada categoria individualmente e confirmar feedback imediato,
categoria correta no destino e retorno funcional.

### Implementation for User Story 2

- [X] T013 [P] [US2] Centralizar `PitGoRoute` (`enum Hashable`, incluindo
  `.providerSearch(categoryID: ServiceCategoryID)`) em `pitgo/Core/Navigation/PitGoRoute.swift`
- [X] T014 [P] [US2] Implementar o destino mínimo com a categoria recebida e navegação de voltar
  nativa em `pitgo/Features/Provider/Views/ProviderSearchEntryView.swift`, adicionando seus textos
  ao Strings Catalog
- [X] T015 [P] [US2] Tornar cada card um único elemento de acessibilidade tocável de pelo menos
  44×44pt, com feedback visual e rótulo "Buscar prestadores de {categoria}", emitindo somente
  `ServiceCategoryID`, em `pitgo/Features/Home/Views/HomeView.swift`
- [X] T016 [US2] Criar `PitGoRootView` com `NavigationStack`, seleção protegida contra navegação
  duplicada, `.navigationDestination(for: PitGoRoute.self)` e back stack padrão, e conectá-lo em
  `pitgo/pitgoApp.swift` (depende de T013–T015)
- [ ] T017 [US2] Executar e registrar os cenários Accessibility, Selection and duplicate
  protection, Back behavior and state restoration e Invalid internal argument de
  `specs/001-home-service-catalog/quickstart.md` — **bloqueado neste ambiente**: exige simulador/
  dispositivo iniciado com VoiceOver (ver nota em T019)

**Checkpoint**: Seleção de qualquer categoria navega para o destino correto, sem duplicar entradas
e com retorno funcional; VoiceOver anuncia cada card corretamente.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Confirmar ausência de escopo indevido e build limpo.

- [X] T018 Auditar `pitgo/` para confirmar ausência de boilerplate do template, Swift Packages de
  terceiros, rede, persistência, DI, autenticação, localização, dados de prestadores e código sem
  uso — árvore final revisada, sem sobras do template e sem dependências novas
- [ ] T019 Executar `xcodebuild -project pitgo.xcodeproj -scheme pitgo clean build` conforme
  `specs/001-home-service-catalog/quickstart.md` — **bloqueado neste ambiente**: o Xcode 26.5
  instalado resolve `SDKROOT`/`iphonesimulator26.5`, mas só o runtime iOS 26.2 Simulator está
  baixado (`xcrun simctl list runtimes`), então nenhuma destination de simulador ou dispositivo é
  elegível (`iOS 26.5 is not installed. Please download and install the platform from Xcode >
  Settings > Components`); gap de provisionamento da máquina, não do código. Uma criação de scheme
  compartilhado (`pitgo.xcodeproj/xcshareddata/xcschemes/pitgo.xcscheme`, ausente até então) foi
  necessária à parte e já está no repositório. **Verificação alternativa executada com sucesso**:
  `xcrun -sdk iphoneos swiftc -typecheck -target arm64-apple-ios17.0 -swift-version 6` sobre todos
  os arquivos Swift da feature — sem erros após corrigir o achado real de T008 (conformidade manual
  de `Hashable`). Para concluir esta tarefa de verdade: baixar o Simulator iOS 26.5 em Xcode →
  Settings → Components (ou `xcodebuild -downloadPlatform iOS`) e reexecutar o `xcodebuild` acima.
- [ ] T020 Executar o roteiro manual completo de `specs/001-home-service-catalog/quickstart.md` em
  Light/Dark, offline, iPhone/iPad, Dynamic Type e VoiceOver, confirmando todos os critérios de
  `specs/001-home-service-catalog/spec.md` — **bloqueado neste ambiente**: mesma causa de T019

**Checkpoint**: Build limpo, roteiro manual concluído, nenhum item fora do escopo introduzido.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: começa imediatamente; T001 e T002 podem rodar em paralelo.
- **Foundational (Phase 2)**: depende do Setup; T003 e T004 podem rodar em paralelo, T005 depende
  de ambos.
- **User Story 1 (Phase 3)**: depende da Foundation; T006–T008 podem rodar em paralelo, seguidas
  por T009, T010, T011 e T012.
- **User Story 2 (Phase 4)**: depende da User Story 1 porque torna os cards existentes
  interativos; T013–T015 podem rodar em paralelo, seguidas por T016 e T017.
- **Polish (Phase 5)**: depende das histórias desejadas; executar T018, T019 e T020 nessa ordem.

### User Story Dependencies

```text
Setup → Foundation → US1 (MVP) → US2 → Polish
```

- **User Story 1 (P1)**: não depende de outra história e entrega o catálogo visual offline.
- **User Story 2 (P2)**: reutiliza o catálogo de US1, mas possui critério de teste próprio para
  seleção, categoria, duplicação e retorno.

### Within Each User Story

- Recursos e modelo antes do ViewModel.
- ViewModel antes da renderização da View.
- Conteúdo da View antes da integração no host de navegação.
- Rotas, destino e callback antes da integração completa de navegação.
- Implementação antes da validação manual da história.

### Parallel Opportunities

- T001 e T002 desde o início.
- T003 e T004 após Setup.
- T006, T007 e T008 após Foundation.
- T013, T014 e T015 após US1.
- Não paralelizar tarefas que alteram `HomeView.swift`, `pitgoApp.swift` ou o Strings Catalog em
  fases diferentes.

---

## Parallel Example: User Story 1

```text
Task T006: Textos da homepage em pitgo/Resources/Localizable.xcstrings
Task T007: Identificações visuais das categorias em pitgo/Assets.xcassets
Task T008: Modelo do catálogo em pitgo/Features/Home/Model/ServiceCategory.swift
```

## Parallel Example: User Story 2

```text
Task T013: Rotas centralizadas em pitgo/Core/Navigation/PitGoRoute.swift
Task T014: Destino de entrada em pitgo/Features/Provider/Views/ProviderSearchEntryView.swift
Task T015: Interação dos cards em pitgo/Features/Home/Views/HomeView.swift
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup.
2. Complete Phase 2: Foundational.
3. Complete Phase 3: User Story 1.
4. **STOP AND VALIDATE**: execute T012 e confirme o catálogo visual offline.
5. Demonstre a homepage antes de iniciar navegação, se uma entrega parcial for desejada.

### Incremental Delivery

1. Setup + Foundation deixam o projeto pronto para SwiftUI.
2. US1 entrega o catálogo offline navegável visualmente (MVP).
3. US2 adiciona seleção, destino correto, proteção contra duplicação e retorno.
4. Polish confirma build, acessibilidade, responsividade e limites de escopo.

### Parallel Team Strategy

1. A equipe conclui Setup e Foundation respeitando as dependências internas.
2. Em US1, textos, identificações visuais e modelo podem ser produzidos em paralelo.
3. Após o MVP, rotas, destino mínimo e interação dos cards podem ser produzidos em paralelo.
4. Cada fase integra e valida antes de iniciar a seguinte.

---

## Notes

- Tarefas `[P]` alteram arquivos distintos no mesmo estágio de dependência.
- Rótulos `[US1]` e `[US2]` garantem rastreabilidade com `spec.md`.
- Não criar testes, mocks, fixtures ou utilitários de teste sem nova solicitação explícita.
- Não adicionar Swift Package externo, persistência (SwiftData/Core Data), DI, rede ou
  funcionalidade fora do escopo desta feature.
