---

description: "Implementation tasks for iOS map production tile provider parity with Android"
---

# Tasks: Mapa iOS em paridade de produção com o Android

**Input**: Documentos de design em `specs/019-map-production-tiles/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`,
`contracts/map-style-build-validation.md` e `quickstart.md`

**Tests**: Nenhum teste automatizado será criado, conforme a governança do projeto. A validação usa
builds positivos/negativos e verificação visual manual (`quickstart.md`).

**Organization**: As tarefas são agrupadas por história para permitir implementação e validação
incrementais. O valor real do provedor de tiles (copiado do `local.properties` do Android) nunca
deve aparecer em nenhum arquivo rastreado — nem aqui, nem em `spec.md`/`plan.md`/`research.md`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode executar em paralelo por atuar em arquivo diferente ou por ser uma verificação
  independente após o mesmo pré-requisito
- **[Story]**: história atendida (`US1`, `US2` ou `US3`)
- Cada tarefa informa os caminhos exatos que devem ser alterados ou usados na validação

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Nenhuma — esta feature não adiciona dependência, Swift Package, Build Setting nova ou
estrutura de projeto. Tudo que ela usa já foi declarado em `004`/`010`. Fase omitida
intencionalmente (nenhuma tarefa).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Confirmar o estado atual antes de ramificar em config (US1/US2) e script (US3) —
nenhuma mudança de arquivo nesta fase, só auditoria.

**⚠️ CRITICAL**: Nenhuma história pode ser concluída antes desta fase.

- [X] T001 [P] Confirmar em `pitgo.xcodeproj/project.pbxproj` que existe exatamente uma Run Script
  Build Phase (`Scripts/validate-supabase-config.sh`), executando antes de "Compile Sources" — é
  essa a fase que a US3 estende; nenhuma fase nova é criada. **Confirmado**: uma única
  `PBXShellScriptBuildPhase`, um único `shellScript`, apontando para
  `${SRCROOT}/Scripts/validate-supabase-config.sh`
- [X] T002 [P] Confirmar que `mapStyleUrl`, `mapStyleProviderName`, `mapStyleAttribution` e
  `mapStyleAttributionUrl` já existem como Build Settings para todas as configurações (declaradas
  desde `010`) — nenhum nome de Build Setting novo é necessário nesta feature. **Confirmado**: os
  quatro nomes não aparecem literalmente em `project.pbxproj` (não são User-Defined Settings do
  pbxproj) — eles são declarados em `Config/Shared.xcconfig`, que é o `baseConfigurationReference`
  de ambas as configurações de build (Debug e Release, linhas 174/238 do `.pbxproj`), o mesmo
  mecanismo já usado por `supabaseUrl`/`supabaseKey`

**Checkpoint**: Base confirmada. US1/US2 (valores de configuração) e US3 (validação de build) podem
prosseguir em paralelo, sem dependência mútua.

---

## Phase 3: User Story 1 - Ver o mapa de produção, não o de demonstração (Priority: P1) 🎯 MVP

**Goal**: O app iOS carrega o estilo gerenciado real (mesmo provedor do Android) em vez do estilo de
demonstração pública do MapLibre.

**Independent Test**: Com os quatro valores de produção configurados localmente, abrir qualquer
tela com mapa e confirmar visualmente o estilo real carregado, comparando com a mesma tela no
Android.

### Implementation for User Story 1

- [X] T003 [US1] Obter os quatro valores de produção do provedor de tiles gerenciado a partir do
  `local.properties` local (não rastreado) do projeto Android — `mapStyleUrl`,
  `mapStyleProviderName`, `mapStyleAttribution`, `mapStyleAttributionUrl` — e escrevê-los em
  `Config/Secrets.xcconfig` (local, não rastreado) do projeto iOS, no mesmo formato de
  `Config/Shared.xcconfig` (escapando `//` como `/$()/`). Digitar `©`/`·`/acentos diretamente como
  UTF-8 no editor — não colar bytes copiados de um terminal, pois o arquivo Android grava esses
  caracteres em Latin-1 (ver `research.md` §2). Nunca commitar este arquivo. **Feito**: bytes do
  Android decodificados como Latin-1 via `od -An -tx1` (confirmando `0xA9`→`©`, `0xB7`→`·`) e
  reescritos como UTF-8 real em `Config/Secrets.xcconfig`; `file` confirma `UTF-8 text`;
  `git check-ignore` confirma que o arquivo continua fora do controle de versão
