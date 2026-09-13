---

description: "Implementation tasks for configuring Supabase on iOS"
---

# Tasks: Configurar Supabase (iOS)

**Input**: Documentos de design em `specs/004-configure-supabase/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`,
`contracts/supabase-configuration.md` e `quickstart.md`

**Tests**: Nenhum teste automatizado será criado. A validação usa builds positivos/negativos,
inspeção de segurança e regressão manual, conforme solicitado na especificação.

**Organization**: As tarefas são agrupadas por história para permitir implementação e validação
incrementais. Todas as fixtures usadas nos comandos devem ser sintéticas; valores reais nunca devem
aparecer em tarefas, argumentos, logs ou arquivos rastreados.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode executar em paralelo por atuar em arquivo diferente ou por ser uma validação
  independente após o mesmo pré-requisito
- **[Story]**: história atendida (`US1`, `US2` ou `US3`)
- Cada tarefa informa os caminhos exatos que devem ser alterados ou usados na validação

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Declarar os artefatos mínimos necessários sem instalar módulos funcionais do Supabase.

- [X] T001 Adicionar `supabase-swift` via Swift Package Manager ao target `pitgo`, produto `Supabase`
  apenas, sem `Auth`/`PostgREST`/`Storage`/`Realtime`/`Functions`, em `pitgo.xcodeproj`
- [X] T002 [P] Criar `pitgo/Config/Shared.xcconfig` com `#include? "Secrets.xcconfig"` e associar o
  arquivo às configurações Debug/Release do target em `pitgo.xcodeproj`
- [X] T003 [P] Adicionar `pitgo/Config/Secrets.xcconfig` ao `.gitignore` do projeto (não criar o
  arquivo em si, que é local/externo)

**Checkpoint**: Dependência declarada e mecanismo de `.xcconfig` pronto, sem valores ainda.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Preparar as User-Defined Build Settings, a validação de build e a fronteira comum de
configuração que bloqueiam todas as histórias.

**⚠️ CRITICAL**: Nenhuma história pode ser concluída antes desta fase.

- [X] T004 Declarar as User-Defined Build Settings `supabaseUrl` e `supabaseKey` (vazias por
  default) no target `pitgo`, para todas as configurações, em `pitgo.xcodeproj`
- [X] T005 Adicionado `SUPABASE_URL`/`SUPABASE_KEY` resolvendo `$(supabaseUrl)`/`$(supabaseKey)` —
  **adaptação de implementação**: em vez de um `pitgo/Info.plist` físico (o projeto usa
  `GENERATE_INFOPLIST_FILE = YES`, sem arquivo físico), as chaves foram adicionadas via
  `INFOPLIST_KEY_SUPABASE_URL`/`INFOPLIST_KEY_SUPABASE_KEY` nas Build Settings do target — mecanismo
  oficialmente documentado pela Apple para injetar chaves customizadas no Info.plist
  autogerado, com o mesmo resultado em runtime (`Bundle.main.object(forInfoDictionaryKey:)`), sem
  reintroduzir um arquivo físico que o template já não usa
- [X] T006 Implementar `pitgo/Scripts/validate-supabase-config.sh` com a leitura canônica
  case-sensitive de `${supabaseUrl}`/`${supabaseKey}`, `trim`, falha segura (código de saída
  diferente de zero) para valores ausentes/blank, sem ecoar o valor recebido em nenhuma mensagem
- [X] T007 Registrar `pitgo/Scripts/validate-supabase-config.sh` como Run Script Build Phase do
  target `pitgo`, posicionado antes de "Compile Sources", em `pitgo.xcodeproj`

**Checkpoint**: O projeto possui a dependência mínima e uma fronteira de configuração comum para
todas as variantes.

---

## Phase 3: User Story 1 - Disponibilizar a conexão configurada (Priority: P1) 🎯 MVP

**Goal**: Disponibilizar um único `SupabaseClient` pronto para reutilização interna, sem request,
plugin funcional ou alteração visual.

**Independent Test**: Com URL HTTPS e chave publishable sintéticas fornecidas externamente, o app
compila e abre; acessos repetidos ao provider usam a mesma instância e Welcome, Home e
RequestService permanecem inalteradas.

### Implementation for User Story 1

- [X] T008 [US1] Criar o `enum SupabaseClientProvider` com propriedade `static let client:
  SupabaseClient`, lida de `Bundle.main.object(forInfoDictionaryKey:)` e inicializada via
  `SupabaseClient(supabaseURL:supabaseKey:)`, sem plugins ou chamadas remotas, em
  `pitgo/Core/Network/SupabaseClientProvider.swift`
