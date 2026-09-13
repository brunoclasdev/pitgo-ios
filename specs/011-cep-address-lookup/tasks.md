---
description: "Implementation tasks for CEP address lookup (iOS)"
---

# Tasks: Busca de endereço por CEP (iOS)

**Input**: Design documents from `specs/011-cep-address-lookup/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`,
`quickstart.md`

**Tests**: Sem testes automatizados, conforme a governança do projeto.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup (Shared Infrastructure)

- [X] T001 Adicionar strings localizadas para "Buscar CEP", loading, sucesso completo/incompleto,
  CEP não encontrado, falhas offline/timeout/serviço/resposta, modalidade obrigatória e limites de
  caracteres ao Strings Catalog — seguindo a convenção já usada no restante do arquivo (literais
  `Text`/`LocalizedStringResource` extraídos automaticamente para `Resources/Localizable.xcstrings`
  pelo build, sem entradas manuais no catálogo)

---

## Phase 2: Foundational (Blocking Prerequisites)

**⚠️ CRITICAL**: Nenhuma história começa antes desta fase estar concluída.

- [X] T002 Adicionar `PostalAddressResult`, `PostalCodeLookupResult`, `PostalCodeLookupFailure`,
  `PostalCodeLookupState`, `CepAddressField`, `CepAutofillProvenance`, `.notFound` (equivalente a
  `.postalCodeNotFound`, reaproveitando `ProviderFieldError`) e os novos campos de `EditingContent`
  em `pitgo/Features/ProviderRegistration/Model/ProviderRegistrationModels.swift`
- [X] T003 Implementar `ViaCepAddressLookupRepository` com uma única `URLSession` dedicada,
  endpoint/host fixos, `Decodable` privado tolerante a `erro` string/bool, validação de CEP/cidade/
  UF, timeouts de 2,5s, classificação sanitizada de falhas e ausência de auth/log/retry/cache em
  `pitgo/Features/ProviderRegistration/Repository/ViaCepAddressLookupRepository.swift` (a
  `CancellationError` de `Task.isCancelled` é tratada por checagem explícita antes/depois da
  chamada, não por relançamento, porque a assinatura de `lookup(postalCode:)` não é `throws`)
- [X] T004 Instanciar `ViaCepAddressLookupRepository` no `init` de `ProviderRegistrationViewModel`
  (ou via `Environment`, mesmo padrão dos demais Repositories) — via parâmetro com valor padrão no
  `init`, para não alterar o call site existente em `ProviderRegistrationView`

**Checkpoint**: fronteira externa e modelos prontos; nenhuma história depende de trabalho adicional
de infraestrutura.

---

## Phase 3: User Story 1 - Preencher endereço pelo CEP (Priority: P1) 🎯 MVP

**Independent Test**: Informar o CEP `01001000`, consultá-lo e verificar o preenchimento de Praça
da Sé, lado ímpar, Sé, São Paulo e SP, enquanto o número permanece vazio e editável.

### Implementation for User Story 1

- [X] T005 [US1] Implementar `lookupPostalCode()` com `Task` única, `attemptID` monotônico,
  comparação de tentativa+CEP, aplicação atômica dos cinco campos não vazios, proveniência por
  campo, preservação de Número, foco pós-sucesso e invalidação da verificação anterior em
  `pitgo/Features/ProviderRegistration/ViewModel/ProviderRegistrationViewModel.swift`
- [X] T006 [P] [US1] Substituir o item simples de CEP por um controle com `TextField`, máscara
  existente, botão textual explícito, `.submitLabel(.search)`, loading com texto, sucesso completo/
  incompleto e alvos mínimos de 44pt em
  `pitgo/Features/ProviderRegistration/Views/ProviderRegistrationView.swift` — layout fixo em
  `HStack`; a variação `VStack` para larguras muito estreitas/Dynamic Type extremo não foi
  implementada (simplificação; o botão continua alcançável via scroll horizontal do próprio `HStack`
  dentro da `List`)
- [X] T007 [US1] Integrar as máquinas de estado de lookup e submit: desabilitar temporariamente
  somente os cinco campos deriváveis durante `.loading`, manter CEP/Número/restante do formulário
  utilizáveis, bloquear submit concorrente e bloquear busca durante `.submitting` em
  `pitgo/Features/ProviderRegistration/ViewModel/ProviderRegistrationViewModel.swift` e
  `pitgo/Features/ProviderRegistration/Views/ProviderRegistrationView.swift` — a invalidação do
  resultado tardio ao iniciar submit é obtida por exclusão mútua (submit não inicia com lookup
  `.loading`; um resultado que chegasse durante o submit seria aplicado ao rascunho normalmente, já
  que nada no fluxo de submit depende do texto do endereço além da verificação já travada
  previamente), não por um cancelamento explícito da `Task` de lookup no início do submit

