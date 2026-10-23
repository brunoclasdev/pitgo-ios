# Implementation Plan: Catálogo de serviços por categoria e mapa PitTec (porte iOS)

**Branch**: `026-service-catalog-map-card` | **Date**: 2026-10-22 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/026-service-catalog-map-card/spec.md`; comportamento
de referência em `../../../android/pitgo/specs/026-service-catalog-map-card/` (mesmo backend).

## Summary

O backend (Supabase compartilhado) já tem o catálogo seed, as RPCs protegidas de gestão e o
contrato de cadastro (`service_id` por oferta, sem `category_id`) em produção desde o porte
Android. Este plano cobre só o cliente iOS: (1) o cadastro de prestador fixo passa a trabalhar com
uma `primaryCategoryID` única no rascunho, com confirmação ao trocar categoria já preenchida; (2) a
tela de acompanhamento do PitTec (`PitTecClientView`) passa a tratar o mapa como conteúdo principal
em `ACCEPTED`/`IN_PROGRESS`, com um resumo compacto/expansível sobreposto, e o host de mapa
(`PitGoMapView`) para de reenquadrar a cada atualização de localização.

## Technical Context

**Language/Version**: Swift 5.10+, SwiftUI, iOS 16+ (deployment target atual do projeto, `151e0fd`)

**Primary Dependencies**: SwiftUI, Combine, MapLibre Native iOS (`PitGoMapView`), Supabase Swift
já adotados pelo projeto; nenhuma dependência nova.

**Storage**: PostgreSQL/Supabase — mesmo projeto (`eetbrkznuqbdrnybnyhf`) e mesmas tabelas/RPCs já
usadas pelo Android (`service_categories`, `services`, `provider_categories`, `provider_services`,
`create_provider_registration`). Nenhuma migration nova é criada por este plano.

**Testing**: build via `xcodebuild -scheme pitgo -destination 'generic/platform=iOS Simulator'`,
inspeção funcional em simulador/dispositivo; sem suíte automatizada nova, seguindo a prática já
adotada pelo projeto (testes manuais registrados em `validation.md`).

**Target Platform**: iOS 16+; backend Supabase/PostgreSQL compartilhado com o Android.

**Project Type**: app iOS nativo (SwiftUI) consumindo o mesmo backend do app Android — sem camada
de backend própria.

**Performance Goals**: nenhuma consulta redundante ao trocar categoria (reaproveitar
`servicesByCategory` já cacheado por categoria); atualizações de localização não devem
recriar/reenquadrar o `MLNMapView` nem interromper pan/zoom manual — validar em dispositivo.

**Constraints**: preservar o fluxo e os estados PitTec existentes (`searching`, `optionFound`,
`awaitingProvider`, `awaitingClientConfirmation`, `awaitingPayment`, `accepted`, `inProgress`,
estados terminais); não expor gestão de catálogo no app; não cobrir marcadores/rota com o painel
compacto; não alterar o payload já aceito pela RPC (`OfferPayload` já envia somente `service_id`).

**Scale/Scope**: uma categoria principal e várias ofertas por prestador fixo no cadastro; um painel
compacto/expansível por acompanhamento PitTec.

## Constitution Check

*GATE: Must pass before Phase 0 research and after Phase 1 design.*

- **Simplicidade**: PASS. Reutiliza o catálogo, a RPC de cadastro e o `PitGoMapView` existentes;
  adiciona só o estado de categoria única, confirmação de troca e o painel expansível.
- **MVVM/estado previsível**: PASS. `primaryCategoryID`, `pendingPrimaryCategoryChange` e
  `summaryExpanded` são estados explícitos em `EditingContent`/`PitTecClientView`; `ViewModel`
  continua controlando transições, `Repository` concentra o acesso a dados.
- **Dados e segurança**: PASS. Nenhuma mudança de superfície de acesso — o app continua lendo
  catálogo público autenticado e enviando só `service_id` por oferta; a gestão de catálogo
  permanece fora do app.
- **Qualidade proporcional**: PASS. Sem dependências novas; build e inspeção funcional cobrem o
  risco principal (cadastro e mapa PitTec).

## Project Structure

```text
specs/026-service-catalog-map-card/
├── plan.md
├── spec.md
├── tasks.md
└── contracts/
    └── provider-service-selection.md   (referência ao contrato já vigente no backend)

pitgo/Features/ProviderRegistration/
├── Model/ProviderRegistrationModels.swift         (primaryCategoryID, pendingPrimaryCategoryChange)
├── ViewModel/ProviderRegistrationViewModel.swift  (selectPrimaryCategory/confirm/cancel)
├── Validation/ProviderRegistrationValidation.swift (validação de categoria única)
└── Views/ProviderRegistrationView.swift           (seletor único + diálogo de confirmação)

pitgo/Features/PitTec/Views/PitTecClientView.swift  (resumo compacto/expansível sobre o mapa)
pitgo/Core/UI/PitGoMapView.swift                    (fitTrigger / fitBottomPadding)
```

**Structure Decision**: mantém a organização por feature já existente (`Features/ProviderRegistration`,
`Features/PitTec`, `Core/UI`). Nenhum módulo novo.

## Phase 0: Research

O comportamento já está validado e em produção no Android com o mesmo backend; a pesquisa de
produto e os contratos de RPC foram herdados de
`../../../android/pitgo/specs/026-service-catalog-map-card/research.md` e
`contracts/provider-service-selection.md`, sem `NEEDS CLARIFICATION` remanescente para o porte
iOS.

## Phase 1: Design

- O contrato de cadastro (`contracts/provider-service-selection.md`) é o mesmo já documentado pelo
  Android — reproduzido aqui só com a seção "Server validation"/"Registration payload" (ver
  `contracts/`), pois o RPC não muda.
- O comportamento do mapa/resumo PitTec segue a tabela de estados já documentada no contrato
  Android `pittec-map-summary.md`: compacto por padrão em `ACCEPTED`/`IN_PROGRESS`, expansível,
  reenquadramento só na abertura/recentralização.

## Constitution Check — Post-Design

- **Simplicidade**: PASS — nenhuma dependência ou arquitetura nova.
- **MVVM e estado**: PASS — categoria única, confirmação de troca e expansão do resumo são estados
  de tela explícitos.
- **Segurança**: PASS — nenhuma superfície de acesso nova; servidor continua sendo a autoridade
  final (`CATALOG_CHANGED`, `DUPLICATE_SERVICE` etc. já tratados pelo repositório existente).
- **Validação**: PASS — build do projeto e inspeção funcional em simulador/dispositivo cobrem o
  risco principal; registrar evidências em `validation.md`.

## Complexity Tracking

Nenhuma violação da constituição exige justificativa.