- [ ] T009 [US1] Executar o cenário positivo com inputs sintéticos, conferir compilação e
  identidade única do provider por inspeção, instalar o build e percorrer Welcome → Home →
  RequestService sem regressão, seguindo `specs/004-configure-supabase/quickstart.md` —
  **parcialmente bloqueado neste ambiente**: `xcodebuild ... clean build` completo exige
  simulador/dispositivo iniciado (só o runtime iOS 26.2 Simulator está baixado, mas o Xcode 26.5
  instalado resolve SDKROOT 26.5 — mesma causa registrada em `001`/T019). **Verificação alternativa
  executada com sucesso**: `xcodebuild -resolvePackageDependencies` resolveu `supabase-swift`
  2.55.2 e seu grafo de dependências a partir do `pitgo.xcodeproj` real; separadamente, um pacote
  SwiftPM standalone com Swift 6 escopado ao próprio alvo (`swiftLanguageMode(.v6)`, sem forçar o
  modo nas dependências) compilou o código exato de `SupabaseClientProvider.swift` sem erros contra
  o pacote real resolvido — confirma `SupabaseClient(supabaseURL:supabaseKey:)` como assinatura
  real (não documentação/suposição). Identidade única por inspeção: `static let` confirmado.
  Regressão visual Welcome/Home/RequestService inalterada por inspeção de código (nenhum arquivo
  dessas features foi tocado por esta feature).

**Checkpoint**: A conexão central está configurada e pode ser demonstrada independentemente como o
MVP da feature.

---

## Phase 4: User Story 2 - Detectar configuração ausente ou inválida (Priority: P2)

**Goal**: Interromper qualquer build antes do artefato quando URL ou chave não forem apropriadas,
com diagnóstico acionável que não revele valores.

**Independent Test**: Ausência, blank, URL sem HTTPS/host ou com user-info, chave secret,
service-role, JWT malformado e formato desconhecido falham em simulador e destino
`generic/platform=iOS`; publishable e JWT legado com `role=anon` passam sem acesso à rede.

### Implementation for User Story 2

- [X] T010 [US2] Estender `pitgo/Scripts/validate-supabase-config.sh` com validação de URI HTTPS
  absoluta sem user-info e allowlist de chave publishable/JWT legado `role=anon` (decodificação
  local do payload via `base64`, sem verificar assinatura), rejeitando secret, service-role, roles
  duplicados e formatos inválidos sem ecoar entrada ou payload
- [X] T011 [US2] Executada a matriz negativa (10 casos: URL ausente, sem scheme, `http://`,
  user-info, sem host, `sb_secret_`, JWT `service_role`, formato desconhecido, além de 2 casos
  positivos — `sb_publishable_...` e JWT `role=anon` sintético gerado localmente) invocando
  `Scripts/validate-supabase-config.sh` diretamente com `supabaseUrl`/`supabaseKey` como variáveis
  de ambiente (mesma forma que o Xcode expõe Build Settings a um Run Script Phase) — todos os 12
  resultados bateram exatamente com `contracts/supabase-configuration.md`, sem ecoar nenhum valor.
  **Execução via `xcodebuild` real em simulador/`generic/platform=iOS` continua bloqueada** pela
  mesma causa de T009 (Simulator iOS 26.5 não baixado neste ambiente).

**Checkpoint**: Configurações ausentes, inválidas ou elevadas são recusadas de forma explícita em
todas as variantes.

---

## Phase 5: User Story 3 - Preservar credenciais e ambientes (Priority: P3)

**Goal**: Suportar o mesmo contrato em ambiente local e CI, com precedência determinística e zero
credencial real em arquivos rastreados ou diagnósticos.

**Independent Test**: Override de linha de comando/CI vence `Config/Secrets.xcconfig`, uma fonte
superior blank falha sem fallback, espaços externos são removidos e a busca pela chave real não
encontra arquivos rastreados nem saída de erro.

### Implementation for User Story 3

- [ ] T012 [US3] Documentar e validar o fluxo de override via `xcodebuild -xcconfig <arquivo
  gerado>` para CI, preservando a precedência sobre `Config/Secrets.xcconfig` inclusive quando o
  override estiver blank, em `specs/004-configure-supabase/quickstart.md` — a documentação já
  existia em `quickstart.md` (seção "Configure local values"); **a validação real de precedência via
  `xcodebuild -xcconfig` continua bloqueada neste ambiente** (mesma causa de T009) — resolução de
  precedência entre fontes é uma etapa do próprio `xcodebuild`, não replicável só invocando o script
  de validação isoladamente.
- [ ] T013 [P] [US3] Validar com fixtures sintéticas as fontes local (`Config/Secrets.xcconfig`) e
  de override de CI, a precedência, o caso blank superior e o `trim`, seguindo
  `specs/004-configure-supabase/quickstart.md` — **parcialmente verificado**: `trim` de espaços
  externos confirmado diretamente no script (caso "padded valid" em T011, build aceito preservando
  o conteúdo interno); precedência real entre fontes permanece bloqueada, mesma causa de T012.
- [X] T014 [P] [US3] Inspecionar Git e saídas de falha sem imprimir credenciais, confirmando que
  `pitgo/Config/Secrets.xcconfig` continua ignorado/não rastreado e que nenhuma chave real foi
  adicionada, conforme `specs/004-configure-supabase/quickstart.md` e `.gitignore`