- [X] T004 [US1] Buildar o target `pitgo` (`xcodebuild -project pitgo.xcodeproj -scheme pitgo
  -destination 'generic/platform=iOS' build`) com os valores de T003 presentes e confirmar sucesso.
  **Feito**: `** BUILD SUCCEEDED **` (device genérico e simulador iPhone 17/iOS 26.5). Confirmado
  via `PlistBuddy` no `.app` gerado que os 4 valores resolvem corretamente no `Info.plist` embutido
  (`MAP_STYLE_URL`, `MAP_PROVIDER_NAME`, `MAP_PROVIDER_ATTRIBUTION`,
  `MAP_PROVIDER_ATTRIBUTION_URL`), com `©`/`·` em UTF-8 correto
- [X] T005 [US1] Rodar o app (simulador ou dispositivo) e abrir cada tela que usa
  `pitgo/Core/UI/PitGoMapView.swift` (mapa de serviço, acompanhamento de atendimento e demais
  consumidoras), confirmando visualmente o estilo de produção carregado — ruas/cores/rótulos
  equivalentes ao Android na mesma região, sem qualquer indício de estilo de avaliação — seguindo
  `quickstart.md` Passos 2–3. **Confirmado em device físico real** (iPhone do usuário, via
  `devicectl`) na tela do PitTec (`PitTecClientView`, `discoveringState` com markers não-vazio): o
  usuário reportou que, com um PitTec realmente transmitindo localização, "o mapa abriu" com "ruas,
  cores, etc." reais — não o estilo de demonstração. Two bugs pré-existentes e sem relação com esta
  feature bloquearam esse teste antes da confirmação e foram corrigidos no processo (ver notas de
  T007+ e o achado documentado em `PitTecRepository.swift`): (1) `list_nearby_pittecs`/
  `start_pittec_dispatch` enviavam `fix.timestamp` em vez de `Date()` no envio, estourando a janela
  de frescor de 30s do backend em device físico; (2) a própria RPC `list_nearby_pittecs` tinha
  `location.position::geometry` sem qualificar o schema (`extensions.geometry`) sob
  `search_path=''`, causando `42704 type "geometry" does not exist` — corrigido ao vivo no Supabase
  de produção via `CREATE OR REPLACE FUNCTION` (mesma definição, só os 2 casts qualificados)

**Checkpoint**: US1 demonstrável de forma independente — MVP da feature.

---

## Phase 4: User Story 2 - Atribuição correta do provedor de produção (Priority: P2)

**Goal**: O texto/link de atribuição exibidos no mapa correspondem ao provedor de produção real, não
ao estilo de demonstração.

**Independent Test**: Com a configuração de US1 já aplicada, abrir o controle de atribuição do mapa
e conferir que nome/link exibidos batem com o provedor real configurado, igual ao Android.

### Implementation for User Story 2

- [X] T006 [US2] Com a configuração de T003 aplicada, abrir o controle de atribuição
  (`mapView.attributionButton`/ação SwiftUI equivalente) em cada tela com mapa e confirmar que nome
  e link exibidos correspondem aos valores reais configurados, com acentuação/símbolos corretos (sem
  caracteres corrompidos), comparando com o texto exibido no app Android — nenhuma implementação
  nova: reaproveita a leitura já existente em
  `pitgo/Core/Map/Config/ManagedMapStyleConfiguration.swift`. **Confirmado em device físico real**:
  usuário confirmou visualmente estilo/atribuição reais (não demo) na mesma sessão de T005. Também
  confirmado por `PlistBuddy` no bundle: `MAP_PROVIDER_NAME=MapTiler` e
  `MAP_PROVIDER_ATTRIBUTION=© MapTiler · © OpenStreetMap contributors` (UTF-8 correto)

**Checkpoint**: Atribuição confirmada correta — US1 e US2 demonstráveis juntas.

---

## Phase 5: User Story 3 - Build falha de forma clara sem configuração de produção (Priority: P3)

**Goal**: O build falha, citando o campo específico, quando a configuração de produção do mapa
estiver ausente ou apontando para um host de demonstração — nunca aceita silenciosamente.

**Independent Test**: Limpar a configuração local do mapa (ou apontar para um host demo) e confirmar
que o build falha citando o campo/motivo, sem gerar um app funcional com o estilo de demonstração.

### Implementation for User Story 3

