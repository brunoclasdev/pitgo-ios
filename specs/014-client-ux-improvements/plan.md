# Implementation Plan: Melhoria de UX das telas do cliente (iOS)

**Branch**: `014-client-ux-improvements` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/014-client-ux-improvements/spec.md`

## Summary

Seis melhorias de UX no lado cliente/provider do PitGo iOS: (1) feedback claro (countdown vivo,
botões com indicador de carregamento, sem "0,0 km") durante a busca/solicitação de guincho; (2)
mapa do cliente centralizado na própria posição com o guincho se movendo em tempo real; (3) mapa do
provider, novo, mostrando sua posição e a do cliente enquadradas e atualizando em tempo real; (4)
especificação explícita do mecanismo de retomada automática de navegação para não interferir com um
"voltar" manual; (5) Home acionável (endereço e veículo viram ações diretas); (6) Perfil completo
(endereço, veículo padrão, seleção de aparência Claro/Escuro/Sistema).

Abordagem técnica: reaproveitar a infraestrutura de Realtime/tracking já especificada (`009`/`010`/
`013`), adicionar um mapa em `ProviderIncomingRequestView` seguindo o mesmo padrão de
`AppointmentTrackingView`, capturar a posição do cliente via leitura pontual de GPS (sem tracking em
background do lado cliente), especificar explicitamente o mecanismo de comparação de `revision` na
retomada automática, e completar Home/Perfil com ações e uma nova preferência de aparência via
`@AppStorage`. O backend novo desta feature (`client_addresses`, `client_current_locations` e as
quatro RPCs) já existe e é compartilhado com o Android — nenhuma migration nova é criada aqui.

## Technical Context

**Language/Version**: Swift 6, modo de concorrência estrita

**Primary Dependencies**: `supabase-swift` (`Auth`/`PostgREST`/`Realtime`, já habilitados); MapLibre
Native iOS (`010`); `CoreLocation` (`009`). Nenhuma dependência nova.

**Storage**: Supabase PostgreSQL hospedado — reaproveita RPCs `SECURITY DEFINER`/RLS/Realtime já
existentes de `009`/`013`; consome duas tabelas novas já compartilhadas
(`public.client_addresses`, `public.client_current_locations`), sem migration nova neste
repositório. `@AppStorage` local para a nova preferência de aparência.

**Testing**: sem testes automatizados, conforme a governança do projeto; validação manual com
verificação (leitura) do schema compartilhado, build via `xcodebuild` e matriz manual em
`quickstart.md`

**Target Platform**: iOS 17+, iPhone e iPad, portrait/landscape, Dynamic Type grande

**Project Type**: aplicativo iOS nativo de alvo único, organizado por feature

**Performance Goals**: countdown do FR-001 atualizado a cada 1s (já especificado em `013`, apenas
verificar não regressão); posição do guincho nos mapas refletindo a cadência já estabelecida (~10s
de publicação, visível em até ~15s, `013 quickstart.md`); ações de Home/Perfil (endereço, veículo,
tema) em no máximo 2 toques (SC-003, SC-004)

**Constraints**: nenhuma nova infraestrutura de rastreamento em background no dispositivo do
cliente (FR-012); nenhuma mudança de identidade visual (paleta, tipografia); reaproveitar
Views/Repositories existentes (`AppointmentTrackingView`, `ProviderIncomingRequestView`,
`MapLibreMapHost`, `DeviceLocationRepository`) em vez de recriar; preservar o comportamento
funcional já especificado de autenticação, logout, cadastro e despacho (FR-010); nenhuma migration
nova

**Scale/Scope**: ~7 Views tocadas (Home, Perfil, acompanhamento do cliente, atendimento do
provider, mais ViewModels/rotas associados), 6 user stories, 18 requisitos funcionais

## Constitution Check

*GATE inicial e pós-design: aprovado sem exceções.*

- **Simplicidade/YAGNI — PASS**: reaproveita infraestrutura/Views existentes (mapa, Realtime,
  `DeviceLocationRepository`, `@AppStorage`); a única estrutura nova no client (`Features/
  ClientAddress`) tem uso atual demonstrável (endereço do cliente não existe em nenhum spec iOS
  anterior) e reaproveita validação/CEP lookup/padrão de RPC já estabelecidos.
- **iOS nativo/MVVM — PASS**: SwiftUI + `@Observable` + `NavigationStack` já são o padrão do
  projeto; nenhuma dependência nova.
- **Estado/UX — PASS**: todos os FRs reforçam estados explícitos (`enum`s de loading/erro/vazio/
  sucesso), hierarquia clara e feedback imediato, sem nova cor/token fora do design system.
- **Dados/segurança — PASS**: nenhuma nova exposição de dado sensível; a posição do cliente ao
  provider só ocorre em atendimento aceito (mesmo modelo de autorização de `provider_current_locations`,
  `009`); localização segue o padrão de solicitar no momento de uso.
- **Qualidade proporcional — PASS**: sem testes automatizados não solicitados; mudanças cirúrgicas
  nas Views/ViewModels já especificados, sem refatoração ampla fora de escopo.

**Re-check pós-Phase 1 (design)**: `data-model.md` e `contracts/` confirmam que a única estrutura
persistida nova (para o client consumir) é `ClientAddress`/`ClientCurrentLocation`, ambas já
existentes no backend compartilhado; nenhuma tabela/RLS/RPC de `009`/`011`/`013` é alterada, só
lida. Os contratos de mapa/navegação descrevem apenas comportamento (câmera, comparação de
`revision`), sem novo protocolo de rede. Gate segue PASS.

## Project Structure

### Documentation (this feature)

```text
specs/014-client-ux-improvements/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── client-address-rpcs.md        # já existente/compartilhado
│   ├── client-location-rpcs.md       # já existente/compartilhado
│   └── appointment-map-and-navigation.md
└── tasks.md                         # criado posteriormente por $speckit-tasks
```

### Source Code (repository root)

```text
pitgo/
├── Core/
│   ├── Address/
│   │   └── Repository/ViaCepAddressLookupRepository.swift  # MOVIDO de Features/ProviderRegistration
│   ├── Preferences/AppearancePreferences.swift               # NOVO: @AppStorage Light/Dark/System
│   ├── Location/Repository/DeviceLocationRepository.swift    # 009, reaproveitado (leitura pontual)
│   ├── Map/UI/MapLibreMapHost.swift                           # 010, reaproveitado (mapa do provider)
│   └── Navigation/PitGoRootView.swift                         # ajuste: mecanismo de revision no resume
├── pitgoApp.swift                                              # ajuste: lê AppearancePreferences, aplica .preferredColorScheme
└── Features/
    ├── ClientAddress/                          # NOVO: form de endereço do cliente (reaproveita CEP lookup)
    │   ├── Repository/ClientAddressRepository.swift
    │   ├── ViewModel/ClientAddressViewModel.swift
    │   └── Views/ClientAddressView.swift
    ├── Home/Views/HomeView.swift               # ajuste: linha de endereço vira ação tocável
    ├── Profile/
    │   ├── Views/ProfileView.swift             # ajuste: seções de endereço, veículo, aparência
    │   └── ViewModel/ProfileViewModel.swift    # NOVO: agrega endereço/veículo/aparência
    ├── AppointmentTracking/
    │   ├── Repository/AppointmentTrackingRepository.swift  # ajuste: publica fix do cliente, snapshot combinado
    │   ├── Views/AppointmentTrackingView.swift              # ajuste: centralizar cliente + guincho
    │   └── ViewModel/AppointmentTrackingViewModel.swift     # ajuste: câmera dupla, fix pontual
    └── MobileDispatch/
        ├── Views/ClientMobileDispatchView.swift             # ajuste: loading inline (FR-002) e distância (FR-003)
        ├── Views/ProviderIncomingRequestView.swift          # ajuste: loading inline + NOVO mapa (FR-013..015)
        └── ViewModel/ProviderIncomingRequestViewModel.swift # ajuste: consome AppointmentTrackingRepository p/ posição do cliente

# Nenhuma migration nova — o backend já existe no repositório Android.
```

**Structure Decision**: alvo único, organizado por feature (já estabelecido). A maior parte dos
ajustes ocorre dentro das features já especificadas (`Home`, `Profile`, `AppointmentTracking`,
`MobileDispatch`) e em componentes compartilhados de `Core` (`Preferences`, `Location`, `Map`,
`Navigation`). Uma única feature nova, `ClientAddress`, é criada por ter responsabilidade própria e
testável isoladamente; `ViaCepAddressLookupRepository` (`011`) é promovido de
`Features/ProviderRegistration` para `Core/Address` para ser reaproveitado sem acoplamento entre
features.

## Complexity Tracking

Nenhuma violação constitucional foi identificada.