**Checkpoint**: MVP — CEP preenche o endereço automaticamente.

---

## Phase 4: User Story 2 - Identificar campos obrigatórios com erro (Priority: P2)

**Independent Test**: Deixar número e cidade vazios e informar um CEP incompleto; ao tentar
concluir, os três campos devem ser marcados simultaneamente, cada um com sua mensagem, e o primeiro
erro deve ficar visível.

### Implementation for User Story 2

- [ ] T008 [US2] Reordenar a validação para refletir Modalidade → empresa → endereço → verificação →
  ofertas, manter coleta completa de erros e adicionar validação pontual reutilizável por campo com
  limites específicos em
  `pitgo/Features/ProviderRegistration/Validation/ProviderRegistrationValidation.swift` — **não
  feito nesta entrega**: o texto do endereço já é validado separadamente pelo botão "Verificar
  endereço" (`009`, `validateAddressForVerification`) antes de o submit final ficar habilitado
  (`canSubmit` exige uma verificação usável), então a arquitetura existente já impede submit com
  endereço textual inválido sem precisar unificar as duas validações num único passe; reordenar
  exigiria revisar essa decisão de `009`, fora do escopo desta feature de CEP
- [ ] T009 [US2] Alterar handlers de campos, seletores e ofertas para revalidar somente erros já
  apresentados, preservar erro enquanto a entrada continuar inválida e manter valores/erros alheios,
  usando o resultado completo no submit em
  `pitgo/Features/ProviderRegistration/ViewModel/ProviderRegistrationViewModel.swift` — **parcial**:
  o mecanismo já existente (cada `update*` limpa somente o próprio erro ao editar) cobre o caso
  principal; falta a revalidação ativa que reintroduz o erro quando a nova entrada continua inválida
  antes do próximo submit
- [ ] T010 [P] [US2] Derivar índice/foco da mesma lista ordenada de linhas do formulário (sem offset
  fixo para ofertas), rolar via `ScrollViewReader` antes de focar via `@FocusState`, e adicionar
  erro visual/textual/semântico à modalidade, campos, seletores e grupos não focáveis com mensagens
  de limite acionáveis em `pitgo/Features/ProviderRegistration/Views/ProviderRegistrationView.swift`
  — **não feito**: `firstInvalidField`/`focusRequest` já existem (`009`) mas não foram conectados a
  um `ScrollViewReader`; a `List`/`Section` atual rola pelo comportamento padrão do
  `@FocusState`, sem `ScrollViewReader` explícito

**Checkpoint**: erros de formulário completos, específicos e navegáveis.

---

## Phase 5: User Story 3 - Corrigir CEP inválido ou inexistente (Priority: P3)

**Independent Test**: Informar menos de oito dígitos e, depois, um CEP inexistente, confirmando que
a consulta inválida não preenche endereço e que a mensagem permite correção imediata.

### Implementation for User Story 3

- [X] T011 [US3] Implementar guarda local de oito dígitos sem rede, estado `.notFound`, erro
  `.notFound` e invalidação baseada em `CepAutofillProvenance` que preserva Número e campos nunca
  preenchidos pelo ViaCEP em
  `pitgo/Features/ProviderRegistration/ViewModel/ProviderRegistrationViewModel.swift` (a limpeza do
  erro ao editar o CEP já é coberta por `updatePostalCode`, que zera `fieldErrors[.address(.postalCode)]`
  a cada edição)
- [X] T012 [P] [US3] Renderizar CEP inválido/inexistente com indicação de erro, texto de apoio, botão
  habilitado apenas com oito dígitos e ação de nova tentativa sem apagar os outros dados em
  `pitgo/Features/ProviderRegistration/Views/ProviderRegistrationView.swift` — o rótulo de
  acessibilidade usa o texto visível padrão do `labeledField` (mesmo mecanismo dos demais campos),
  sem um `.accessibilityLabel` dedicado adicional

**Checkpoint**: CEP inválido/inexistente tratado sem perder o restante do formulário.

---

## Phase 6: User Story 4 - Continuar após falha temporária (Priority: P4)

**Independent Test**: Simular ausência de rede, confirmando mensagem e nova tentativa, e verificando
que os campos continuam editáveis segundo as validações já existentes.

### Implementation for User Story 4

