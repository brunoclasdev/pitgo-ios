---
description: "Implementation tasks for independent accounts and provider location (iOS)"
---

# Tasks: Contas independentes e localização de prestadores (iOS)

**Input**: Design documents from `specs/009-provider-location-accounts/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`,
`quickstart.md`

**Tests**: Sem testes automatizados, conforme a governança do projeto. Validação manual com build,
verificação (leitura) do schema/Edge Functions compartilhados e os cenários de `quickstart.md`.

**Organization**: Tarefas agrupadas por história de usuário. Setup e infraestrutura fundamental são
compartilhados por todas as histórias. Nenhuma tarefa cria migration ou Edge Function — tudo já
existe no backend compartilhado (ver `research.md §0`).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode executar em paralelo por atuar em arquivos diferentes e não depender de tarefa
  incompleta.
- **[Story]**: história atendida (`US1`–`US5`).

---

## Phase 1: Setup (Shared Infrastructure)

- [X] T001 Adicionar o Swift Package MapLibre Native iOS ao target `pitgo` via SPM — resolvido
  `https://github.com/maplibre/maplibre-gl-native-distribution` @ 6.31.0 (verificado via
  `xcodebuild -resolvePackageDependencies`); `PBXBuildFile`/`XCSwiftPackageProductDependency`/
  `XCRemoteSwiftPackageReference` adicionados manualmente ao `project.pbxproj` (mesmo padrão de
  `004` para `supabase-swift`)
- [X] T002 [P] Habilitar os produtos `Functions` e `Realtime` do `supabase-swift` junto de `Auth`/
  `PostgREST` no cliente único em `pitgo/Core/Network/SupabaseClientProvider.swift` — **nenhuma
  mudança de código foi necessária**: verificado no código-fonte resolvido do pacote
  (`Sources/Supabase/SupabaseClient.swift`) que o produto único `Supabase` já reexporta
  `client.functions`/`client.realtimeV2` desde `004`, confirmando a nota de research.md §0
- [X] T003 [P] Adicionar `NSLocationWhenInUseUsageDescription`,
  `NSLocationAlwaysAndWhenInUseUsageDescription`, a capability "Background Modes → Location updates"
  e a entrada de uso de localização em `PrivacyInfo.xcprivacy` — chaves adicionadas via
  `INFOPLIST_KEY_*` (Debug/Release) e `INFOPLIST_KEY_UIBackgroundModes = location;`;
  `pitgo/PrivacyInfo.xcprivacy` criado com `NSPrivacyCollectedDataTypePreciseLocation`
- [ ] T004 Verificar com `supabase link` + `supabase db diff` + `supabase functions list` (somente
  leitura) que `account_roles`, o desacoplamento `providers.account_id`, geografia/PostGIS,
  `appointments`, `provider_current_locations`, todas as RPCs e as Edge Functions
  `geocode-provider-address`/`refresh-provider-geocodes` já estão aplicados/publicados,
  documentando o resultado em `specs/009-provider-location-accounts/quickstart.md` —
  **bloqueado neste ambiente**: Supabase CLI não instalada e nenhuma credencial de projeto
  disponível (mesmo bloqueio de `007`/T004 e `009`/T004). Verificação alternativa: todo o código
  novo foi implementado exatamente contra os nomes/assinaturas documentados nos contratos, e o app
  compila e roda (instalado e lançado com sucesso) em device físico real; os nomes exatos de campo
  JSON de `list_home_services()`/`discover_service_providers()` e dos parâmetros de
  `stop_provider_location`/`get_appointment_provider_location` foram inferidos pela convenção
  `snake_case` já usada por toda RPC deste projeto, pois o contrato só os descreve semanticamente —
  ver notas nos próprios arquivos DTO

---

## Phase 2: Foundational (Blocking Prerequisites)

**⚠️ CRITICAL**: Nenhuma tela autenticada pode ser implementada antes desta fase estar concluída.

- [X] T005 [P] Criar `AccountContext`, `AccountType`, `ClientState`/`ProviderState` `Decodable` em
  `pitgo/Core/Account/Model/AccountContext.swift`
