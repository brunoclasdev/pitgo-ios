# Implementation Plan: Corrigir cadastro de veículos e erros por campo (iOS)

**Branch**: `012-fix-vehicle-registration` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/012-fix-vehicle-registration/spec.md`

## Summary

`create_vehicle`/`set_primary_vehicle` **já foram restauradas** no backend compartilhado (migration
`20260823000000_restore_vehicle_rpcs.sql`, aplicada pela feature Android equivalente) — nenhuma ação
de schema é necessária nesta feature iOS. O trabalho é inteiramente client-side: fortalecer três
pontos do fluxo de veículo (`006`) — normalização/validação local com mensagens específicas,
classificação sanitizada dos erros PostgREST em erro de campo ou falha geral, e foco precedido por
rolagem explícita ao primeiro campo inválido. A conclusão do onboarding é movida para depois do
salvamento confirmado; onboarding vai para Home e cadastro iniciado na Garagem retorna à Garagem,
sempre removendo o formulário concluído do `NavigationPath`.

## Technical Context

**Language/Version**: Swift 6, modo de concorrência estrita

**Primary Dependencies**: `supabase-swift` (`PostgREST`, já habilitado); SwiftUI. Nenhuma
dependência nova.

**Storage**: Supabase PostgreSQL (`public.vehicles`, `public.profiles`, `public.account_roles` —
schema compartilhado, inalterado) e `UserDefaults` existente (`006`) somente para a pendência local
do onboarding

**Testing**: sem testes automatizados, conforme a governança do projeto; validação com verificação
(leitura) do schema restaurado, build via `xcodebuild` e fluxos manuais em `quickstart.md`

**Target Platform**: iOS 17+, iPhone e iPad, portrait e landscape, teclado aberto e Dynamic Type
grande

**Project Type**: aplicativo iOS nativo de módulo único com backend Supabase compartilhado

**Performance Goals**: primeira indicação de campo inválido visível e focada em até 1 segundo; 95%
dos salvamentos válidos concluem ou retornam falha acionável em até 5 segundos; uma única RPC por
toque aceito

**Constraints**: Marca e Modelo são os únicos obrigatórios; sem `service_role`, `userID` no
payload, DML direto, retry automático, migration nova, dependência nova, persistência local do
formulário ou testes automatizados

**Scale/Scope**: duas RPCs já existentes, treze campos do formulário existente, um fluxo de
onboarding, uma View de Garagem e os resumos de conta/Home já existentes

## Constitution Check

*GATE inicial e pós-design: aprovado sem exceções.*

- **Simplicidade/YAGNI — PASS**: reutiliza tabela, RPCs, Repository, ViewModel, formulário,
  `UserDefaults` e navegação existentes. Sem View nova, dependência ou infraestrutura especulativa.
- **iOS nativo/MVVM — PASS**: SwiftUI continua stateless; o ViewModel controla validação e
  submissão; o Repository permanece a única fronteira Supabase; a navegação decide o destino pela
  origem tipada.
- **Estado/UX — PASS**: operação, erros de campo, foco e origem são `enum`s explícitos no
  `@Observable`. Todos os erros conhecidos são apresentados juntos e falhas gerais ficam em banner
  separado.
- **Dados/segurança — PASS**: RPCs já `SECURITY DEFINER` com `search_path=''`, ownership de
  `auth.uid()`, papel `CLIENT`, RLS e execução restrita (inalteradas). A classificação iOS usa
  apenas códigos/tokens permitidos e nunca registra o `Error` bruto.
- **Qualidade proporcional — PASS**: a migration (já aplicada) é aditiva e reproduzível; locking
  transacional protege a unicidade do principal; build, verificação de schema e cenários manuais
  cobrem o risco sem criar testes não solicitados.

O design pós-Phase 1 mantém todos os gates aprovados. Nenhuma migration nova é necessária — a
restauração já foi feita e é compartilhada.

## Project Structure

### Documentation (this feature)

```text
specs/012-fix-vehicle-registration/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── vehicle-form-ui.md
│   └── vehicle-rpcs.md            # contrato das RPCs já restauradas; nenhuma migration aqui
└── tasks.md                         # criado posteriormente por $speckit-tasks
```

### Source Code (repository root)

```text
pitgo/
├── Core/
│   ├── Auth/Store/SessionStore.swift
│   └── Vehicle/
│       ├── Data/VehicleDTOs.swift
│       ├── Model/VehicleModels.swift
│       ├── Repository/VehicleRepository.swift
│       └── Validation/VehicleValidation.swift
└── Features/
    ├── Garage/
    │   ├── Views/VehicleFormView.swift
    │   └── ViewModel/{GarageViewModel.swift, VehicleFormViewModel.swift}
    └── Onboarding/
        ├── Views/VehicleOnboardingView.swift
        └── ViewModel/VehicleOnboardingViewModel.swift

# Nenhuma migration nova — a restauração já existe no repositório Android.
```

**Structure Decision**: manter o alvo único e as responsabilidades já consolidadas em `006`.
Modelos, DTOs, validação e Repository de veículo permanecem em `Core/Vehicle` porque são consumidos
por Garagem, Home, conta e onboarding. Estado e View do formulário continuam na feature `Garage`.

## Complexity Tracking

Nenhuma violação constitucional foi identificada.