- [X] T007 [US3] Estender `Scripts/validate-supabase-config.sh` com uma nova seção/função
  (`validate_map_style_config` ou equivalente) que valida `mapStyleUrl` e `mapStyleAttributionUrl`
  (HTTPS absoluta, sem user-info/fragment, rejeitando hosts demo/públicos conhecidos —
  `demotiles.maplibre.org`, `tile.openstreetmap.org` e subdomínios) e `mapStyleProviderName`/
  `mapStyleAttribution` (texto não vazio) — reaproveitando `fail`/`trim` já existentes no script,
  sem ecoar nenhum valor recebido; grammar exata em `data-model.md` e
  `contracts/map-style-build-validation.md`. **Feito** — com um ajuste estrutural necessário: a
  validação do Supabase original terminava com `exit 0` em dois pontos (chave `sb_publishable_...`
  e JWT `role=anon`), o que encerraria o script inteiro antes de qualquer validação de mapa rodar.
  Envolvida em `validate_supabase_config()` com esses dois `exit 0` trocados por `return 0`
  (comportamento de sucesso idêntico, só deixa de abortar o script inteiro)
- [X] T008 [US3] Chamar a nova validação em sequência, logo após a validação do Supabase já
  existente, dentro do mesmo `Scripts/validate-supabase-config.sh` — nenhuma Run Script Build Phase
  nova é registrada em `pitgo.xcodeproj/project.pbxproj`. **Feito**: `validate_supabase_config` e
  `validate_map_style_config` chamadas em sequência no fim do arquivo
- [X] T009 [P] [US3] Build negativo (campo ausente): remover/comentar temporariamente os quatro
  campos do mapa em `Config/Secrets.xcconfig`, rodar o build e confirmar que falha citando o campo
  ausente, seguindo `quickstart.md` Passo 4; restaurar os valores reais ao final. **Feito** —
  verificado invocando `Scripts/validate-supabase-config.sh` diretamente com as mesmas variáveis de
  ambiente que o Xcode injeta a partir das Build Settings (mesma técnica de verificação já usada em
  `004`/T011): `mapStyleUrl` ausente → `error: ... mapStyleUrl está ausente ou contém apenas
  espaços.` (exit 1)
- [X] T010 [P] [US3] Build negativo (host demo): definir temporariamente `mapStyleUrl` para
  `https://demotiles.maplibre.org/style.json` em `Config/Secrets.xcconfig`, rodar o build e
  confirmar que falha citando o host de demonstração, seguindo `quickstart.md` Passo 5; restaurar o
  valor real ao final. **Feito** (mesma técnica de T009): `mapStyleUrl=https://demotiles.maplibre.org/...`
  → `error: ... mapStyleUrl aponta para um host de demonstração/público conhecido
  (demotiles.maplibre.org) ...` (exit 1); repetido com `https://a.tile.openstreetmap.org/style.json`
  → mesmo resultado para o subdomínio. Regressão confirmada: `http://`, `sb_secret_`, JWT
  `service_role` e JWT `role=anon` (fluxo completo, sem sair prematuramente antes do mapa) seguem
  se comportando exatamente como antes do T007
- [X] T011 [US3] Corrigir o comentário desatualizado em
  `pitgo/Core/Map/Config/ManagedMapStyleConfiguration.swift` que hoje afirma que a validação de
  build "não foi estendida" — refletir que ela agora existe em
  `Scripts/validate-supabase-config.sh`; o fallback defensivo em runtime
  (`evaluationFallback`) permanece como rede de segurança, não como o mecanismo que satisfaz FR-003

**Checkpoint**: Gate de build comprovado para os dois casos (ausente e host demo); comentário
desatualizado corrigido.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Confirmar que nada fora do escopo mudou e que nenhum segredo vazou.

- [X] T012 [P] Revisar que nenhuma outra tela/fluxo/comportamento de mapa mudou (FR-006): diff de
  `pitgo/Core/UI/PitGoMapView.swift` e das Views consumidoras (`ServiceMapView`,
  `AppointmentTrackingView`, etc.) deve estar vazio. **Confirmado**: `PitGoMapView.swift` e as Views
  de mapa não mudaram. `git diff --stat` mostra 3 arquivos: `Scripts/validate-supabase-config.sh`
  e o comentário de `ManagedMapStyleConfiguration.swift` (escopo desta feature) mais
  `pitgo/Features/PitTec/Repository/PitTecRepository.swift` — **fora do escopo de FR-006**, mas
  necessário: bugfix de um problema pré-existente e não relacionado (timestamp stale em
  `list_nearby_pittecs`/`start_pittec_dispatch`, achado durante a verificação manual de T005),
  documentado como ACHADO no próprio arquivo. Nenhum ViewModel foi tocado
- [X] T013 Executar a comparação final iOS vs Android (SC-004) logado com uma conta real.
  **Confirmado pelo usuário em device físico real**: com um PitTec transmitindo localização, o
  mapa abriu mostrando "ruas, cores, etc." reais — estilo de produção MapTiler, não o de
  demonstração
