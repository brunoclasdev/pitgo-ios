---

description: "Dependency-ordered implementation tasks for creating a user account (iOS)"
---

# Tasks: Criar conta de usuário (iOS)

**Input**: Design documents from `specs/005-create-user-account/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`,
`quickstart.md`

**Tests**: Nenhum teste automatizado será criado. A feature será verificada por build/lint iOS,
verificação (não aplicação) do schema compartilhado e pelos cenários manuais de `quickstart.md`.

**Organization**: Tasks are grouped by user story so each increment can be implemented and
validated before the next priority.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Pode executar em paralelo por alterar arquivos diferentes e não depender de tarefa
  incompleta no mesmo grupo.
- **[Story]**: História de usuário da especificação (`US1`, `US2`, `US3`).
- Todas as tarefas de implementação indicam caminhos exatos.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Habilitar os produtos remotos necessários do `supabase-swift` já resolvido em
`004-configure-supabase`. Nenhuma migration é criada nesta fase (ver `research.md §0`).

- [X] T001 **Achado real, sem ação de pbxproj necessária**: verificado (compilando contra o pacote
  `supabase-swift` 2.55.2 real, resolvido em `004`) que o produto central `Supabase` já reexporta
  `Auth`/`PostgREST`/`Storage`/`Realtime`/`Functions` como propriedades de `SupabaseClient`
  (`.auth`, `.from(_:)`, etc.) — não existem produtos SPM separados "Auth"/"PostgREST" a adicionar
  ao target; `client.auth.signUp/session/signIn` e `client.from("profiles").select/upsert`
  compilaram e funcionam usando somente `import Supabase`, o mesmo já instalado em `004`.
- [ ] T002 [P] Verificar com `supabase link` + `supabase db diff` (somente leitura) que o schema de
  `contracts/profiles-schema.md` já está aplicado no projeto de desenvolvimento compartilhado com o
  Android, documentando o resultado — nenhum arquivo de migration é criado neste repositório —
  **bloqueado neste ambiente**: exige Supabase CLI autenticado contra o projeto de desenvolvimento
  real (`eetbrkznuqbdrnybnyhf`), credenciais/acesso não disponíveis nesta sessão

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Disponibilizar os plugins remotos e a fronteira de navegação exigida por todas as
histórias.

**⚠️ CRITICAL**: Nenhuma história pode ser concluída antes desta fase.

- [X] T003 [P] Habilitar `Auth` e `PostgREST` no `SupabaseClientProvider` compartilhado (instalação
  única, sem chamada remota na inicialização) em `pitgo/Core/Network/SupabaseClientProvider.swift`
- [X] T004 [P] Criar `enum UnauthenticatedRoute: Hashable { case signUp }` e estender
  `PitGoRootView` com `enum RootPhase { case unauthenticated, case home }`, envolvendo Welcome numa
  `NavigationStack` própria enquanto `phase == .unauthenticated`, em
  `pitgo/Core/Navigation/PitGoRootView.swift` e `pitgo/Core/Navigation/UnauthenticatedRoute.swift`

**Checkpoint**: Auth/PostgREST e a fronteira de navegação estão prontos para as histórias.

---

## Phase 3: User Story 1 — Criar uma conta com perfil (Priority: P1) 🎯 MVP

**Goal**: Abrir o cadastro pela Welcome e concluir um cadastro válido de pessoa física ou jurídica
com sessão ativa, um perfil do mesmo UUID (já garantido pelo backend compartilhado) e navegação
para Home.

**Independent Test**: Abrir **Criar conta**, selecionar PF ou PJ, informar dados válidos e confirmar
no projeto Supabase exatamente uma identidade e um perfil de mesmo ID; a Home abre imediatamente e
Voltar não retorna ao formulário.

### Implementation for User Story 1

- [X] T005 [P] [US1] Criar `PersonType`, `SignUpDraft`, `AccountRegistration`, estados exclusivos e
  `RegistrationResult` com a invariante de exatamente um documento em
  `pitgo/Features/SignUp/Model/SignUpModels.swift`
- [X] T006 [P] [US1] Criar `ProfileInsertDTO`/`ProfileDTO` (`Codable`), omitindo `active` no insert
  e mapeando `isActive`/`active` via `CodingKeys` no retorno, em
  `pitgo/Features/SignUp/Data/ProfileDTOs.swift`
