---
description: "Tarefas do porte iOS dos ambientes Dev/Homol/Prod"
---

# Tasks: Ambientes iOS (Dev/Homol/Prod)

**Tests**: build dos três schemes via `xcodebuild`; sem suíte automatizada nova.

## Phase 1: Configuração (xcconfig/Info.plist/validação)

- [X] T001 Restruturar `Config/Shared.xcconfig` para base comum sem `#include` de secrets; adicionar
  `supabaseProjectRef`.
- [X] T002 [P] Criar `Config/Dev.xcconfig`/`Homol.xcconfig`/`Prod.xcconfig` (cada um
  `#include "Shared.xcconfig"` + seu `#include? "*.secrets.xcconfig"`); `Dev.xcconfig` força
  `mercadoPagoPublicKey` vazia por último; `Homol.xcconfig` inclui `Prod.secrets.xcconfig`.
- [X] T003 [P] Criar `Config/Dev.secrets.xcconfig`/`Prod.secrets.xcconfig` (reaproveitando os
  backends já usados pelo Android, mesmo projeto de desenvolvimento e mesmo projeto de produção) e
  os `.example` tracked; remover `Config/Secrets.xcconfig` (substituído); atualizar `.gitignore`.
- [X] T004 Adicionar `ENVIRONMENT_ID`/`SUPABASE_PROJECT_REF` a `AppInfo/Info.plist`.
- [X] T005 Estender `Scripts/validate-supabase-config.sh`: `supabaseProjectRef` consistente com
  `supabaseUrl`; isolamento Dev≠Prod lendo `Prod.secrets.xcconfig` do disco quando
  `ENVIRONMENT_ID=DEV`.

## Phase 2: Projeto Xcode (configurations/schemes)

- [X] T006 `project.pbxproj`: `PBXFileReference`/`PBXGroup` para os três `.xcconfig` novos.
- [X] T007 `project.pbxproj`: repontar `Debug`/`Release` (nível de projeto) de `Shared.xcconfig`
  para `Dev.xcconfig`; adicionar `Debug-Homol`/`Release-Homol`/`Debug-Prod`/`Release-Prod` (nível de
  projeto, apontando para `Homol.xcconfig`/`Prod.xcconfig`).
- [X] T008 `project.pbxproj`: adicionar `INFOPLIST_KEY_CFBundleDisplayName` ("PitGo Dev"/
  "PitGo Homol"/"PitGo") às seis configurações de nível de alvo (`Debug`/`Release` existentes +
  quatro novas).
- [X] T009 Criar `pitgo-Homol.xcscheme`/`pitgo-Prod.xcscheme` (cópia de `pitgo.xcscheme` com as
  build configurations trocadas); `pitgo.xcscheme` original fica inalterado (passa a ser Dev).

## Phase 3: User Story 1/4 — Identidade do ambiente (P1/P2)

- [X] T010 [P] [US1/US4] Criar `pitgo/Core/Environment/EnvironmentConfig.swift`
  (`EnvironmentID`/`PaymentMode`/`label`/`fingerprint`) e `EnvironmentDiagnostics.label`.
- [X] T011 [US1] Criar `pitgo/Core/Environment/EnvironmentStateRepository.swift` (fingerprint em
  `UserDefaults`) e ligar em `SessionStore.start()`, com `clearIncompatibleEnvironmentState()`
  (sign-out local do Supabase) antes do primeiro `bootstrap()`.
- [X] T012 [US4] Mostrar `EnvironmentDiagnostics.label` em `ProfileView` (abaixo do e-mail).

## Phase 4: User Story 2/3 — Gateway de pagamento (P1)

- [X] T013 [US2/US3] Criar `pitgo/Features/Payment/Repository/PaymentGateway.swift`
  (`PaymentGateway`/`SimulatablePaymentGateway`; `PaymentRepository: PaymentGateway`).
- [X] T014 [US2] Criar `pitgo/Features/Payment/Repository/SimulatedPaymentGateway.swift` (`actor`).
- [X] T015 [US2/US3] Trocar o tipo armazenado `PaymentRepository` → `PaymentGateway` em
  `PitGoRootView`, `ClientMobileDispatchViewModel`/`View`, `PaymentCheckoutViewModel`/`View`,
  `PitTecClientViewModel`/`View`; escolher o gateway em `PitGoRootView.init` a partir de
  `EnvironmentConfig.current.simulated`.
- [X] T016 [US2] Adicionar `simulated`/`simulate(_:)`/`simulateFailure()` a
  `PaymentCheckoutViewModel`; adicionar `simulationBanner` (Aprovar/Rejeitar/Expirar/Simular falha)
  a `PaymentCheckoutView`, visível só quando `viewModel.simulated`.

## Phase 5: Validação

- [X] T017 Build do scheme `pitgo` (Dev) — `xcodebuild -scheme pitgo -destination 'generic/platform=iOS Simulator'`.
- [X] T018 Build dos schemes `pitgo-Homol` e `pitgo-Prod`.
- [ ] T019 Validação funcional manual: Perfil mostra o ambiente certo nos três schemes; checkout em
  Dev mostra o banner/botões de simulação e nenhuma chamada `mp-*`; Homol/Prod seguem o fluxo
  integrado normal. Pendente de sessão manual do usuário (ver mensagem da conversa).

## Coverage

- US1: FR-001–FR-003, FR-008, FR-009; SC-001, SC-005.
- US2: FR-004, FR-005; SC-002, SC-003.
- US3: FR-006; SC-004.
- US4: FR-003, FR-007, FR-010; SC-001, SC-005.