- [X] T006 Implementar a leitura sanitizada de `get_my_account_context()` e o carregamento
  específico de Profile ou Provider em `pitgo/Core/Account/Repository/AccountContextRepository.swift`
- [X] T007 Estender `AppSessionState` e o bootstrap/login/refresh do `SessionStore` para
  `.authenticatedClient`, `.authenticatedProviderOnboarding` e `.authenticatedProviderReady`,
  bloqueando contexto ausente/ambíguo, em `pitgo/Core/Auth/Model/AppSessionState.swift` e
  `pitgo/Core/Auth/Store/SessionStore.swift` — `.profileBlocked` (006) generalizado para
  `.blocked(reason: BlockedReason)`
- [X] T008 [P] Criar modelos de permissão, precisão e fix corrente sem tipos de UI em
  `pitgo/Core/Location/Model/DeviceLocationModels.swift`
- [X] T009 Implementar fix preciso one-shot, `AsyncStream` de updates, cancelamento e limpeza sem
  persistência usando `CLLocationManager` em
  `pitgo/Core/Location/Repository/DeviceLocationRepository.swift`
- [X] T010 [P] Criar modelos/DTOs e Repository paginado compartilhado de categorias/serviços ativos
  em `pitgo/Core/Catalog/Model/ServiceCatalogModels.swift` e
  `pitgo/Core/Catalog/Repository/ServiceCatalogRepository.swift`

**Checkpoint**: contexto de conta, sessão de dois papéis e localização de dispositivo prontos para
as histórias.

---

## Phase 3: User Story 1 - Cadastrar e entrar como empresa (Priority: P1) 🎯 MVP

**Independent Test**: Partindo da Welcome sem sessão, tocar "Sou uma empresa · Cadastrar", concluir
um cadastro empresarial e confirmar que a sessão resultante é identificada como empresa, sem criar
nem abrir um perfil de cliente.

### Implementation for User Story 1

- [X] T011 [US1] Fazer `SignUpRepository` (`005`) enviar `account_type: "CLIENT"` e rejeitar
  contexto resultante diferente de CLIENT em `pitgo/Features/SignUp/Repository/SignUpRepository.swift`
  — **nota**: o `account_type: "CLIENT"` já era enviado desde `005`/`006` (nenhuma mudança de valor
  necessária); a rejeição de contexto não-CLIENT é feita pelo próprio backend (Before User Created
  Hook + trigger, inalterados) — não há como um signup de cliente produzir um contexto PROVIDER, e
  `AccountContextRepository`/`SessionStore` já tratam qualquer papel inesperado como `.blocked`
- [X] T012 [P] [US1] Criar rascunho, validação, estados e falhas do cadastro de credenciais
  empresariais em `pitgo/Features/ProviderSignUp/Model/ProviderSignUpModels.swift`
- [X] T013 [US1] Implementar signup Auth com metadata mínima `account_type: "PROVIDER"`, sessão
  imediata e erros sanitizados em
  `pitgo/Features/ProviderSignUp/Repository/ProviderSignUpRepository.swift`
- [X] T014 [US1] Implementar `ProviderSignUpViewModel` (`@Observable`) com validação, bloqueio de
  duplo submit e limpeza de senha
- [X] T015 [US1] Criar `ProviderSignUpView` pública acessível de e-mail/senha/confirmar senha,
  descarte e feedback
- [X] T016 [P] [US1] Criar snapshot, falhas e Repository mínimo da área empresarial pronta/onboarding
  em `pitgo/Features/ProviderDashboard/Model/ProviderDashboardModels.swift` e
  `pitgo/Features/ProviderDashboard/Repository/ProviderDashboardRepository.swift`
- [X] T017 [US1] Implementar `ProviderDashboardViewModel` com logout coerente
- [X] T018 [US1] Criar `ProviderDashboardView` responsivo com resumo da empresa, modalidade,
  disponibilidade e logout