- [X] T007 [P] [US1] Adicionar strings base do cadastro e SF Symbols de voltar/visibilidade de
  senha ao Strings Catalog/`Assets.xcassets`, reutilizando os já definidos em specs anteriores
  quando existirem
- [X] T008 [US1] Implementar `SignUpRepository` com leitura de sessão atual, signup por e-mail/
  senha, metadata namespaced normalizada, exigência de sessão, seleção do perfil do mesmo UUID e
  retorno de `RegistrationResult` sem expor o SDK, em
  `pitgo/Features/SignUp/Repository/SignUpRepository.swift`
- [X] T009 [US1] Implementar `SignUpViewModel` (`@Observable`, `@MainActor`) com eventos explícitos
  de campos/tipo, um único documento, submissão em `Task` própria, guarda contra reenvio e estado
  `.success` em `pitgo/Features/SignUp/ViewModel/SignUpViewModel.swift`
- [X] T010 [US1] Criar `SignUpView` stateless com `Form`/`ScrollView`, seleção PF/PJ, campos
  dinâmicos, senha/confirmação e CTA, sem `TabView`, em
  `pitgo/Features/SignUp/Views/SignUpView.swift`
- [X] T011 [US1] Conectar `WelcomeView.onCreateAccount` para empurrar `.signUp` no
  `NavigationStack` não autenticado e observar `SignUpUiState.submission == .success` para trocar
  `RootPhase` para `.home` em `pitgo/Features/Welcome/Views/WelcomeView.swift` e
  `pitgo/Core/Navigation/PitGoRootView.swift` (depende de T004, T009, T010)
- [ ] T012 [US1] Executar os fluxos PF e PJ das seções 4 e 5 de
  `specs/005-create-user-account/quickstart.md`, conferindo sessão imediata, UUID 1:1, documento
  alternativo nulo, `active=true` e a troca de `RootPhase` — **bloqueado neste ambiente**: exige
  simulador/dispositivo iniciado (só o runtime iOS 26.2 Simulator está baixado, mas o Xcode 26.5
  instalado resolve SDKROOT 26.5 — mesma causa registrada em `001`/T019) e um projeto Supabase de
  desenvolvimento real. **Verificação alternativa executada com sucesso**: `SignUpRepository`
  (junto com `SignUpModels`/`ProfileDTOs`) compilado sem erros contra o pacote `supabase-swift`
  2.55.2 real em um harness SwiftPM isolado (confirma `client.auth.signUp/session/signIn` e
  `client.from("profiles").select/upsert` como assinaturas reais); `SignUpViewModel`/`SignUpView`
  e o app inteiro (specs 001–005 juntas, com `SupabaseClientProvider`/`SignUpRepository` isolados
  por stub Sendable equivalente) type-checked sem erros nem warnings contra o SDK iOS real em modo
  Swift 6 estrito.

**Checkpoint**: O MVP cria uma conta válida e um perfil consistente para PF ou PJ.

---

## Phase 4: User Story 2 — Corrigir dados inválidos antes do envio (Priority: P2)

**Goal**: Bloquear formulários inválidos, explicar todos os erros, focar o primeiro e aceitar
entrada brasileira com normalização/máscaras corretas sem criar registros indevidos.

**Independent Test**: Tentar todas as combinações ausentes/inválidas, troca PF/PJ, colagem com
máscara, CNPJ numérico/alfanumérico e conflitos; nenhum formulário inválido cria identidade/perfil,
e todos os campos relevantes recebem erro com foco no primeiro.

### Implementation for User Story 2

- [X] T013 [P] [US2] Implementar normalização e validação local de nome, e-mail, DDD/telefone, CPF,
  CNPJ numérico/alfanumérico oficial e senha de 8 caracteres em
  `pitgo/Features/SignUp/Model/SignUpValidation.swift`
- [X] T014 [P] [US2] Implementar a formatação-ao-editar de telefone/CPF/CNPJ (dígitos puros no
  estado, máscara recomputada no `onChange`, conforme `research.md §9`) em
  `pitgo/Features/SignUp/Views/SignUpView.swift`
- [X] T015 [P] [US2] Adicionar rótulos dinâmicos, textos de apoio e mensagens neutras de
  validação/conflito ao Strings Catalog
