---
description: "Tarefas do porte iOS do catálogo por categoria e resumo PitTec"
---

# Tasks: Catálogo de serviços por categoria e mapa PitTec (porte iOS)

**Input**: Design documents from `specs/026-service-catalog-map-card/` (iOS) e do Android
(`../../../android/pitgo/specs/026-service-catalog-map-card/`, mesmo backend).

**Tests**: Sem suíte automatizada nova — build (`xcodebuild`) e validação funcional em
simulador/dispositivo, seguindo a prática já adotada pelo projeto.

**Organization**: Tarefas por história; [P] indica arquivos independentes. Caminhos relativos à
raiz do projeto iOS.

## Phase 1: Setup

- [X] T001 Revisar o contrato de cadastro vigente (`ProviderRegistrationDTOs.swift`) e confirmar
  que o backend compartilhado já tem o catálogo seed e as RPCs de `026` aplicadas (mesmo projeto
  Supabase do Android) — sem migration nova. Registrado em `plan.md`/`contracts/`.

## Phase 2: User Story 1 — Categoria única + seleção de serviços (P1, MVP)

Validação independente: cadastrar Borracharia com dois serviços, trocar de categoria com oferta
preenchida (deve pedir confirmação), rejeitar duplicado, confirmar somente as ofertas da categoria
final persistidas.

- [X] T002 [US1] Substituir `OfferDraft.categoryID` por `ProviderRegistrationDraft.primaryCategoryID`
  único; adicionar `offersHaveMeaningfulContent`/`hasMeaningfulContent` e
  `PendingPrimaryCategoryChange` em
  `pitgo/Features/ProviderRegistration/Model/ProviderRegistrationModels.swift`.
- [X] T003 [US1] Adicionar `case primaryCategory` a `ProviderField`, remover `.category` de
  `OfferField` no mesmo arquivo do T002.
- [X] T004 [US1] Implementar `selectPrimaryCategory`/`confirmPrimaryCategoryChange`/
  `cancelPrimaryCategoryChange`/`applyPrimaryCategoryChange` (substitui `updateOfferCategory`),
  ajustar `updateLocationMode`/`resolveImplicitService` para o campo único em
  `pitgo/Features/ProviderRegistration/ViewModel/ProviderRegistrationViewModel.swift`.
- [X] T005 [P] [US1] Validar `primaryCategoryID` obrigatório para `FIXED` (fora do laço de ofertas),
  remover a validação de categoria por oferta e ajustar `firstInvalidField` em
  `pitgo/Features/ProviderRegistration/Validation/ProviderRegistrationValidation.swift`.
- [X] T006 [US1] Extrair `primaryCategoryField` (seletor único + `confirmationDialog` de troca),
  simplificar `offerRow`/`serviceField` para usar a categoria do rascunho em
  `pitgo/Features/ProviderRegistration/Views/ProviderRegistrationView.swift`.
- [ ] T007 [US1] Executar os cenários de cadastro (categoria única, troca com confirmação,
  cancelamento da confirmação, duplicação, regressão Móvel/PitTec) em simulador/dispositivo —
  pendente de sessão manual com conta de prestador real; registrar resultados em
  `specs/026-service-catalog-map-card/validation.md`.

## Phase 3: User Story 2 — Catálogo inicial e gestão (P1)

Já cumprido pelo backend compartilhado (seed e RPCs de gestão aplicados pelo porte Android). Sem
tarefas de cliente — `ServiceCatalogRepository`/`ProviderRegistrationRepository` já leem o catálogo
ativo filtrado por categoria.

- [X] T008 [US2] Confirmar que `ProviderRegistrationRepository.fetchCategories()`/`fetchServices
  (categoryID:)` já filtram ativos e não precisam de paginação adicional para o porte iOS.

## Phase 4: User Story 3 — Mapa PitTec desobstruído (P1)

Validação independente: pagamento aprovado, mapa visível em tela cheia, resumo compacto por
padrão, expandir/recolher sem navegação, 20 atualizações de localização sem mover o viewport
manual, recentralização só pelo botão dedicado.

- [X] T009 [P] [US3] Adicionar `fitTrigger`/`fitBottomPadding` a `PitGoMapView`, trocando o gate de
  reenquadramento de "coordenadas mudaram" para "trigger mudou" em
  `pitgo/Core/UI/PitGoMapView.swift`.
- [X] T010 [US3] Substituir o `VStack` que encolhia o mapa por `ZStack` com resumo
  compacto/expansível sobreposto (`summaryPanel`), botão de recentralizar e medição de altura via
  `PreferenceKey`, cancelar disponível somente expandido, em
  `pitgo/Features/PitTec/Views/PitTecClientView.swift` (`acceptedState`).
- [ ] T011 [US3] Validar em simulador/dispositivo: `ACCEPTED` após pagamento, chegada,
  `IN_PROGRESS`, estados terminais, GPS antigo, offline, e preservação do pan/zoom manual por 20
  atualizações simuladas — pendente de sessão manual com um acompanhamento PitTec real; registrar
  resultados em `specs/026-service-catalog-map-card/validation.md`.

## Phase 5: Polish & Cross-Cutting Concerns

- [X] T012 Build completo (`xcodebuild -scheme pitgo -destination 'generic/platform=iOS
  Simulator'`): `** BUILD SUCCEEDED **`, sem erros de compilação introduzidos pelas mudanças de
  `026`. Revisão de acessibilidade (Dynamic Type, VoiceOver, toque mínimo 44pt) feita por leitura de
  código — ainda sem confirmação visual em simulador (ver T007/T011).
- [ ] T013 Conferir cobertura de FR-001 a FR-013 e SC-001 a SC-005 de `spec.md`, marcando tarefas
  somente após execução e documentando evidências pendentes em `validation.md`.

## Dependencies & Execution Order

```text
T001 → Foundation ready
  ├─ US1: T002 → T003 → T004 → T005 → T006 → validação T007
  ├─ US2: T008 (sem dependência das demais)
  └─ US3: T009 → T010 → validação T011
Todas as histórias → T012 → T013
```

US1 e US3 são independentes entre si (arquivos distintos); T009 (host de mapa) precede T010 (tela
PitTec) pois a View passa a usar os novos parâmetros do host.

## Coverage

- US1: FR-001–FR-007; SC-001, SC-002.
- US2: nenhum FR de cliente novo — já cumprido pelo backend compartilhado.
- US3: FR-008–FR-013; SC-003–SC-005.
- T012–T013 verificam build e requisitos transversais.