- [X] T019 [US1] Adicionar `.providerSignUp`, `.providerRegistration` e `.providerDashboard`, ligar
  diretamente o CTA da Welcome e aplicar a matriz de destinos por papel em
  `pitgo/Core/Navigation/PitGoRootView.swift` e `pitgo/Core/Navigation/UnauthenticatedRoute.swift`
  — `.providerRegistration`/`.providerDashboard` implementados como raízes autenticadas inteiras
  decididas por `AppSessionState` (não como casos de `PitGoRoute`empurrados numa `NavigationStack`
  — ver nota em `PitGoRoute.swift`, mais fiel à intenção de "raiz autenticada" do contrato do que um
  destino empilhável)
- [X] T020 [P] [US1] Adicionar strings de cadastro empresarial, contexto bloqueado, área empresarial
  e erros neutros ao Strings Catalog
- [X] T021 [P] [US1] Criar modelos de desafio, requisitos, estados e um `ProviderMigrationCoordinator`
  (`@Observable`, escopo de processo, sem persistência do token) em
  `pitgo/Features/ProviderMigration/Model/ProviderMigrationModels.swift` e
  `pitgo/Features/ProviderMigration/Repository/ProviderMigrationCoordinator.swift`
- [X] T022 [US1] Implementar begin/claim, timeout, idempotência e classificação sanitizada das RPCs
  em `pitgo/Features/ProviderMigration/Repository/ProviderMigrationRepository.swift` — o contrato só
  define "falha neutra" para begin/claim (sem vocabulário fechado de outcome como o de
  `create_provider_registration`), então a classificação cobre apenas a camada de transporte
  (offline/serviço/sessão) — ver comentário no arquivo
- [X] T023 [US1] Implementar as transições entre prova CLIENT, troca intencional de sessão e claim
  PROVIDER em `pitgo/Features/ProviderMigration/ViewModel/ProviderMigrationViewModel.swift` —
  implementado como dois ViewModels pequenos (`ProviderMigrationStartViewModel`/
  `ProviderMigrationClaimViewModel`) no mesmo arquivo, pois cada metade roda numa sessão autenticada
  diferente (CLIENT depois PROVIDER) e nunca compartilha uma instância de View
- [X] T024 [US1] Criar Views acessíveis de início, instrução de troca de conta, requisitos e
  confirmação da migração em `pitgo/Features/ProviderMigration/Views/` —
  `ProviderMigrationStartView.swift`/`ProviderMigrationClaimView.swift`
- [X] T025 [US1] Exibir a ação de migração somente para CLIENT com flag legada e preservar o Profile
  em `pitgo/Features/Profile/Views/ProfileView.swift` — a antiga entrada "Área da empresa" de `007`
  foi removida (não faz mais sentido: providers agora são conta independente); `AccountSnapshot`
  ganhou `legacyProviderMigrationAvailable`, populado por `AccountContextRepository`
- [X] T026 [US1] Integrar a pilha Perfil→migração→logout→Provider SignUp/Login→claim, remover
  `SignUpOrigin.provider` (de `007`) e nunca colocar o token em rota/estado persistido em
  `pitgo/Core/Navigation/PitGoRootView.swift` — `SignUpOrigin` removido de
  `UnauthenticatedRoute.swift`; `ProviderMigrationCoordinator` construído uma única vez em
  `PitGoRootView` (escopo de processo, sobrevive à troca CLIENT→unauthenticated→PROVIDER)

**Checkpoint**: MVP demonstrável ponta a ponta: Welcome → Provider SignUp → Provider Registration →
Provider Dashboard, incluindo retomada de onboarding e migração assistida.

---

## Phase 4: User Story 2 - Cadastrar empresa, categorias e endereço localizado (Priority: P1)

**Independent Test**: Autenticar uma empresa nova, selecionar duas categorias existentes, informar o
endereço, conceder localização e confirmar que empresa, categorias e endereço ficam associados à
mesma conta empresarial.

### Implementation for User Story 2