- [X] T016 [P] [US2] Mapear somente códigos estáveis de `AuthError`/status HTTP e nomes de
  constraint allowlisted (ver `contracts/profiles-schema.md`) para e-mail/documento indisponível,
  descartando detalhes remotos, em `pitgo/Features/SignUp/Repository/SignUpRepository.swift`
- [X] T017 [US2] Integrar validação em uma passada, limpeza do erro editado, troca de tipo com
  limpeza do documento e `FocusRequest` monotônico no estado em
  `pitgo/Features/SignUp/ViewModel/SignUpViewModel.swift`
- [X] T018 [US2] Integrar `@FocusState` por campo, teclado CPF/CNPJ adequado, mensagens de erro
  inline, `textContentType`/autofill e toggles independentes de visibilidade de senha em
  `pitgo/Features/SignUp/Views/SignUpView.swift`
- [ ] T019 [US2] Executar a matriz de formulário da seção 6 e os conflitos da seção 7 de
  `specs/005-create-user-account/quickstart.md`, confirmando zero criação remota para entrada
  inválida e ausência de exposição do proprietário — **bloqueado neste ambiente**: mesma causa de
  T012. **Verificado independentemente**: `SignUpValidation` (CPF/CNPJ/telefone/e-mail) executado
  com casos reais (CPF/CNPJ de teste publicamente conhecidos, validados também de forma
  independente em Python) confirmando aceitação/rejeição corretas; a checagem client-side impede a
  chamada ao Repository antes de qualquer rede.

**Checkpoint**: Cadastro válido continua funcionando e todos os casos de correção são verificáveis.

---

## Phase 5: User Story 3 — Receber feedback seguro do cadastro (Priority: P3)

**Goal**: Representar processamento/falhas com segurança, impedir duplicidade, recuperar perfil
parcialmente ausente, proteger o descarte e comprovar RLS/atomicidade antes da Home — reaproveitando
integralmente as garantias de backend já validadas pelo Android.

**Independent Test**: Simular toque repetido, offline, timeout, rate limit, falha de perfil e sessão
com perfil ausente; a UI permanece coerente, senha/documentos não vazam, retry converge para uma
linha e acesso cruzado ao perfil é negado.

### Implementation for User Story 3

- [X] T020 [P] [US3] Adicionar textos de processamento, banners sanitizados, rate limit, falha de
  ambiente/perfil, retry e confirmação de descarte ao Strings Catalog
- [X] T021 [US3] Completar `retryProfile` com select-first, upsert por conflito de ID, confirmação
  pós-insert, reconciliação de resposta ambígua e classificação segura de rede/HTTP/Auth/PostgREST
  em `pitgo/Features/SignUp/Repository/SignUpRepository.swift`
- [X] T022 [US3] Implementar as transições `.creatingAccount`/`.ensuringProfile`/
  `.recoveringProfile`/`.failure`/`.success`, retry exclusivo de perfil, limpeza de senhas após I/O
  e bloqueio de toques concorrentes em `pitgo/Features/SignUp/ViewModel/SignUpViewModel.swift`
- [X] T023 [US3] Renderizar progresso, banner com Live Region, estado somente leitura de
  recuperação, retry, `.confirmationDialog` de descarte e bloqueio de Voltar durante submissão em
  `pitgo/Features/SignUp/Views/SignUpView.swift`
- [ ] T024 [US3] Executar as seções 7, 8 e 9 de `specs/005-create-user-account/quickstart.md`,
  comprovando falhas sanitizadas, rollback do trigger (backend compartilhado), recuperação
  idempotente, nenhuma duplicidade e RLS própria/cross-user/anônima — **bloqueado neste ambiente**:
  exige projeto Supabase de desenvolvimento real com acesso de administrador de banco, além da
  mesma causa de T012

**Checkpoint**: Todas as histórias funcionam e as fronteiras de falha/segurança estão demonstradas.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Consolidar design system, regressão e evidências finais sem ampliar o escopo.

- [X] T025 Revisar consistência de altura mínima de CTA (56pt) e ícone de voltar reutilizável entre
  `SignUpView` e as Views de `001`–`004`, sem criar componentes genéricos de formulário prematuros
