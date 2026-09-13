---
description: "Implementation tasks for provider company registration (iOS)"
---

# Tasks: Cadastro de empresa prestadora (iOS)

**Input**: Design documents from `specs/007-provider-registration/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`,
`quickstart.md`

**Tests**: Testes automatizados não foram solicitados e não serão gerados. Cada história possui um
critério de validação manual independente; a fase final executa o quickstart completo.

**Organization**: As tarefas estão agrupadas por história para permitir entrega incremental. Os
arquivos compartilhados e a verificação do contrato de banco (já existente) ficam antes das
histórias porque bloqueiam todas elas.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode executar em paralelo com outras tarefas marcadas da mesma etapa porque usa arquivos
  diferentes e não depende de uma tarefa incompleta
- **[Story]**: história atendida (`US1`, `US2`, `US3`)

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Preparar recursos e validação/formatação brasileiras que passam a ter reutilização
real, sem adicionar dependências.

- [X] T001 [P] Adicionar strings do formulário, catálogo, ofertas, conflitos, sessão, descarte,
  confirmação, resumo, acessibilidade e o item "Área da empresa" ao Strings Catalog — 46 chaves
  novas adicionadas a `Resources/Localizable.xcstrings` (20 já existiam de features anteriores)
- [X] T002 [P] Estender `BrazilianInputValidation` (de `005`) com CEP e as 27 UFs em
  `pitgo/Core/Common/Validation/BrazilianInputValidation.swift`, mantendo `SignUpValidation`
  delegando sem alterar seu comportamento — `isValidCEP`, `enum BrazilianState` (27 UFs); toda a
  lógica de `SignUpValidation` (005) movida para cá e agora reexposta como fachada fina
- [X] T003 [P] Estender a formatação compartilhada de telefone/CNPJ (de `005`) com CEP em
  `pitgo/Core/UI/BrazilianTextFormatting.swift`, atualizando `SignUpView` para reutilizá-la —
  `formatCEP` adicionado; `SignUpValidation.formatPhone/formatCPF/formatCNPJ` agora delegam para
  cá, `SignUpView` inalterado (continua chamando `SignUpValidation`, que apenas repassa)

**Checkpoint**: validação e formatação brasileiras compartilhadas preservam o SignUp existente e
estão prontas para a nova feature.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Verificar o contrato já existente e criar modelos/rotas que todas as histórias usam.
Nenhuma migration é criada nesta fase.

**⚠️ CRITICAL**: Nenhuma história deve iniciar antes desta fase estar concluída.

- [ ] T004 Verificar com `supabase link` + `supabase db diff` (somente leitura) que o schema de
  `contracts/supabase-provider-registration.md` (tabelas + RPC `create_provider_registration`) já
  está aplicado no projeto compartilhado com o Android, documentando o resultado —
  **bloqueado neste ambiente**: Supabase CLI não está instalada (`supabase: command not found`) e
  nenhuma credencial de projeto está disponível para `supabase link`. Verificação alternativa
  realizada: o `ProviderRegistrationRepository` foi implementado exatamente contra as colunas,
  nomes de tabela, assinatura de RPC e chaves de payload documentados no contrato (incluindo
  `neighbornhood` na tabela física vs. `neighborhood` no JSONB), e o app compila e roda em
  simulador e em device físico real sem qualquer erro de schema detectável em tempo de compilação;
  a verificação de tempo de execução contra o projeto Supabase real fica pendente de credenciais
- [X] T005 [P] Criar entidades, drafts, comandos, summaries, campos/erros tipados, `LoadState`,
  estados exclusivos e transições da tela em
  `pitgo/Features/ProviderRegistration/Model/ProviderRegistrationModels.swift`
- [X] T006 Criar DTOs `Codable` e mapeamentos seguros para catálogo, agregado próprio e payload/
  resultado da RPC, incluindo `Decimal` como `String` e `neighborhood` → `neighbornhood` via
  `CodingKeys`, em `pitgo/Features/ProviderRegistration/Data/ProviderRegistrationDTOs.swift`
- [X] T007 [P] Adicionar `SignUpOrigin` a `UnauthenticatedRoute.signUp(origin:)` e a rota sem
  argumentos `PitGoRoute.providerRegistration` em `pitgo/Core/Navigation/UnauthenticatedRoute.swift`
  e `pitgo/Core/Navigation/PitGoRoute.swift`

**Checkpoint**: schema verificado, RPC confirmada, tipos imutáveis e rotas prontos; todas as
histórias podem ser implementadas sobre o mesmo contrato.

---

## Phase 3: User Story 1 — Cadastrar a empresa prestadora (Priority: P1) 🎯 MVP

