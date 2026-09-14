# Implementation Plan: Aceite do PitTec com confirmação de valor e mapa conjunto

**Branch**: `021-pittec-accept-confirm-tracking` | **Date**: 2026-09-13 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/021-pittec-accept-confirm-tracking/spec.md`

## Summary

Entre o aceite do PitTec e o acompanhamento no mapa, esta feature insere um passo de confirmação
de valor: o cliente vê um card com o valor já pago (revisão informativa, sem nova cobrança — FR-002)
e confirma ou recusa; o PitTec espera numa tela dedicada até essa confirmação chegar. Depois de
confirmado, os mapas do cliente e do PitTec passam a enquadrar as duas posições juntas (hoje cada um
só vê marcadores soltos, sem nenhuma lógica de "caber os dois na tela"), e a atualização periódica
de posição do PitTec já existente continua alimentando esse mapa conjunto.

**Descoberta central do Phase 0**: sincronizar "o cliente confirmou" entre os dois aparelhos exige
um sinal persistido no backend compartilhado (nenhum RPC/coluna hoje carrega essa informação) — o
usuário confirmou que fica responsável por essa parte (ver `research.md` §1). O trabalho **deste
repositório iOS** consome essa nova RPC como dependência externa, exatamente como já consome todas
as outras RPCs do PitTec hoje.

## Technical Context

**Language/Version**: Swift 6.0 (`SWIFT_VERSION` do projeto)

**Primary Dependencies**: SwiftUI, MapLibre Native iOS (`PitGoMapView`, `MLNMapView.setVisibleCoordinates(_:count:edgePadding:animated:)` para enquadrar múltiplos pontos — API já disponível no SDK vendorizado, nenhuma dependência nova), Supabase Realtime (canais já existentes `mobile-dispatch:<searchID>`/`provider-dispatch:<providerID>`), Swift Concurrency

**Storage**: N/A no client (nenhuma persistência local nova). Uma coluna nova no backend Supabase
compartilhado é necessária (fora deste repositório — ver `contracts/confirm-pittec-value-rpc.md`)

**Testing**: XCTest disponível; não solicitado explicitamente para esta feature (regra V da
constituição) — validação por `quickstart.md`

**Target Platform**: iOS 17+

**Project Type**: App iOS nativo (Xcode single project); mudança concentrada na feature
`Features/PitTec` (client + provider) e em `Core/UI/PitGoMapView.swift`

**Performance Goals**: nenhuma chamada de rede adicional além da nova RPC de confirmação (uma
chamada por atendimento); atualização de posição continua no mesmo intervalo já existente (~10s)

**Constraints**: a coluna/RPC nova (`confirm_pittec_appointment`) é uma dependência externa deste
plano — este repositório iOS não contém migration nem definição de RPC (regra da constituição:
"nenhuma migration de schema, RPC ou Edge Function é feita por este app"); o trabalho aqui pressupõe
que ela existirá com o contrato descrito em `contracts/confirm-pittec-value-rpc.md`. Nenhuma outra
RPC muda de formato

**Scale/Scope**: 2 Views + 2 ViewModels da feature `PitTec` (cliente e provider), 1 novo campo em
`PitTecAppointment`, 1 novo método de repositório, 1 nova capacidade de enquadramento em
`PitGoMapView`; nenhuma mudança em `Features/MobileDispatch` (guincho móvel `013`, que não tem esse
passo de confirmação) nem em `Features/ProviderMap`/`ServiceMapView`

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Simplicidade/YAGNI**: PASS — reaproveita o mesmo envelope (`PitTecFlowResult`)/helper
  (`call(_:params:)`) já usado por toda RPC do PitTec; a recusa do valor reaproveita
  `cancel_mobile_appointment` já existente em vez de criar uma política de cancelamento nova; o
  enquadramento conjunto usa uma API nativa do MapLibre já vendorizado, sem dependência nova.
- **II. MVVM**: PASS — a nova lógica de confirmação/espera vive nas ViewModels
  (`PitTecClientViewModel`/`PitTecIncomingRequestViewModel`); as Views apenas renderizam o novo
  sub-estado derivado de `appointment.confirmedAt` e emitem `confirmValue()`/`declineValue()`.
- **III. Estado previsível**: PASS — nenhum `Bool` paralelo novo; o sub-estado
  "aguardando"/"confirmado" é derivado de um único campo opcional (`confirmedAt: Date?`) já dentro
  do `enum`/struct existente (`PitTecAppointment`), não um novo caso de `PitTecClientUiState`.
- **IV. Dados/segurança**: PASS — nenhuma posição exata nova é exposta antes do already-established
  ponto do fluxo (aceite); `confirmedAt` é só um timestamp, sem dado sensível. A dependência de
  backend é tratada como tal (não implementada por este app), preservando "nenhuma migration de
  schema, RPC ou Edge Function é feita por este app".
- **Restrição explícita da constituição** (RPCs/schema fora deste app): a introdução de
  `confirm_pittec_appointment` e da coluna `confirmed_at` é responsabilidade do usuário/administrador
  do Supabase compartilhado (confirmado nesta sessão), não deste plano de implementação iOS — ver
  `research.md` §1 para a decisão completa e as alternativas descartadas.

Nenhuma violação do lado iOS — tabela de Complexity Tracking não se aplica ao código deste
repositório. A dependência de backend está documentada como pré-requisito externo, não como uma
exceção da constituição.

**Re-check pós-design (Fase 1)**: `data-model.md` e os contratos confirmam que o único novo campo
(`confirmedAt`) se encaixa na estrutura existente sem novo caso de enum, e que o enquadramento de
mapa usa uma capacidade nativa já disponível. Gates permanecem PASS.

## Project Structure

### Documentation (this feature)

```text
specs/021-pittec-accept-confirm-tracking/
├── plan.md              # This file ($speckit-plan command output)
├── research.md          # Phase 0 output ($speckit-plan command)
├── data-model.md         # Phase 1 output ($speckit-plan command)
├── quickstart.md         # Phase 1 output ($speckit-plan command)
├── contracts/            # Phase 1 output ($speckit-plan command)
│   ├── confirm-pittec-value-rpc.md   # contrato da RPC/coluna nova (dependência externa)
│   └── pittec-confirmation-tracking-ui.md  # contrato de UI (estados/mapa)
└── tasks.md              # Phase 2 output ($speckit-tasks command - NOT created by $speckit-plan)
```

### Source Code (repository root)

```text
pitgo/
├── Features/PitTec/
│   ├── Model/
│   │   └── PitTecModels.swift             # PitTecAppointment ganha confirmedAt: Date?
│   ├── Repository/
│   │   └── PitTecRepository.swift         # novo confirmValue(appointmentID:expectedRevision:)
│   ├── ViewModel/
│   │   ├── PitTecClientViewModel.swift    # confirmValue()/declineValue(); deriva sub-estado
│   │   └── PitTecIncomingRequestViewModel.swift  # novo sub-estado "aguardando confirmação"
│   └── Views/
│       ├── PitTecClientView.swift         # novo card de confirmação; acceptedState ganha
│       │                                  # enquadramento conjunto
│       └── PitTecIncomingRequestView.swift # nova tela de espera antes de reservedState
└── Core/UI/
    └── PitGoMapView.swift                 # nova capacidade: enquadrar múltiplas coordenadas
                                            # (setVisibleCoordinates), além do centerCoordinate único