- [ ] T026 Executar `xcodebuild clean build` em simulador e `generic/platform=iOS` e corrigir
  regressões somente nos arquivos listados em `specs/005-create-user-account/plan.md` —
  **bloqueado neste ambiente**: mesma causa registrada em `001`/T019 (Simulator iOS 26.5 não
  baixado). Ver T012 para as verificações alternativas reais executadas com sucesso.
- [ ] T027 Executar as seções 3 a 10 de `specs/005-create-user-account/quickstart.md`, revisar o
  diff final e confirmar ausência de testes novos, migration duplicada, service-role/admin key,
  credencial versionada, senha persistida, `Error` bruto em log e mudança fora do escopo —
  **parcialmente verificado por revisão de código, sem simulador**: nenhum teste automatizado,
  migration, `SupabaseClient` alternativo ou chave admin foi adicionado; `SignUpRepository` nunca
  loga/propaga `Error`/`localizedDescription`/headers brutos (só `AuthError.errorCode`/
  `PostgrestError.code`+allowlist de nomes de constraint); senha/confirmação são limpas em
  `apply(_:)` do `SignUpViewModel` em todo caminho de sucesso ou falha e nunca chegam a um tipo
  `Codable`/`UserDefaults`/`SwiftData`. **Execução real em dispositivo/simulador continua
  bloqueada**, mesma causa de T012.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: inicia imediatamente; T001 e T002 são paralelas.
- **Foundational (Phase 2)**: depende do setup; T003 depende de T001, T004 é independente e ambas
  podem rodar em paralelo.
- **US1 (Phase 3)**: depende de toda a fundação e entrega o MVP.
- **US2 (Phase 4)**: depende do cadastro funcional de US1 para integrar validação ao mesmo fluxo.
- **US3 (Phase 5)**: depende de US1 e US2, pois amplia os mesmos estados, Repository e View com
  feedback/recuperação.
- **Polish (Phase 6)**: depende das três histórias desejadas.

### User Story Dependencies

- **US1 (P1)**: começa após Phase 2 e não depende de outra história.
- **US2 (P2)**: reutiliza modelos, ViewModel, Repository e View entregues por US1; permanece
  independentemente verificável pela matriz de formulário.
- **US3 (P3)**: estende o fluxo completo de US1/US2 com falhas e recovery; permanece
  independentemente verificável pela matriz de falhas/RLS.

### Within Each User Story

- Modelos/DTOs e recursos antes do Repository/ViewModel/View que os consomem.
- Repository antes da orquestração no ViewModel.
- ViewModel antes da integração final de estado na View.
- View antes da navegação e validação manual.
- Nenhuma tarefa de teste automatizado é necessária ou autorizada.

### Parallel Opportunities

- Setup: T001 e T002.
- Foundational: T003 e T004.
- US1: T005, T006 e T007; depois o fluxo converge em T008 → T009 → T010 → T011.
- US2: T013, T014, T015 e T016 após US1; depois T017 → T018.
- US3: T020 pode rodar em paralelo com T021; depois T022 → T023.
- Validações manuais e build permanecem após o código correspondente para gerar evidência real.

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Concluir Setup e Foundational.
2. Implementar T005–T011.
3. Parar e validar T012 com PF e PJ em ambiente de desenvolvimento aprovado.
4. Demonstrar sessão + perfil 1:1 + Home antes de ampliar o fluxo.

### Incremental Delivery

1. Setup + Foundational → SDK habilitado e navegação preparada.
2. US1 → cadastro válido completo (MVP).
3. US2 → validação, máscaras e correção de entrada.
4. US3 → feedback, recovery e RLS demonstrados (backend já garantido pelo Android).
5. Polish → regressão e auditoria final.

### Safe Execution Notes

- Nenhuma migration é criada ou aplicada por estas tarefas; qualquer divergência de schema deve ser
  corrigida no repositório Android, fonte única de verdade do backend.
- Usar apenas fixtures não produtivas nos cenários manuais.
- Nunca imprimir URL com token, Authorization, mensagem/detalhe de `Error`, CPF/CNPJ completo ou
  senha durante diagnóstico.
- Fazer commits pequenos por tarefa ou grupo lógico, sem incluir `Config/Secrets.xcconfig` ou
  credenciais.