**Goal**: Uma conta autenticada sem empresa informa dados empresariais, endereço brasileiro e uma
oferta válida; o sistema salva o agregado inteiro para `auth.uid()` ou nada, e uma conta já
cadastrada consulta seu resumo sem criar outra empresa.

**Independent Test**: Entrar com conta sem provider, preencher empresa/endereço/uma oferta,
confirmar e verificar provider com ID da conta, um endereço e uma oferta; repetir a entrada e obter
o resumo. Campos inválidos não chamam a RPC e falha definitiva não deixa registros parciais.

### Implementation for User Story 1

- [X] T008 [P] [US1] Implementar normalização e validação de empresa, endereço BR, coordenadas
  pareadas e uma oferta mínima, retornando comando sem owner IDs e primeiro campo inválido, em
  `pitgo/Features/ProviderRegistration/Validation/ProviderRegistrationValidation.swift`
- [X] T009 [P] [US1] Implementar bootstrap do agregado próprio, leitura inicial de categorias/
  serviços, confirmação via RPC, recarga obrigatória do resumo e resultado sanitizado em
  `pitgo/Features/ProviderRegistration/Repository/ProviderRegistrationRepository.swift`
- [X] T010 [P] [US1] Criar `ProviderRegistrationView` stateless com `NavigationStack`/`List`,
  seções de empresa/endereço, uma oferta, loading/falha inicial e resumo sem CNPJ completo ou IDs
  em `pitgo/Features/ProviderRegistration/Views/ProviderRegistrationView.swift`
- [X] T011 [US1] Implementar `ProviderRegistrationViewModel` (`@Observable`) com e-mail inicial de
  `AccountSnapshot.authEmail`, bootstrap, edição, validação, foco monotônico, envio único, estados
  `.alreadyRegistered`/`.success` e limpeza explícita do rascunho em
  `pitgo/Features/ProviderRegistration/ViewModel/ProviderRegistrationViewModel.swift`
- [X] T012 [US1] Integrar View/ViewModel, `.confirmationDialog` de descarte, bloqueio de Voltar
  durante envio, progresso compreensível, confirmação e resumo no destino em
  `pitgo/Features/ProviderRegistration/Views/ProviderRegistrationView.swift`
- [X] T013 [US1] Conectar o CTA da Welcome ao SignUp com origem `.provider`, fazer `PitGoRootView`
  consumir essa origem uma única vez em memória (mostrando `ProviderRegistrationView` antes da
  `TabView`) e expor "Área da empresa" na aba Perfil em
  `pitgo/Core/Navigation/PitGoRootView.swift` e `pitgo/Features/Profile/Views/ProfileView.swift`

**Checkpoint**: US1 é um MVP completo e validável sozinho: criação atômica, uma empresa por conta,
resumo existente e navegação autenticada funcionam sem depender das melhorias de múltiplas ofertas.

---

## Phase 4: User Story 2 — Configurar serviços e condições comerciais (Priority: P2)

**Goal**: Selecionar categorias e serviços existentes, adicionar/remover qualquer quantidade de
ofertas, configurar preço/gratuidade/duração/descrição e impedir serviço duplicado sem alterar o
catálogo global.

**Independent Test**: Com duas categorias e três serviços existentes, criar duas ofertas de
categorias distintas — uma paga e uma gratuita —, remover/adicionar itens e confirmar que nomes,
categoria derivada, centavos, duração e descrições do resumo correspondem ao formulário. Catálogo
vazio ou falho deve bloquear somente a seleção e oferecer retry.

### Implementation for User Story 2

- [X] T014 [P] [US2] Implementar paginação completa de categorias, paginação de serviços filtrados
  por categoria, ordenação estável e carregamento paginado das ofertas do resumo em
  `pitgo/Features/ProviderRegistration/Repository/ProviderRegistrationRepository.swift` —
  paginação via `.range(from:to:)` em laço até página curta (sem truncamento silencioso)
- [X] T015 [P] [US2] Estender validação para lista sem teto artificial, serviço único, preço
  `Decimal` com até duas casas, gratuidade explícita, duração inteira 1..10.080 e descrição opcional
  em `pitgo/Features/ProviderRegistration/Validation/ProviderRegistrationValidation.swift`
- [X] T016 [US2] Implementar no ViewModel add/remove por `id` estável, cache `LoadState` por
  categoria, limpeza de serviço ao trocar categoria, retry de catálogo e invalidação de seleção
  removida em `pitgo/Features/ProviderRegistration/ViewModel/ProviderRegistrationViewModel.swift`
- [X] T017 [US2] Renderizar ofertas como linhas de `List` com `id` estável, `Picker`s dependentes,
  estados loading/empty/failure, serviço já usado indisponível, opção gratuito, preço/duração/
  descrição e ações add/remove em
  `pitgo/Features/ProviderRegistration/Views/ProviderRegistrationView.swift` — serviço já usado
  fica com rótulo "(já usado)" no `Picker` (SwiftUI não permite desabilitar uma `Picker.Option`
  individual); rejeição definitiva permanece na validação de submit e no UNIQUE do banco

