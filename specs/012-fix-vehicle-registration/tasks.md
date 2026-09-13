---
description: "Implementation tasks to fix vehicle registration and field errors (iOS)"
---

# Tasks: Corrigir cadastro de veículos e erros por campo (iOS)

**Input**: Design documents from `specs/012-fix-vehicle-registration/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`,
`quickstart.md`

**Tests**: Sem testes automatizados, conforme a governança do projeto.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup (Shared Infrastructure)

- [X] T001 Verificar com `supabase link` + consultas somente leitura via `supabase db query --linked`
  que `create_vehicle`/`set_primary_vehicle` já estão restauradas no projeto compartilhado
  (`eetbrkznuqbdrnybnyhf`) — confirmado nesta sessão: ambas as funções existem, `prosecdef = true`,
  `search_path = ""`, `EXECUTE` concedido somente a `authenticated`/`service_role`/`postgres` (nunca
  `public`/`anon`), RLS habilitado em `public.vehicles`, e os SQLSTATEs `P2001..P2008`/`P2011..P2013`
  (mais o fallback `P2099` para violação não mapeada) e `P0002` aparecem exatamente como descrito em
  `contracts/vehicle-rpcs.md`

---

## Phase 2: Foundational (Blocking Prerequisites)

- [X] T002 [P] Ampliar os resultados e falhas tipados para `.fieldFailure`/`.rpcUnavailable`,
  preservando `VehicleFormOrigin` e a ordem de `VehicleField`, em
  `pitgo/Core/Vehicle/Model/VehicleModels.swift` (`VehicleFormResult` agora
  `success/fieldFailure(VehicleField, VehicleFieldError)/failure(VehicleFormFailureReason)`) e
  `pitgo/Features/Garage/Model/GarageUiModels.swift` (`VehicleFormFailureReason` ganhou
  `.sessionExpired/.rpcUnavailable/.vehicleUnavailable/.contract/.timeout`; `.success` agora carrega
  o `Vehicle` criado)
- [X] T003 [P] Validação por campo reutilizável (`isFieldValueValid`, nova nesta sessão em
  `VehicleFormViewModel`) usando as mesmas funções de normalização/limite dinâmico de ano já
  existentes em `pitgo/Core/Vehicle/Validation/VehicleValidation.swift` — nenhuma mudança na ordem
  da validação completa de `submit()`

---

## Phase 3: User Story 1 - Cadastrar veículo com os dados mínimos (Priority: P1) 🎯 MVP

**Independent Test**: Autenticar uma conta cliente sem veículos, informar marca e modelo válidos,
manter os demais campos vazios e confirmar que o veículo é salvo como principal e aparece nas áreas
da conta que exibem o veículo atual.

### Implementation for User Story 1

- [X] T004 [P] [US1] Adicionar `applyAuthoritativePrimaryVehicle(_:)` usando somente o veículo
  retornado, próprio, ativo e principal em `pitgo/Core/Auth/Store/SessionStore.swift`
- [X] T005 [US1] Adaptar criação/seleção no `VehicleRepository` para validar o proprietário e a
  forma da resposta antes de retornar sucesso, sem serializar `userID`, em
  `pitgo/Core/Vehicle/Repository/VehicleRepository.swift` — `classify(_:)` reescrito para o
  allowlist exato de SQLSTATEs verificado no backend (T001); `userID` nunca fez parte de
  `CreateVehicleParams`/`SetPrimaryVehicleParams` (já vinha somente da sessão)
- [X] T006 [US1] Orquestrar submissão única, aplicação do principal autoritativo, resolução do
  onboarding somente após sucesso e estado terminal `.success` em
  `pitgo/Features/Garage/ViewModel/VehicleFormViewModel.swift`/`VehicleFormView.swift` — a projeção
  do principal (`applyAuthoritativePrimaryVehicle`) é aplicada pela View (`GarageView`/
  `OnboardingFlow`) a partir do `Vehicle` recebido em `onSaved`, não pelo ViewModel (que não deve
  depender de `SessionStore` — mesma fronteira MVVM das demais features)
- [X] T007 [US1] Atualizar a projeção central do principal após `set_primary_vehicle` e manter a
  lista da Garagem coerente com a linha retornada em
  `pitgo/Features/Garage/ViewModel/GarageViewModel.swift` (`confirmedPrimaryVehicle`, observado por
  `GarageView` para chamar `applyAuthoritativePrimaryVehicle`) — a lista em si já era recarregada
  integralmente do servidor após sucesso (`await load()`), a forma mais forte de "coerente com a
  linha retornada"
