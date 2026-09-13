# Implementation Plan: Contas independentes e localização de prestadores (iOS)

**Branch**: `009-provider-location-accounts` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/009-provider-location-accounts/spec.md`

## Summary

Separar cliente e empresa em identidades autenticadas de papel único no client iOS, consumindo o
mesmo backend já reconciliado pela feature Android (`account_roles`, `providers.account_id`
desacoplado, geocodificação, discovery PostGIS, tracking em tempo real). O cadastro empresarial
continua um fluxo público dedicado (`ProviderSignUpView`), seguido por onboarding autenticado que
salva empresa, modalidade, categorias/serviços e endereço geocodificado por uma RPC atômica e
idempotente já existente. Providers legados continuam pertencendo ao cliente até uma transferência
assistida que troca somente a conta proprietária da empresa.

A descoberta usa **MapLibre Native iOS** (mesmo provedor de tiles self-hosted do Android, conforme a
constitution) e a mesma projeção PostGIS filtrada pelo UUID exato do serviço; providers fixos e
móveis aparecem publicamente pelo endereço. Somente durante um atendimento `ACCEPTED` ou
`IN_PROGRESS`, um provider móvel mantém uma única posição corrente, publicada aproximadamente a cada
10 segundos via `CLLocationManager` com atualização em background (sem foreground service — o iOS
mostra automaticamente o indicador de sistema de uso de localização), distribuída aos participantes
por Supabase Broadcast privado. A posição fica desatualizada após 30 segundos e nunca forma
histórico. Nenhuma migration ou Edge Function nova é criada nesta feature iOS — tudo já existe e é
compartilhado.

## Technical Context

**Language/Version**: Swift 6, modo de concorrência estrita

**Primary Dependencies**: `supabase-swift` (produtos `Auth`, `PostgREST`, `Functions` e `Realtime`,
todos do mesmo pacote já resolvido em `004`–`007`); **MapLibre Native iOS** (Swift Package, novo
nesta feature, conforme decisão já registrada na constitution); `CoreLocation` (framework do
sistema, sem Swift Package). Nenhuma dependência de billing/chave de mapa proprietária.

**Storage**: Supabase Auth + PostgreSQL com PostGIS (schema já existente e compartilhado); nenhuma
persistência local de coordenadas; desafio de migração de propriedade só em memória de processo

**Testing**: build via `xcodebuild`, verificação (não aplicação) do schema/Edge Functions
compartilhados e validação manual em `quickstart.md`; nenhum teste automatizado, conforme governança
do projeto

**Target Platform**: iOS 17+, iPhone e iPad, Debug e destino `generic/platform=iOS`; dispositivos
físicos para os cenários de localização em background e Realtime com dois participantes

**Project Type**: aplicativo iOS nativo de alvo único, com backend Supabase compartilhado com o
Android (mesmo projeto remoto, mesmo schema, mesmas Edge Functions)

**Performance Goals**: primeiro resultado/estado vazio do mapa em até 3s p95; atualização móvel alvo
de 10s; marcador considerado desatualizado em 30s; consulta espacial limitada a 200 resultados e
renderizada com clustering nativo do MapLibre Style Spec

**Constraints**: um papel por conta/e-mail; nenhuma service-role no bundle; `.authorizedAlways`
solicitada somente no início do tracking de provider, nunca no cadastro; atualização em background
somente após ação visível de aceitar atendimento; sem histórico de localização; mapa público nunca
usa posição móvel; credenciais e coordenadas sensíveis não aparecem em logs; nenhuma migration/Edge
Function nova

**Scale/Scope**: dois destinos autenticados (cliente/empresa), cadastro e migração de empresa,
catálogo paginado sem limite artificial de seleção, mapa por serviço, no máximo um atendimento ativo
por provider nesta versão e uma posição corrente por atendimento

## Constitution Check

*GATE inicial e pós-design: aprovado.*

- **Simplicidade/YAGNI — PASS**: cada peça nova no client tem uso atual. `Functions`/`Realtime` já
  são produtos do pacote `supabase-swift` único (sem dependência nova); MapLibre é a única
  dependência SPM nova, exigida pela consistência de fornecedor de mapa já decidida na constitution.
  Sem histórico, frota, despacho completo ou framework de DI.
- **iOS nativo/MVVM — PASS**: Views SwiftUI stateless, ViewModels `@Observable`, Repositories para
  Supabase/`CoreLocation`/MapLibre, `Task`/`AsyncStream` para concorrência, `NavigationStack`/
  `TabView` centralizados. Sem framework de DI — injeção por `init`/`Environment`.
- **Estado/UX — PASS**: sessão, permissão, verificação de endereço, mapa, cadastro, tracking e
  recência são `enum`s exclusivos; tema, design system e acessibilidade existentes reutilizados.
- **Dados/segurança — PASS**: tipo de conta vem de RPC autoritativa (já existente), nunca de
  metadata mutável; owner é derivado de `auth.uid()` no servidor; mutações críticas usam RPCs
  `SECURITY DEFINER` já endurecidas; RLS e Broadcast privado (já aplicados) limitam participantes;
  o dispositivo guarda somente a posição corrente em memória.
- **Qualidade proporcional — PASS**: nenhuma suíte de testes é criada. Build, verificação de schema/
  Edge Functions, permissões, RLS, concorrência, tracking em background e fluxos completos são
  validados manualmente.

O design pós-Phase 1 permanece conforme a constitution. Nenhuma tabela/RPC/Edge Function nova é
autorada neste repositório — tudo já existe e foi validado pela feature Android equivalente.

## Project Structure

### Documentation (this feature)

```text
specs/009-provider-location-accounts/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── account-provider-database.md    # já existente/compartilhado
│   ├── geocoding-edge-function.md      # já existente/compartilhado
│   ├── location-realtime.md
│   └── navigation-session.md
└── tasks.md                         # criado posteriormente por $speckit-tasks
```

### Source Code (repository root)

```text
pitgo/
├── Core/
│   ├── Account/
│   │   ├── Model/AccountContext.swift
│   │   └── Repository/AccountContextRepository.swift
│   ├── Auth/
│   │   ├── Model/AppSessionState.swift          # + casos Provider Onboarding/Ready
│   │   └── Store/SessionStore.swift
│   ├── Catalog/
│   │   ├── Model/ServiceCatalogModels.swift
│   │   └── Repository/ServiceCatalogRepository.swift
│   ├── Location/
│   │   ├── Model/DeviceLocationModels.swift
│   │   └── Repository/DeviceLocationRepository.swift   # CLLocationManager wrapper
│   ├── Navigation/{PitGoRoute.swift, UnauthenticatedRoute.swift, PitGoRootView.swift}
│   └── Network/SupabaseClientProvider.swift             # + Functions, + Realtime
└── Features/
    ├── ProviderSignUp/{Model,Repository,Views,ViewModel}/
    ├── ProviderRegistration/{Data,Model,Repository,Validation,ViewModel,Views}/   # de 007, estendido
    ├── ProviderDashboard/{Model,Repository,ViewModel,Views}/
    ├── ProviderMigration/{Data,Model,Repository,ViewModel,Views}/
    ├── ProviderMap/{Data,Model,Repository,ViewModel,Views}/         # MapLibre
    ├── ProviderTracking/{Data,Model,Repository,ViewModel}/          # CLLocationManager em background
    ├── AppointmentTracking/{Data,Model,Repository,ViewModel,Views}/
    ├── Home/{ViewModel,Views}/          # + catálogo real
    ├── Login/{ViewModel,Views}/         # de 006
    └── SignUp/{Repository,ViewModel,Views}/   # de 005

# Nenhum diretório supabase/ novo — migrations e Edge Functions continuam no repositório Android.
```

**Structure Decision**: manter o alvo único organizado por feature, serviços compartilhados em
`Core`. O cadastro empresarial existente (`007`) é evoluído no próprio grupo; não é criada uma
segunda implementação concorrente. `HomeView` passa a navegar para o mapa usando o UUID do serviço
carregado do catálogo real, em vez do `DemoServiceCatalog` (`003`).

## Complexity Tracking

Nenhuma violação da constitution foi identificada. As responsabilidades adicionais são diretamente
exigidas por autenticação de dois papéis, mapa/tracking autorizado — geocodificação, discovery e
RPCs de localização já existem e são reutilizadas sem alteração porque o backend é compartilhado.