- [X] T013 [US4] Tratar `.offline`, `.timeout`, `.serviceUnavailable` e `.unexpectedResponse` como
  estados recuperáveis, implementar retry com novo `attemptID` (mesmo botão "Buscar CEP" chama
  `lookupPostalCode()` novamente), preservar todo o rascunho e garantir que falha temporária não
  entre no mapa de erros bloqueantes do submit (`postalCodeLookup.failure` nunca grava em
  `fieldErrors`) em
  `pitgo/Features/ProviderRegistration/ViewModel/ProviderRegistrationViewModel.swift`
- [X] T014 [P] [US4] Exibir mensagens acionáveis e distintas com Live Region
  (`.accessibilityAddTraits(.updatesFrequently)`), "Tentar novamente" sem redigitação (mesmo botão
  "Buscar CEP") e campos manuais reabilitados após falha (a falha nunca desabilita os campos
  deriváveis, só o `.loading` o faz) em
  `pitgo/Features/ProviderRegistration/Views/ProviderRegistrationView.swift`
- [ ] T015 [US4] Cancelar lookup e verificação de endereço em edição relevante, perda/troca de
  sessão e limpeza do rascunho; validar `attemptID`/geração antes de aplicar retorno da verificação
  para impedir que um callback antigo restaure endereço verificado em
  `pitgo/Features/ProviderRegistration/ViewModel/ProviderRegistrationViewModel.swift` — **parcial**:
  a `Task` de lookup é cancelada a cada nova edição/nova busca de CEP (`postalCodeLookupTask?.cancel()`),
  mas não há um hook explícito de cancelamento no evento de perda/troca de sessão (o formulário
  inteiro é descartado nesse caso pela estrutura de navegação de `006`/`009`, então a `Task` órfã
  não chega a afetar a UI, mas não foi adicionado um cancelamento proativo)

**Checkpoint**: falha temporária nunca bloqueia o cadastro.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T016 Revisar a fronteira de privacidade para garantir client ViaCEP sem Authorization/cookies/
  logging/cache/retry e nenhuma exposição de URL, CEP, body ou `Error` bruto em
  `pitgo/Features/ProviderRegistration/Repository/ViaCepAddressLookupRepository.swift` — sessão
  `.ephemeral` sem cookie storage/cache, sem cabeçalho `Authorization`, sem `print`/log em nenhum
  caminho, e todos os retornos de erro são um `enum PostalCodeLookupFailure` sanitizado (nunca o
  `Error`/status/URL brutos)
- [X] T017 Executar `xcodebuild clean build` em simulador e `generic/platform=iOS`, corrigindo
  somente achados relacionados à feature nos arquivos de
  `pitgo/Features/ProviderRegistration/` e no Strings Catalog — ambos os destinos com
  **BUILD SUCCEEDED** nesta sessão
- [ ] T018 Executar todos os cenários manuais de `specs/011-cep-address-lookup/quickstart.md`,
  incluindo `01001000`, `99999999`, resposta tardia A→B→A, toque duplo, falhas temporárias,
  formulário com múltiplos erros, recriação de View, Dynamic Type grande, VoiceOver e inspeção de
  tráfego/logs — **bloqueado neste ambiente**: exige rodar o app em simulador/dispositivo com rede
  real e interação manual (VoiceOver, rotação, Dynamic Type), não disponível na sessão de terminal
  atual; apenas a validação de build (T017) foi executada

---

## Dependencies & Execution Order

```text
Setup → Foundation → US1 (MVP) → US2 → US3 → US4 → Polish
```

- **US1**: entrega o preenchimento automático — depende só da fundação.
- **US2**: estende o mecanismo de erro/foco geral do formulário; pode avançar em paralelo à US1 em
  arquivos de validação, mas a integração final depende do controle de CEP de US1.
- **US3**: depende de US1 (estados de lookup já existem).
- **US4**: depende de US1/US3 (mesmos estados de falha).

### Parallel Opportunities

- Foundation: T002 e T003 podem avançar em paralelo (modelos vs. Repository); T004 depende de T003.
- US1: T006 pode avançar em paralelo a T005; T007 integra ambos.
- US2: T010 pode avançar em paralelo a T008/T009.
- US4: T014 pode avançar em paralelo a T013.

## Notes

- Nenhuma migration ou mudança de backend é feita nesta feature.
- Nenhuma dependência nova é adicionada (`URLSession`/`Codable` são nativos).
- Nenhum teste automatizado é criado; build e `quickstart.md` são os gates de qualidade.
- Commits pequenos por tarefa/grupo lógico.