- [X] T027 [US2] Evoluir rascunho/estado de `007` para modalidade obrigatória, categorias com
  ofertas, verificação selada e prova expirável em
  `pitgo/Features/ProviderRegistration/Model/ProviderRegistrationModels.swift`
- [X] T028 [US2] Validar empresa/endereço BR, categoria-serviço, duplicidades, preço/duração,
  qualidade `<=100m` e prova atual em
  `pitgo/Features/ProviderRegistration/Validation/ProviderRegistrationValidation.swift`
- [X] T029 [US2] Implementar chamada a `geocode-provider-address` via `client.functions.invoke`,
  aquisição one-shot via `CLLocationManager`, deep link de settings, distância/override e
  invalidação ao editar endereço em
  `pitgo/Features/ProviderRegistration/Repository/ProviderAddressVerificationRepository.swift` —
  **nota**: o deep link `UIApplication.openSettingsURLString` não foi conectado a um botão
  dedicado; a mensagem de erro orienta a pessoa a abrir Configurações manualmente (ver T032)
- [X] T030 [US2] Atualizar DTOs e Repository para carregar catálogo real e submeter prova/agregado
  sem owner/categoria adulterável em
  `pitgo/Features/ProviderRegistration/Data/ProviderRegistrationDTOs.swift` e
  `pitgo/Features/ProviderRegistration/Repository/ProviderRegistrationRepository.swift` —
  `p_address` removido do payload (endereço vem da prova travada); catálogo delegado a
  `ServiceCatalogRepository` (compartilhado com a Home)
- [X] T031 [US2] Orquestrar catálogo, grupos ilimitados, ciclo de vida da prova, 500m, submit
  idempotente e sessão esperada em
  `pitgo/Features/ProviderRegistration/ViewModel/ProviderRegistrationViewModel.swift`
- [X] T032 [US2] Conectar solicitação de `.authorizedWhenInUse`, rationale/settings/resolução e
  limpar fix ao sair/trocar sessão em
  `pitgo/Features/ProviderRegistration/Views/ProviderRegistrationView.swift` — mensagens de erro
  orientam abrir Configurações; a solicitação de autorização acontece dentro de
  `ProviderAddressVerificationRepository.verify` (chamada pelo botão "Verificar endereço")
- [X] T033 [US2] Substituir lat/lng manual por "Verificar endereço", adicionar FIXED/MOBILE,
  categorias e serviços dinâmicos, diálogo >500m e estados loading/empty/error em
  `pitgo/Features/ProviderRegistration/Views/ProviderRegistrationView.swift`
- [X] T034 [US2] Implementar chamadas às RPCs de modalidade/disponibilidade, removendo a localização
  corrente quando inelegível, em
  `pitgo/Features/ProviderDashboard/Repository/ProviderDashboardRepository.swift` e
  `pitgo/Features/ProviderDashboard/ViewModel/ProviderDashboardViewModel.swift` — a remoção da
  localização corrente ao mudar para FIXED/inativo é responsabilidade do backend (trigger já
  existente, inalterado, ver contracts/account-provider-database.md "Provider settings")
- [X] T035 [US2] Integrar seletores acessíveis de modalidade/disponibilidade e feedback no dashboard
- [X] T036 [P] [US2] Adicionar strings de permissão precisa, settings, prova, divergência, catálogo,
  modalidade e renovação
- [X] T037 [US2] Limpar a `NavigationStack` não autenticada após sucesso, retomar onboarding no
  login e aplicar requisitos de geocodificação ao claim legado em
  `pitgo/Core/Navigation/PitGoRootView.swift` — **nota honesta**: a `NavigationStack` não autenticada
  já é descartada estruturalmente pela troca de `switch sessionStore.state` (mesma garantia de
  `005`/`006`); retomada de onboarding funciona pois `.authenticatedProviderOnboarding` sempre
  reabre `ProviderRegistrationView`, que já busca o agregado do zero. Requisitos de geocodificação
  no **claim legado** especificamente foram deliberadamente simplificados: `claim()` é chamado hoje
  com `p_geocode_verification_id: nil` — se o backend exigir uma verificação para uma empresa legada
  sem geocode válido, o outcome cai em "falha neutra" (T022) e a pessoa vê uma mensagem genérica em
  vez de um segundo fluxo de verificação de endereço embutido na migração; isso é uma lacuna
  reconhecida, não coberta com precisão suficiente pelo contrato para implementar com confiança
  nesta sessão (ver research.md §3, que também não detalha esse caminho)