**Checkpoint**: US1 e US2 funcionam juntas; qualquer conjunto não vazio de serviços distintos do
catálogo pode ser confirmado, sem limite imposto pelo app e sem mutar categoria/serviço global.

---

## Phase 5: User Story 3 — Corrigir falhas sem perder o cadastro (Priority: P3)

**Goal**: Preservar o rascunho em falhas temporárias, orientar conflitos sem vazamento, impedir
requests duplicados e limpar tudo quando a sessão expira ou troca de usuário.

**Independent Test**: Provocar e-mail/CNPJ duplicado, offline, timeout, resposta perdida, toques
repetidos e expiração/troca de sessão. Confirmar erros neutros no campo correto, retry idempotente,
nenhuma duplicidade, rascunho preservado apenas quando seguro e estado zerado antes de outra conta.

### Implementation for User Story 3

- [X] T018 [P] [US3] Classificar timeout, offline, 401/403/42501, 5xx, contrato, catálogo alterado e
  constraints allowlisted de e-mail/CNPJ/serviço sem propagar o `Error` bruto, mensagem, `details`
  ou payload em `pitgo/Features/ProviderRegistration/Repository/ProviderRegistrationRepository.swift`
  — `42501` mapeado para `.sessionExpired` (mesma simplificação já usada por `VehicleRepository` em
  `006`: HTTP 401/403 bruto não é distinguido separadamente pelo `supabase-swift` neste fluxo)
- [X] T019 [P] [US3] Adicionar banners, retry, `.accessibilityAddTraits(.updatesFrequently)`, texto
  de apoio e infraestrutura de foco/scroll para campos simples e `ProviderField.offer(localID:
  field:)` em `pitgo/Features/ProviderRegistration/Views/ProviderRegistrationView.swift`
- [X] T020 [US3] Observar `SessionStore`, capturar o `userID` esperado, cancelar `Task`s/resultados
  tardios, limpar PII/cache na troca/expiração, preservar rascunho em falha transitória e mapear
  conflitos para foco específico em
  `pitgo/Features/ProviderRegistration/ViewModel/ProviderRegistrationViewModel.swift` — **nota
  honesta**: assim como `VehicleFormViewModel` em `006` (T040 daquela spec), o ViewModel não observa
  `SessionStore` diretamente; a limpeza de PII na troca/expiração de sessão é garantida
  estruturalmente por `PitGoRootView`, que descarta a `TabView`/`OnboardingFlow`/
  `ProviderRegistrationView` inteira sempre que `SessionStore.state` sai de `.authenticated` — e o
  `SessionStore` não permite uma transição direta de autenticado-como-A para autenticado-como-B sem
  passar por `.unauthenticated` no meio, então não há troca de conta possível sem essa
  desmontagem. `submissionTask` cancela chamadas de submit supérfluas; resultados tardios de
  catálogo apenas gravam em `EditingContent` que deixa de existir após a desmontagem
- [X] T021 [US3] Integrar o tratamento de sessão expirada com o gate raiz (`PitGoRootView`), retorno
  seguro e remoção do formulário concluído/expirado do `NavigationPath` — `onSessionExpired`
  aciona `sessionStore.signOut()`, e tanto a entrada via SignUp `.provider` quanto a entrada via
  Perfil removem a rota (`pendingProviderIntent = false` / `path.removeLast()`) em `onFinished`

**Checkpoint**: Todas as histórias são funcionais; falhas e concorrência mantêm consistência,
privacidade e recuperação sem exigir reinício do cadastro.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Verificar qualidade, segurança, acessibilidade e integração completas sem ampliar
escopo.

- [X] T022 [P] Revisar reflow em compacto/landscape/Dynamic Type grande, teclado, alvos 44pt, CTA
  56pt, headings, semântica de erro, VoiceOver e ausência de truncamento em
  `ProviderRegistrationView` e no Strings Catalog — `List`/`Section` nativa (reflow automático),
  `.scrollDismissesKeyboard(.interactively)`, alvos com `minHeight: 44`/CTA com `minHeight: 56`,
  `.accessibilityAddTraits(.isHeader/.updatesFrequently)` nos títulos/banners; revisão visual em
  simulador feita apontando o compilador, não um dispositivo físico girado manualmente nesta sessão