- [X] T008 [P] [US1] Separar "Cadastrar veículo" de "Agora não" — **já estava correto** em
  `VehicleOnboardingView.swift` (dois botões com closures distintas; não existe/não é necessário um
  `VehicleOnboardingViewModel` dedicado, a View já é stateless o suficiente). O bug real estava do
  outro lado do fluxo (T009)
- [X] T009 [US1] **Bug real corrigido nesta sessão**: `OnboardingFlow` (em
  `pitgo/Core/Navigation/PitGoRootView.swift`) tratava `onCancel` (voltar do formulário sem salvar)
  como equivalente a `onSkip`/sucesso — resolvia a pendência e ia para a Home mesmo sem nenhum
  veículo salvo, violando FR-026. Corrigido para `onCancel: { isRegisteringVehicle = false }` (volta
  ao convite, pendência intacta); `onSaved` agora também aplica o principal autoritativo à sessão.
  `isOnboardingPending` também passou a considerar `snapshot.primaryVehicle == nil` além da flag
  local, ignorando uma pendência legada quando o servidor já mostra um principal
- [ ] T010 [US1] Executar os cenários mínimos, segundo veículo, troca e concorrência de principal,
  onboarding→Home e Garagem→Garagem descritos em
  `specs/012-fix-vehicle-registration/quickstart.md` — **bloqueado neste ambiente**: exige
  interação manual em simulador/dispositivo com uma conta CLIENT real; apenas o build (T021) foi
  executado nesta sessão

**Checkpoint**: MVP — cadastro mínimo funcional com principal correto e navegação por origem
corrigida (o bug de onboarding resolvendo a pendência ao cancelar era o problema mais visível).

---

## Phase 4: User Story 2 - Corrigir dados inválidos no campo certo (Priority: P2)

**Independent Test**: Submeter combinações inválidas para cada campo validado e confirmar que todos
os problemas conhecidos aparecem junto ao campo correspondente, com o primeiro campo inválido
visível e focado.

### Implementation for User Story 2

- [X] T011 [US2] Mapear exclusivamente os SQLSTATEs allowlisted (`contracts/vehicle-rpcs.md`) para
  `.fieldFailure(field, error)` sem interpretar mensagens, `details` ou `hint` em
  `pitgo/Core/Vehicle/Repository/VehicleRepository.swift` — a versão anterior lia
  `message.contains("vehicles_plate_unique")` etc., o que o contrato proíbe; substituído por um
  `switch` fechado sobre `postgrestError.code`
- [X] T012 [US2] Revalidar somente campos que já possuem erro, manter/substituir o erro enquanto o
  novo valor continuar inválido, preservar erros alheios e repetir foco pelo `focusRequestID` em
  `pitgo/Features/Garage/ViewModel/VehicleFormViewModel.swift` (`isFieldValueValid(_:)`, novo) — uma
  falha de campo vinda do servidor também gera um novo `VehicleFocusRequest` e volta o formulário
  para `.editing` (antes ficava em `.failure` com um banner redundante além do erro do campo)
- [X] T013 [P] [US2] Adicionar mensagens específicas de Marca, Modelo, Placa, Renavam, Chassi, anos,
  Quilometragem e identificador duplicado — seguindo a convenção de auto-extração já usada no
  projeto (literais `LocalizedStringResource`), sem entradas manuais no Strings Catalog
- [X] T014 [US2] Renderizar mensagens por combinação campo/erro (`fieldErrorMessage(field:error:)`,
  tabela completa de `contracts/vehicle-form-ui.md`), adicionar `ScrollViewReader` + `@FocusState`
  (rola até o campo, aguarda 250ms, depois foca — evita disputa com o scroll do teclado) e
  `.accessibilityLabel` combinando rótulo+erro em
  `pitgo/Features/Garage/Views/VehicleFormView.swift` — "ações de teclado" (ex.: `.submitLabel`/
  `onSubmit` para avançar de campo em campo) e um "alvo único" dedicado para o `Toggle` de principal
  além do que o `Toggle` nativo já oferece não foram adicionados
- [ ] T015 [US2] Executar a matriz manual de erros simultâneos, formatos válidos, limites anuais,
  duplicidades, foco, Dynamic Type grande e VoiceOver descrita em
  `specs/012-fix-vehicle-registration/quickstart.md` — **bloqueado neste ambiente** (interação
  manual)

**Checkpoint**: erros de campo completos, específicos, navegáveis e persistentes até correção.

---