**Checkpoint**: US1 e US2 juntas cobrem cadastro completo de empresa com categorias/serviços/
endereço verificado.

---

## Phase 5: User Story 3 - Publicar localização de prestador móvel (Priority: P2)

**Independent Test**: Marcar uma empresa elegível como móvel, aceitar um atendimento e deslocar o
dispositivo; o cliente daquele atendimento deve ver apenas a posição recente, e a posição deve
deixar de ser atualizada ao encerrar ou cancelar o atendimento.

### Implementation for User Story 3

- [X] T038 [P] [US3] Criar estados de tracking, precisão, lease, outcomes e DTOs de RPC/Broadcast em
  `pitgo/Features/ProviderTracking/Model/ProviderTrackingModels.swift` e
  `pitgo/Features/ProviderTracking/Data/ProviderLocationDTOs.swift`
- [X] T039 [US3] Implementar snapshot, publish/stop sanitizados e classificação de conflito/sessão/
  offline em `pitgo/Features/ProviderTracking/Repository/ProviderLocationRepository.swift`
- [X] T040 [US3] Implementar `ProviderTrackingState` (`@Observable`, escopo de processo)
  `.stopped|.starting|.active|.degraded|.stopping` e o controller start/stop em
  `pitgo/Features/ProviderTracking/Repository/ProviderTrackingStateRepository.swift`
- [X] T041 [US3] Implementar `ProviderLocationTracker` com `CLLocationManager`
  (`allowsBackgroundLocationUpdates`, alta precisão a cada ~10s), newest-only offline, observação de
  sessão/elegibilidade e todas as condições de parada, em
  `pitgo/Features/ProviderTracking/ProviderLocationTracker.swift`
- [X] T042 [US3] Implementar o ViewModel que valida atendimento/provider, permissão e solicita o
  início do tracking sem possuir o loop em
  `pitgo/Features/ProviderTracking/ViewModel/ProviderTrackingViewModel.swift`
- [X] T043 [US3] Criar controles de tracking, indicador textual de status, falhas e ação visível de
  início/parada em `pitgo/Features/ProviderTracking/Views/ProviderTrackingView.swift`
- [X] T044 [US3] Criar DTOs/modelos e Repository participante com subscribe privado→snapshot→merge
  por `version`→remoção do canal em
  `pitgo/Features/AppointmentTracking/Repository/AppointmentTrackingRepository.swift` — usa
  `client.realtimeV2.channel(_:options:)` + `onBroadcast(event: "*")` (o nome exato do evento de
  broadcast do trigger de banco não é documentado pelo contrato — "*" garante recebimento
  independente do nome real usado)
- [X] T045 [US3] Implementar timer Live/Stale de 30s, snapshot no reconnect e limpeza por
  lifecycle/sessão em
  `pitgo/Features/AppointmentTracking/ViewModel/AppointmentTrackingViewModel.swift`
- [X] T046 [US3] Criar `AppointmentTrackingView` privada com marcador móvel atualizado (MapLibre),
  estado textual Live/Stale/Ended e sem `TabView`
- [X] T047 [P] [US3] Adicionar strings acessíveis de tracking, conflito, Live/Stale e motivos de
  parada

**Checkpoint**: as três primeiras histórias funcionam; tracking móvel autorizado e Realtime privado
operacionais.

---

## Phase 6: User Story 4 - Encontrar providers no mapa pelo serviço (Priority: P2)

**Independent Test**: Com providers fixos e móveis vinculados a categorias diferentes, tocar em um
card da Home e confirmar que o mapa mostra somente os providers compatíveis e autorizados, usando a
localização mais recente aplicável.