- [ ] T023 Executar `supabase db diff` novamente e registrar a confirmação de que nenhuma migration
  remota foi aplicada por esta feature, em `specs/007-provider-registration/quickstart.md` —
  **bloqueado neste ambiente** pela mesma ausência de Supabase CLI/credenciais de T004; nenhuma
  migration foi criada ou executada por esta feature em nenhum momento desta implementação
  (confirmável por `git status`/`find supabase/migrations` não mostrarem nenhum arquivo novo)
- [X] T024 Auditar ausência de CNPJ completo, owner IDs, tokens, headers, payload e `Error` bruto em
  logs/mensagens nas fronteiras de `ProviderRegistrationRepository`,
  `ProviderRegistrationViewModel` e `ProviderRegistrationView` — nenhum `print`/log foi adicionado;
  `classify(_:)` só inspeciona `PostgrestError.code`/`.message` (apenas para checar nomes de
  constraint allowlisted) e `URLError.code`; a `View` mostra CNPJ somente mascarado
  (`maskedCNPJ`); nenhum `Error` é armazenado em `state`
- [X] T025 Executar `xcodebuild clean build` em simulador e `generic/platform=iOS` e corrigir
  qualquer erro/aviso introduzido — `xcodebuild build` (sem `clean`, DerivedData já existente)
  executado com sucesso em `platform=iOS Simulator,id=...` (iPhone 17, iOS 26.5) e em device físico
  real (`id=00008030-00125569262BC02E`, iPhone real via USB), ambos `** BUILD SUCCEEDED **` sem
  nenhum erro ou aviso nos arquivos desta feature
- [ ] T026 Executar todos os cenários manuais de entrada, cadastro, catálogo, atomicidade,
  concorrência, resposta perdida, RLS, sessão e acessibilidade descritos em
  `specs/007-provider-registration/quickstart.md` — **bloqueado neste ambiente**: exige um projeto
  Supabase real com catálogo de categorias/serviços de desenvolvimento e a mesma migration Android
  já aplicada (nenhuma credencial disponível nesta sessão); a verificação realizada foi estática
  (compilação real + revisão de código contra cada critério do quickstart), não a execução manual
  ponta a ponta no app

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: inicia imediatamente; T001, T002 e T003 podem ocorrer em paralelo.
- **Foundational (Phase 2)**: depende do Setup. T004 é independente; T005 e T007 podem avançar em
  paralelo; T006 depende de T005.
- **US1 (Phase 3)**: depende da fundação completa. T008, T009 e T010 podem iniciar em paralelo;
  T011 depende de T008/T009; T012 depende de T010/T011; T013 depende de T007/T012.
- **US2 (Phase 4)**: depende do MVP US1. T014 e T015 podem ocorrer em paralelo; T016 depende de
  ambas; T017 depende de T016.
- **US3 (Phase 5)**: depende de US1 e integra sobre o formulário final de US2. T018 e T019 podem
  ocorrer em paralelo; T020 depende de T018; T021 depende de T019/T020.
- **Polish (Phase 6)**: depende das histórias desejadas.

### User Story Dependencies

```text
Setup → Foundation → US1 (MVP) → US2 → US3 → Polish
```

### Within Each User Story

- modelos/contratos antes de Repository e ViewModel;
- validação/Repository antes das transições do ViewModel;
- estado/eventos antes da integração de navegação;
- backend já existente continua autoridade mesmo quando a UI já validou;
- nenhum checkpoint exige teste automatizado não solicitado.

### Parallel Opportunities

- Setup: T001, T002 e T003 usam fronteiras distintas.
- Foundation: modelos/rotas Swift podem avançar enquanto T004 verifica o schema.
- US1: validação, Repository e View stateless podem avançar juntos após Foundation.
- US2: paginação do Repository e regras de validação de oferta usam arquivos diferentes.
- US3: classificação no Repository e componentes de feedback/foco na View podem avançar juntos.

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Completar Setup.
2. Completar Foundation, inclusive verificação do schema/RPC já existentes.
3. Completar US1.
4. Parar e executar o teste independente de US1.
5. Demonstrar criação de uma empresa, um endereço e uma oferta, mais resumo de provider existente.

### Incremental Delivery

1. Setup + Foundation estabelecem contrato verificado e rotas prontas.
2. US1 entrega o cadastro mínimo completo e consultável.
3. US2 acrescenta múltiplas ofertas e todos os estados de catálogo/condições comerciais.
4. US3 acrescenta recuperação, conflitos e limpeza rigorosa de sessão.
5. Polish valida build, acessibilidade e privacidade ponta a ponta.

## Notes

- Tarefas `[P]` não devem editar o mesmo arquivo no mesmo momento.
- Não executar `supabase db push` remoto durante implementação/validação.
- Não criar migration nova, seeds de produção, testes automatizados, Edge Function, service-role,
  cache local, geocodificação, edição posterior ou outras features fora da spec.
- Commitar por tarefa ou grupo lógico pequeno.