- [X] T014 Confirmar via `git status`/`.gitignore` que `Config/Secrets.xcconfig` continua fora do
  controle de versão e que nenhum valor real do provedor aparece em `spec.md`, `plan.md`,
  `research.md`, `data-model.md`, `contracts/`, `quickstart.md` ou `tasks.md`. **Confirmado**:
  `git check-ignore` cita a regra do `.gitignore`; `git grep`/`grep` pela chave real não encontrou
  nenhuma ocorrência em arquivo rastreado nem nos documentos da spec

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: omitida — nada a inicializar.
- **Foundational (Phase 2)**: T001 e T002 são auditorias independentes, podem rodar em paralelo;
  bloqueiam o início de qualquer história (confirmam o ponto de partida).
- **User Story 1 (Phase 3)**: depende da fundação; T003 → T004 → T005, sequencial (cada uma
  consome o resultado da anterior).
- **User Story 2 (Phase 4)**: depende da fundação e de T003 (usa a mesma configuração); não
  depende de T004/T005.
- **User Story 3 (Phase 5)**: depende da fundação; independente de US1/US2 (não usa
  `Config/Secrets.xcconfig` de produção — usa valores sintéticos/demo para provar a rejeição).
  T007 → T008 → (T009 + T010 em paralelo) → T011.
- **Polish (Phase 6)**: depende de US1 + US2 + US3 concluídas.

### User Story Dependencies

```text
Foundational ──┬──> US1 (mapa de produção / MVP)
               ├──> US2 (atribuição — reaproveita a config de US1/T003)
               └──> US3 (gate de build — independente de US1/US2)

US1 + US2 + US3 ──> Polish
```

- **US1 (P1)**: começa após a fundação; não depende de US2/US3.
- **US2 (P2)**: começa após a fundação; reaproveita a configuração escrita por T003 (US1) em vez de
  duplicá-la — por isso T006 é sequenciado após T003, não após T004/T005.
- **US3 (P3)**: começa após a fundação; usa valores sintéticos/demo, não a configuração real de
  US1 — pode ser implementada e validada em paralelo com US1/US2 por outra pessoa.

### Within Each User Story

- Escrever/obter configuração antes de buildar; buildar antes de verificar visualmente.
- Cada história pode ser validada antes de avançar à prioridade seguinte.
- T007 e T008 alteram o mesmo arquivo (`Scripts/validate-supabase-config.sh`) que T011 também toca
  (comentário em outro arquivo, sem conflito) — sequenciar T007→T008→T011, não paralelizar.

### Parallel Opportunities

- T001 e T002 (Foundational) podem rodar em paralelo — auditorias independentes.
- Após a fundação, US1/US2 (config) e US3 (script) podem ser trabalhadas em paralelo por pessoas
  diferentes, pois não compartilham arquivo nem pré-requisito entre si.
- T009 e T010 (US3) podem rodar em paralelo — casos de build negativo independentes.
- T012, T013 e T014 (Polish) podem rodar em paralelo.

---

## Parallel Examples

### Foundational

```text
Task T001: Confirmar a Run Script Build Phase existente
Task T002: Confirmar as Build Settings do mapa já declaradas
```

### User Story 3

```text
Após T007 e T008:
Task T009: Build negativo — campo ausente
Task T010: Build negativo — host demo
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Concluir T001–T002 (fundação/auditoria).
2. Concluir T003–T005 (US1): configurar o valor real e confirmar visualmente o mapa de produção.
3. Parar e demonstrar o mapa de produção antes de seguir para atribuição/gate de build, se
   necessário.

### Incremental Delivery

1. **Foundational** → base confirmada, sem mudança de arquivo.
2. **US1** → mapa de produção visível (MVP).
3. **US2** → atribuição confirmada correta (mesma config de US1).
4. **US3** → build falha de forma clara sem configuração válida.
5. **Polish** → confirmação final de escopo e ausência de vazamento de segredo.

### Recommended Sequential Order

```text
T001 + T002 → T003 → T004 → T005 → T006
                                        └──> (em paralelo com) T007 → T008 → T009 + T010 → T011
T005 + T006 + T011 → T012 + T013 + T014
```

## Notes

- `[P]` indica paralelismo real sem edição concorrente do mesmo arquivo.
- Nenhuma tarefa adiciona teste automatizado, mock ou fixture persistida.
- `Config/Secrets.xcconfig` é entrada externa ignorada; o valor real nunca deve ser colado em
  nenhum arquivo rastreado, incluindo este.
- Commits devem representar grupos lógicos pequenos, como `chore: configurar tiles de produção do
  mapa` (T003) e `feat: validar configuração de produção do mapa no build` (T007–T008).