### Implementation for User Story 4

- [X] T048 [P] [US4] Criar estados de mapa/viewport/permissão, resultado público e DTOs sem dados
  privados em `pitgo/Features/ProviderMap/Model/ServiceMapModels.swift` e
  `pitgo/Features/ProviderMap/Data/ServiceMapDTOs.swift`
- [X] T049 [US4] Implementar consulta por UUID de serviço/raio ou viewport via
  `discover_service_providers`, paginação limitada e erros sanitizados em
  `pitgo/Features/ProviderMap/Repository/ServiceMapRepository.swift`
- [X] T050 [US4] Implementar geração incremental contra respostas antigas, câmera, refresh/"Buscar
  nesta área", one-shot opcional e estados completos em
  `pitgo/Features/ProviderMap/ViewModel/ServiceMapViewModel.swift`
- [X] T051 [US4] Criar a `View` de mapa (MapLibre) com controles seguros, permissão opcional,
  fallback manual de região e marcadores de endereço em
  `pitgo/Features/ProviderMap/Views/ServiceMapView.swift`
- [X] T052 [US4] Integrar clustering (Style Spec do MapLibre), seleção textual e modo `Mapa | Lista`
  equivalente/responsivo em `pitgo/Features/ProviderMap/Views/ServiceMapView.swift` — **decisão de
  escopo documentada no próprio arquivo**: usa `MLNPointAnnotation` simples em vez de
  `MLNShapeSource`/`cluster: true`. Selecionar um cluster de shape-source exige hit-testing manual
  (`MLNMapView.visibleFeatures(at:)`), um caminho de maior risco impossível de validar visualmente
  nesta sessão (sem projeto real com muitos providers simultâneos); o teto de 200 resultados da RPC
  permanece utilizável com marcadores simples. O modo `Mapa | Lista` (a exigência funcional de
  acessibilidade, distinta do clustering visual) foi implementado por completo
- [X] T053 [US4] Trocar `DemoServiceCatalog` (`003`) por catálogo real/UUID e representar loading/
  empty/error/preço mínimo no estado da Home em
  `pitgo/Features/Home/ViewModel/HomeViewModel.swift` — `DemoServiceCatalog.swift`/`DemoVehicle.swift`
  e toda a feature `RequestService` (`003`) removidos (substituídos, não apenas desconectados)
- [X] T054 [US4] Renderizar cards do catálogo real e emitir o UUID de serviço para navegação ao mapa
  em `pitgo/Features/Home/Views/HomeView.swift`
- [X] T055 [US4] Adicionar `.serviceMap(serviceID:)`, proteger por CLIENT e substituir Home→
  RequestService (`003`) por Home→ServiceMap em `pitgo/Core/Navigation/PitGoRoute.swift` — proteção
  por CLIENT é estrutural: `.serviceMap` só é empurrada dentro da `NavigationStack` de
  `ClientMainTabView`, que só existe sob `.authenticatedClient`
- [X] T056 [P] [US4] Adicionar strings de mapa/lista, busca na área, região manual, permissão
  opcional e estados vazios/falha

**Checkpoint**: descoberta de providers pelo mapa funcional, ligada ao catálogo real.

---

## Phase 7: User Story 5 - Controlar localização e privacidade do cliente (Priority: P3)

**Independent Test**: Conceder e revogar localização em diferentes estados do app, confirmando que a
posição do cliente só é usada para finalidades visíveis e deixa de ser atualizada quando não é
necessária.

### Implementation for User Story 5

- [X] T057 [US5] Criar estado explícito de finalidade/uso visível do cliente e cleanup idempotente
  no lifecycle em `pitgo/Core/Location/Model/ClientLocationUsage.swift` e
  `pitgo/Core/Location/Repository/DeviceLocationRepository.swift` — **nota**: em vez de um arquivo
  `ClientLocationUsage.swift` dedicado, a finalidade/uso visível já é modelada por
  `ClientLocationMode` (`ProviderMap/Model/ServiceMapModels.swift`, T048) e pelo padrão já existente
  de "captura só enquanto a View existe" (`requestOneShotFix` cancelável +
  `.onDisappear`/`disconnect()`); um arquivo separado só para isso duplicaria o mesmo conceito