**Checkpoint**: Configuração local e automatizada funciona sem alteração de código e sem vazamento
de credencial real.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Confirmar o escopo mínimo, compatibilidade e ausência de regressões ao juntar as três
histórias.

- [X] T015 [P] Revisar o projeto e o código para confirmar somente o pacote central `supabase-swift`,
  o Run Script Build Phase e o provider compartilhado, sem módulos funcionais, Repository, DI,
  logging ou health check, em `pitgo.xcodeproj`, `pitgo/Scripts/validate-supabase-config.sh` e
  `pitgo/Core/Network/SupabaseClientProvider.swift`
- [ ] T016 **bloqueado neste ambiente** (mesma causa de T009). Executar `xcodebuild clean build` em simulador e `generic/platform=iOS` com configuração
  externa válida, repetir a abertura offline e a regressão dos fluxos existentes e finalizar com
  inspeção do diff conforme `specs/004-configure-supabase/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: começa imediatamente; T001, T002 e T003 podem ocorrer em paralelo.
- **Foundational (Phase 2)**: T004 depende de T001–T003; T005 depende de T004; T006 é independente
  de T004/T005; T007 depende de T006. Toda a fase bloqueia as histórias.
- **User Story 1 (Phase 3)**: depende da fase foundational.
- **User Story 2 (Phase 4)**: depende da fase foundational; não depende do provider de US1.
- **User Story 3 (Phase 5)**: depende da fase foundational; T013 e T014 podem executar em paralelo
  depois de T012.
- **Polish (Phase 6)**: depende de todas as histórias incluídas na entrega.

### User Story Dependencies

```text
Setup ──> Foundational ──┬──> US1 (cliente compartilhado / MVP)
                        ├──> US2 (validação estrita)
                        └──> US3 (fontes e proteção)

US1 + US2 + US3 ──> Polish
```

- **US1 (P1)**: começa após a fundação e não depende de US2/US3 para seu cenário positivo.
- **US2 (P2)**: começa após a fundação e é verificável com a matriz de configuração; não usa US1.
- **US3 (P3)**: começa após a fundação e é verificável pelas fontes/inspeção; não usa o provider de
  US1. T010 e T012 alteram/documentam o mesmo script/quickstart, portanto devem ser sequenciadas ou
  coordenadas apesar de as histórias serem conceitualmente independentes.

### Within Each User Story

- Implementação precede sua validação manual.
- A validação usa somente fixtures sintéticas ou valores fornecidos externamente.
- Nenhum artefato deve prosseguir após falha de configuração.
- A história pode ser validada antes de avançar à prioridade seguinte.

### Parallel Opportunities

- T001, T002 e T003 atuam em arquivos/configurações diferentes e podem executar em paralelo.
- Após T012, T013 e T014 são verificações independentes e podem executar em paralelo.
- T015 pode ocorrer em paralelo com preparativos externos para T016.
- US1, US2 e US3 têm fronteiras próprias após a fundação, mas alterações simultâneas no mesmo script
  de validação devem ser evitadas.

---

## Parallel Examples

### Setup

```text
Task T001: Adicionar supabase-swift via SPM
Task T002: Criar Config/Shared.xcconfig
Task T003: Adicionar Config/Secrets.xcconfig ao .gitignore
```

### User Story 1

```text
T008 cria o provider; T009 começa somente quando o provider e as chaves de Info.plist compilarem.
Não há paralelismo seguro dentro desta história.
```

### User Story 2

```text
T010 implementa a validação; T011 executa a matriz somente após T010.
Não há paralelismo seguro dentro desta história.
```

### User Story 3

```text
Após T012:
Task T013: Validar fontes, precedência e normalização
Task T014: Inspecionar rastreamento e vazamentos
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Concluir T001–T007 para preparar a fundação.
2. Concluir T008 para disponibilizar o cliente compartilhado.
3. Executar T009 e confirmar o cenário positivo sem mudança visual ou request.
4. Parar e demonstrar o cliente central antes das regras adicionais, se necessário.

### Incremental Delivery

1. **Setup + Foundational** → dependência mínima e fronteira de configuração gerada.
2. **US1** → cliente compartilhado pronto (MVP).
3. **US2** → configuração inválida/elevada bloqueada em todas as variantes.
4. **US3** → local e CI com precedência segura e inspeção de vazamento.
5. **Polish** → build/regressão final do conjunto.

### Recommended Sequential Order

```text
T001 + T002 + T003 → T004 → T005 → T006 → T007 → T008 → T009 → T010 → T011 → T012
                                                                                └───> T013 + T014
T013 + T014 → T015 + T016
```

## Notes

- `[P]` indica paralelismo real sem edição concorrente do mesmo arquivo.
- Nenhum task adiciona testes, fixtures persistidas ou credenciais reais.
- `Config/Secrets.xcconfig` é entrada externa ignorada; não deve ser criado com valores sintéticos
  ou reais como mudança rastreada.
- Commits devem representar grupos lógicos pequenos, como `chore: add Supabase build setup` e
  `feat: expose shared Supabase client`.