## Phase 5: User Story 3 - Receber falhas gerais sem indicação incorreta de campo (Priority: P3)

**Independent Test**: Simular sessão expirada, indisponibilidade da RPC, ausência de conexão,
demora excessiva e erro inesperado, verificando que o formulário é preservado e que a mensagem
orienta a ação adequada sem marcar campos.

### Implementation for User Story 3

- [X] T016 [US3] Classificar timeout, offline, sessão, `PGRST202`, `PGRST203`, `42883`, 5xx,
  contrato de resposta e desconhecido sem propagar/logar o `Error` bruto em
  `pitgo/Core/Vehicle/Repository/VehicleRepository.swift` — inclui um branch novo para `HTTPError`
  (`supabase-swift`, resposta não-JSON) mapeando 401/403→sessionExpired, 404→rpcUnavailable,
  5xx→serviceUnavailable, verificado contra o código-fonte real das duas funções nesta sessão (T001)
- [X] T017 [US3] Preservar o rascunho em falhas recuperáveis, bloquear `Task`s e resultados tardios
  e manter falhas gerais fora do mapa de campos em
  `pitgo/Features/Garage/ViewModel/VehicleFormViewModel.swift` — **parcial**: nenhuma falha geral
  já tocava `fieldErrors` (mantido); "limpar estado em perda/troca de sessão" depende de
  `onSessionExpired` (T018, adicionado) delegar ao `SessionStore.signOut()`, que desmonta a View
  inteira pelo gate central — não há uma limpeza adicional independente disso
- [X] T018 [P] [US3] Exibir a mensagem literal de RPC indisponível ("O cadastro de veículos está
  temporariamente indisponível. Tente novamente mais tarde."), feedback de salvamento e bloquear
  Voltar durante submissão sem marcar campos em
  `pitgo/Features/Garage/Views/VehicleFormView.swift` — botão Voltar já ficava `.disabled` durante
  `.isSubmitting` (pré-existente); adicionado `onSessionExpired` delegando ao gate central
  (`SessionStore.signOut()`, mesmo padrão de `ProviderRegistrationView`/`AppointmentTrackingView`)
- [ ] T019 [US3] Executar os cenários de falha geral, resposta perdida, toque duplicado,
  preservação do rascunho e ausência de detalhes técnicos descritos em
  `specs/012-fix-vehicle-registration/quickstart.md` — **bloqueado neste ambiente** (interação
  manual)

**Checkpoint**: falhas gerais nunca marcam campo válido e o rascunho sobrevive a falhas recuperáveis.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T020 Verificar (leitura) assinaturas, `SECURITY DEFINER`, `search_path`, ACLs, papel CLIENT,
  RLS, ownership e exatamente um principal — confirmado nesta sessão via `supabase db query
  --linked` (T001): `prosecdef=true`, `search_path=""`, EXECUTE só para `authenticated`/
  `service_role`/`postgres`, RLS habilitado em `vehicles`, `private.has_account_type('CLIENT')` e
  `profiles.active` checados no corpo de `create_vehicle`, lock por `auth.uid()`
  (`pg_advisory_xact_lock`) protegendo a unicidade do principal
- [X] T021 Executar `xcodebuild clean build` em simulador e `generic/platform=iOS` — ambos com
  **BUILD SUCCEEDED** nesta sessão, após todas as mudanças de T002-T018
- [X] T022 Revisar o diff para confirmar ausência de migration nova (nenhuma criada), `service_role`
  (não usado pelo client), `userID` no payload (`CreateVehicleParams`/`SetPrimaryVehicleParams`
  nunca tiveram esse campo), `Error` bruto (todo `catch` em `VehicleRepository.classify` produz
  somente `VehicleFormResult`) e valores completos de placa/Renavam/chassi em log (nenhum `print`/
  log adicionado)

---

## Dependencies & Execution Order

```text
Setup → Foundation → US1 (MVP) → US2 → US3 → Polish
```

### Parallel Opportunities

- Foundation: T002 e T003 em paralelo.
- US1: T004 e T008 podem avançar em paralelo ao núcleo (T005→T006→T007→T009).
- US2: T013 pode avançar em paralelo a T011/T012/T014.
- US3: T018 pode avançar em paralelo a T016/T017.

## Notes

- Nenhuma migration nova é criada — a restauração já existe e é compartilhada com o Android.
- Nenhuma dependência nova é adicionada.
- Nenhum teste automatizado é criado; build e `quickstart.md` são os gates de qualidade.
- Commits pequenos por tarefa/grupo lógico.