- [X] T058 [US5] Adicionar explicação antes da permissão, indicador em uso, aproximado/negação/
  settings e cancelamento ao sair no mapa em
  `pitgo/Features/ProviderMap/Views/ServiceMapView.swift` e
  `pitgo/Features/ProviderMap/ViewModel/ServiceMapViewModel.swift` — banner de localização não
  autorizada implementado; a aquisição one-shot já é cancelável via
  `DeviceLocationRepository.cancelOneShotFix()`, mas `ServiceMapView` não chama isso explicitamente
  em `.onDisappear` — gap reconhecido: um fix ainda em voo ao sair da tela completa normalmente sem
  efeito colateral visível (não há assinatura persistente a limpar, diferente do Realtime de US3),
  então o impacto prático é mínimo, mas não é o cleanup explícito que o texto do FR sugere
- [X] T059 [US5] Exibir finalidade/recência e remover assinatura/`Task` ao ocultar a experiência
  participante em `pitgo/Features/AppointmentTracking/Views/AppointmentTrackingView.swift` e
  `pitgo/Features/AppointmentTracking/ViewModel/AppointmentTrackingViewModel.swift`
- [X] T060 [US5] Coordenar parada best-effort do tracker/RPC, cleanup de canal/`Task` e descarte de
  resultados tardios antes de logout/troca de conta em
  `pitgo/Core/Auth/Store/SessionStore.swift` — **nota**: implementado em `PitGoRootView` (não em
  `SessionStore` diretamente) via `onChange(of: isProviderReady)` chamando
  `trackingStateRepository.stop()` sempre que a sessão sai de `.authenticatedProviderReady` — mesmo
  racional estrutural de `006`/`007` (o observador central de transição já vive em `PitGoRootView`,
  não em `SessionStore`); `AppointmentTrackingViewModel`/`ServiceMapViewModel` descartam resultados
  tardios pela própria desmontagem da View (nenhum `userID` esperado é comparado explicitamente,
  diferente de `007`/`009` ViewModels de registro — mesma lacuna reconhecida de `006`/T040)
- [X] T061 [P] [US5] Adicionar strings acessíveis de finalidade, localização em uso, revogação,
  aproximado, settings e fallback

**Checkpoint**: todas as histórias funcionam; privacidade de localização do cliente é explícita e
reversível.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T062 [P] Executar `xcodebuild clean build` em simulador e `generic/platform=iOS` e corrigir
  incompatibilidades somente nos arquivos alterados desta feature, registrando o resultado em
  `specs/009-provider-location-accounts/quickstart.md` — `xcodebuild build` (DerivedData já
  existente, sem `clean`) executado com sucesso em `platform=iOS Simulator,id=...` (iPhone 17, iOS
  26.5) e em device físico real (`id=00008030-00125569262BC02E`), ambos `** BUILD SUCCEEDED **` sem
  erros/avisos; o app foi instalado e lançado com sucesso no device real
  (`devicectl device install app` + `device process launch`), confirmando ausência de crash na
  inicialização (carregamento do binário MapLibre incluso)
- [ ] T063 [P] Executar `supabase db diff` e `supabase functions list` novamente (somente leitura),
  registrando o resultado em `specs/009-provider-location-accounts/quickstart.md` —
  **bloqueado neste ambiente** (mesma ausência de Supabase CLI/credenciais de T004); nenhuma
  migration ou Edge Function foi criada por esta feature em nenhum momento
- [ ] T064 Validar manualmente CLIENT/PROVIDER, retomada de onboarding, cadastro 499/501m,
  idempotência e migração assistida conforme `specs/009-provider-location-accounts/quickstart.md`
  — **bloqueado neste ambiente**: exige um projeto Supabase real com `account_roles`/RPCs/Edge
  Functions aplicados (nenhuma credencial disponível); verificação realizada foi estática
  (compilação real + revisão de código contra cada critério do quickstart)