```

**Structure Decision**: Mudança contida na feature `Features/PitTec` existente (client + provider) e
em `Core/UI/PitGoMapView.swift` (capacidade de mapa compartilhada, sem afetar quem só usa
`centerCoordinate`, como `020` e `ServiceMapView`). Nenhum novo grupo/feature criado. A RPC/coluna
nova pertence ao backend Supabase compartilhado (fora deste repositório) — documentada em
`contracts/confirm-pittec-value-rpc.md` para quem for implementá-la.

## Complexity Tracking

> Nenhuma violação do lado iOS a justificar. A única "complexidade" adicional (uma RPC nova) é uma
> dependência externa ao backend compartilhado, não uma exceção às regras desta constituição —
> registrada para rastreabilidade, não para justificar desvio de princípio:

| Item | Por que é necessário | Alternativa mais simples descartada |
|------|----------------------|--------------------------------------|
| Nova RPC `confirm_pittec_appointment` + coluna `confirmed_at` (backend, fora deste repo) | O PitTec precisa saber, entre dispositivos diferentes, que o cliente confirmou — só o backend compartilhado (lido por ambos via os canais Realtime já existentes) pode carregar esse sinal | Confirmação puramente local/client-side (sem sincronizar o PitTec) foi avaliada e descartada pelo usuário nesta sessão — ver `research.md` §1, alternativas B/C |
