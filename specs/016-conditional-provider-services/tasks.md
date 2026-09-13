---
description: "Implementation tasks for conditional provider service selection (iOS)"
---

# Tasks: Seleção de serviços condicionada à modalidade do prestador (iOS)

**Input**: Design documents from `specs/016-conditional-provider-services/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`,
`quickstart.md`

**Tests**: Sem testes automatizados, conforme a governança do projeto.

> **ACHADO CRÍTICO, PRÉ-EXISTENTE (não introduzido por esta feature)**: inspecionando
> `create_provider_registration` no projeto Supabase compartilhado via `pg_get_functiondef` nesta
> sessão, a assinatura real é `(p_provider jsonb, p_address jsonb, p_offers jsonb)` — sem
> `p_geocode_verification_id`/`p_divergence_confirmed`, que é o que
> `ProviderRegistrationRepository.submit()` (`009`) atualmente envia. A Edge Function
> `geocode-provider-address` (baixada e inspecionada nesta sessão) já retorna `verification_token`
> (string), não um `verification_id` (UUID), confirmando que o RPC real espera o endereço + token
> dentro de `p_address`, não os parâmetros separados que o client envia hoje. **Toda submissão de
> cadastro de empresa (Fixo, Móvel ou PitTec) provavelmente falha contra o backend real neste
> estado** — um bug de `009` anterior a esta sessão, fora do escopo de `014`/`015`/`016`, não
> corrigido aqui por exigir uma reconciliação maior (Repository, ViewModel e a UI de verificação de
> endereço) que mereceria sua própria passada dedicada. As mudanças desta feature (016) estão
> corretas em relação ao desenho pretendido e passam a funcionar automaticamente assim que esse bug
> for corrigido — só não são verificáveis ponta a ponta contra o RPC real enquanto ele persistir.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Foundational (Blocking Prerequisites)

- [X] T001 Confirmar que `CatalogService`/`CatalogServiceDTO` (`007`/`009`) já expõem
  `dispatchKind`; caso contrário, adicioná-lo em
  `pitgo/Features/ProviderRegistration/Model/ProviderRegistrationModels.swift` e
  `pitgo/Features/ProviderRegistration/Data/ProviderRegistrationDTOs.swift`
- [X] T002 Implementar `resolveImplicitService(dispatchKind:)` (`.found`/`.missing`/`.duplicated`,
  buscando no máximo 2 registros) em
  `pitgo/Features/ProviderRegistration/Repository/ProviderRegistrationRepository.swift`

**Checkpoint**: resolução do serviço implícito disponível para o ViewModel.

---

## Phase 2: User Story 1 - Prestador Fixo escolhe seus serviços (Priority: P1) 🎯 MVP (regressão)

**Independent Test**: Cadastrar um prestador com modalidade Fixo e verificar que o envio só é
permitido depois de selecionar pelo menos um serviço com preço e duração válidos; nenhum serviço é
atribuído automaticamente.

### Implementation

- [X] T003 [US1] Confirmar (sem alterar) que a modalidade `.fixed` mantém a lista de ofertas
  controlada manualmente pelo prestador, conforme já especificado em
  `pitgo/Features/ProviderRegistration/ViewModel/ProviderRegistrationViewModel.swift`
- [ ] T004 [US1] **bloqueado neste ambiente** (interação manual). Executar os cenários de regressão de Fixo descritos em
  `specs/016-conditional-provider-services/quickstart.md §2`

---

## Phase 3: User Story 2 - Prestador Guincho não escolhe serviço (Priority: P1)

**Independent Test**: Cadastrar um prestador com modalidade Móvel e verificar que a tela não exibe
seleção de categoria/serviço e que o cadastro é aceito normalmente.

### Implementation

- [X] T005 [US2] Ao selecionar `.mobile`, substituir `offers` por uma única oferta pré-vinculada ao
  serviço `.mobileSequential` resolvido (categoria/serviço travados, preço/duração editáveis) em
  `pitgo/Features/ProviderRegistration/ViewModel/ProviderRegistrationViewModel.swift`
- [X] T006 [US2] Ocultar os seletores de categoria/serviço e exibir somente preço/duração para a
  modalidade `.mobile` em `pitgo/Features/ProviderRegistration/Views/ProviderRegistrationView.swift`
- [X] T007 [US2] Bloquear o envio com `.catalogChanged` quando a resolução do serviço Guincho for
  `.missing`/`.duplicated`, sem criar um prestador sem serviço associado
- [ ] T008 [US2] **bloqueado neste ambiente** (interação manual). Executar os cenários de Guincho descritos em
  `specs/016-conditional-provider-services/quickstart.md §3`

---

## Phase 4: User Story 3 - Prestador PitTec não escolhe serviço nem preço (Priority: P1)

**Independent Test**: Cadastrar um prestador com modalidade PitTec e verificar que nenhuma tela de
seleção de serviço, preço ou duração é exibida, e que o cadastro é aceito normalmente.

### Implementation

- [X] T009 [US3] Ao selecionar `.pittec`, substituir `offers` por uma única oferta pré-vinculada ao
  serviço `.pittecAutoSequential` resolvido, com `isFree = true`, preço zero e duração padrão
  interna (não editável/exibida) em
  `pitgo/Features/ProviderRegistration/ViewModel/ProviderRegistrationViewModel.swift`
- [X] T010 [US3] Ocultar toda a seção de oferta (categoria, serviço, preço, duração) para a
  modalidade `.pittec` em `pitgo/Features/ProviderRegistration/Views/ProviderRegistrationView.swift`
- [X] T011 [US3] Bloquear o envio com `.catalogChanged` quando a resolução do serviço PitTec for
  `.missing`/`.duplicated`
- [ ] T012 [US3] **bloqueado neste ambiente** (interação manual). Executar os cenários de PitTec descritos em
  `specs/016-conditional-provider-services/quickstart.md §4`

---

## Phase 5: Polish & Cross-Cutting Concerns

- [X] T013 Implementar a troca de modalidade durante o preenchimento (descarte de seleção manual ao
  ir para Móvel/PitTec; reaparição da obrigatoriedade ao voltar para Fixo) em
  `pitgo/Features/ProviderRegistration/ViewModel/ProviderRegistrationViewModel.swift`
- [X] T014 Executar `xcodebuild clean build` — simulador e `generic/platform=iOS`, **BUILD SUCCEEDED** conforme
  `specs/016-conditional-provider-services/quickstart.md`
- [ ] T015 **bloqueado neste ambiente**: matriz manual completa (troca de modalidade, catálogo inconsistente, escopo)
  descrita em `specs/016-conditional-provider-services/quickstart.md §5-§7`

---

## Dependencies & Execution Order

```text
Foundation → US1 (regressão) → US2 → US3 → Polish
```

### Parallel Opportunities

- US2 e US3 podem ser desenvolvidas em paralelo (arquivos compartilhados, mas lógica independente
  por modalidade); coordenar edições concorrentes ao ViewModel/View.

## Notes

- Nenhuma migration ou RPC nova — feature inteiramente client-side.
- Nenhuma dependência nova é adicionada.
- Nenhum teste automatizado é criado; build e `quickstart.md` são os gates de qualidade.
- Commits pequenos por tarefa/grupo lógico.