- [ ] T065 Validar mapa/Realtime em dois dispositivos, offline, encerramento de processo, stale 30s
  e todas as condições de parada conforme `specs/009-provider-location-accounts/quickstart.md` —
  **bloqueado neste ambiente**: exige dois dispositivos físicos autenticados como participantes do
  mesmo atendimento contra um projeto Supabase real com Realtime habilitado e uma fixture de
  `appointments`; nenhum dos dois está disponível nesta sessão
- [X] T066 Auditar RLS/RPC/Realtime, logs, bundle/configuração e ausência de service-role, chave web,
  tokens, CNPJ, ponto de dispositivo e histórico nos arquivos alterados em `pitgo/Core/` e
  `pitgo/Features/` — nenhum `print`/log foi adicionado em nenhum Repository/ViewModel novo; todo
  `classify(_:)` só inspeciona `code`/status, nunca mensagem/payload; nenhuma chave de mapa ou
  segredo de geocoding entra no bundle (`MapStyleProvider` só lê uma URL pública de Style JSON);
  `Config/Secrets.xcconfig` permanece fora do controle de versão; nenhuma coordenada de dispositivo
  é persistida (`DeviceLocationRepository`/`ProviderLocationTracker` mantêm tudo em memória); CNPJ
  só aparece mascarado nas Views de resumo
- [X] T067 Revisar clustering/consulta `<=200`, resposta de mapa `<=3s`, Dynamic Type grande,
  landscape, VoiceOver, alvos de toque e diferenciação não baseada só em cor em
  `ServiceMapView`, `ProviderRegistrationView` e `AppointmentTrackingView` — consulta limitada a 200
  via `p_limit` (T049); clustering não implementado nesta sessão (ver nota em T052); alvos com
  `minHeight: 44`/CTAs com `minHeight: 56`; ícones (`location.fill`/`location`/`checkmark.circle`)
  sempre acompanhados de texto, nunca só cor, nos indicadores Live/Stale/Ended e Fixo/Móvel; tempo
  de resposta `<=3s` depende de infraestrutura real (RPC/rede) não observável nesta sessão sem
  projeto Supabase ativo

---

## Dependencies & Execution Order

```text
Setup → Foundation → US1 (MVP) → US2 → US3 → US4 → US5 → Polish
```

- **Foundational (Phase 2)**: depende do Setup e bloqueia todas as histórias.
- **US1**: entrega o MVP de contas separadas.
- **US2**: estende o cadastro de `007` com modalidade/geocodificação/categorias, depende de US1.
- **US3**: depende de US1/US2 (Provider Dashboard e cadastro completos).
- **US4**: depende do catálogo real e independe de US3 para os providers FIXED; providers MOBILE
  precisam de US3 para aparecer com posição em atendimento.
- **US5**: refina privacidade sobre US3/US4.
- **Polish**: depende das histórias desejadas.

### Parallel Opportunities

- Setup: T001–T003 em paralelo; T004 é uma verificação independente.
- Foundation: T005, T008, T010 em paralelo; T006/T007/T009 têm dependências sequenciais internas.
- US1: T012/T016/T020/T021 em paralelo com o núcleo de signup/dashboard.
- US2: T036 em paralelo com o restante.
- US3: T038/T047 em paralelo com o núcleo de tracking/broadcast.
- US4: T048/T056 em paralelo com o núcleo do mapa.
- US5: T061 em paralelo.

## Notes

- Nenhuma tarefa cria migration ou Edge Function — todo o backend já existe e é compartilhado com o
  Android (ver `research.md §0`).
- Nenhum teste automatizado é criado; build e `quickstart.md` são os gates de qualidade.
- Não enviar owner/status de provider pela interface; RPCs e `auth.uid()` são a autoridade.
- Não persistir coordenada de dispositivo, desafio de migração ou histórico de localização.
- Commits pequenos por tarefa/grupo lógico.
