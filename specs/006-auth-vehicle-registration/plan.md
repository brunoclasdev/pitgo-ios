# Implementation Plan: Sessão autenticada e cadastro de veículos (iOS)

**Branch**: `006-auth-vehicle-registration` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/006-auth-vehicle-registration/spec.md`

## Summary

Implementar autenticação real por e-mail/senha, restauração e encerramento de sessão com uma única
máquina de estados (`SessionStore`, `@Observable`) que bloqueia qualquer conteúdo privado até
validar identidade e perfil. Substituir os dados demonstrativos da Home por um snapshot autorizado
de `profiles` e do veículo ativo principal. Persistir a decisão pós-cadastro por usuário com
`UserDefaults` e oferecer convite, Garagem (aba já reservada desde `002`), formulário completo de
veículo e Perfil (aba já reservada) em SwiftUI.

O acesso remoto usa os produtos `Auth`/`PostgREST` do `supabase-swift` já habilitados em `005`.
Leituras usam RLS e filtros explícitos; criação de veículo e troca de principal usam as RPCs
PostgreSQL transacionais **já existentes e compartilhadas com o Android**
(`create_vehicle`/`set_primary_vehicle`) — nenhuma migration nova é criada por esta feature iOS.

## Technical Context

**Language/Version**: Swift 6, modo de concorrência estrita

**Primary Dependencies**: `supabase-swift` (produtos `Auth`/`PostgREST`, já resolvidos em `004`/`005`);
SwiftUI, Foundation; nenhuma biblioteca de imagem assíncrona de terceiros (`AsyncImage` nativo cobre
o avatar, ver `research.md §8`); nenhum framework de DI

**Storage**: Supabase Auth (sessão gerida pelo SDK, tipicamente via Keychain) e PostgreSQL
`public.profiles`/`public.vehicles` (schema e RPCs já existentes e compartilhados com o Android); um
`UserDefaults` contendo o conjunto de `userID`s com onboarding de veículo pendente; nenhum
`SwiftData`, cache de veículo ou rascunho persistido

**Testing**: build via `xcodebuild`, verificação (não aplicação) do schema compartilhado e validação
manual end-to-end/segurança/acessibilidade documentada em `quickstart.md`; nenhum teste automatizado,
conforme governança do projeto

**Target Platform**: iOS 17+, iPhone e iPad, Debug e destino `generic/platform=iOS`

**Project Type**: aplicativo iOS nativo de alvo único, com backend Supabase compartilhado com o
projeto Android (mesmo projeto remoto, mesmas tabelas `profiles`/`vehicles`, mesmas RPCs)

**Performance Goals**: 95% das aberturas autenticadas em rede normal mostram os dados corretos da
Home em até dois segundos; rolagem SwiftUI fluida; uma única sequência de bootstrap por transição de
sessão; nenhuma requisição repetida por recomposição de View

**Constraints**: nenhum conteúdo privado antes da validação; sessão offline armazenada é preservada,
mas a Home fica oculta; nenhum reparo automático de perfil; nenhum log de token/valor sensível;
nenhum `userID` vindo de UI/navegação; mutação de veículo principal é atômica (garantida pelo
backend); rascunho descartado na expiração de sessão; schema remoto já existe e não deve ser
duplicado ou recriado

**Scale/Scope**: um alvo iOS, um projeto Supabase compartilhado, seis novas superfícies
autenticadas/públicas (session gate, login, decisão de onboarding, Garagem, formulário de veículo,
Perfil), um refactor da Home personalizada, duas RPCs já existentes, nenhuma migration nova; listas
pessoais de veículo limitadas a um prático máximo de 100 linhas sem paginação nesta entrega

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after Phase 1 design.*

### Pre-research gate

| Principle/gate | Status | Evidence |
|---|---|---|
| Simplicidade/YAGNI | PASS | Reutiliza o cliente Supabase e o design system existentes; adiciona apenas `UserDefaults` para a preferência exigida e `AsyncImage` nativo para o avatar — nenhuma dependência nova é introduzida. |
| iOS nativo e MVVM | PASS | Views SwiftUI emitem eventos a ViewModels `@Observable`; ViewModels usam Repositories; nenhuma lógica de rede na View. |
| Estado previsível | PASS | Estado raiz de sessão e cada tela usam `enum`s exclusivos; `TabView` fixa reutilizada de `002`; componentes nativos/tokens existentes reutilizados. |
| Dados/segurança/falhas | PASS | Sessão central, RLS, grants mínimos (já aplicados), RPCs transacionais (já existentes), validação local+servidor, erros sanitizados, nenhum owner/token/documento em navegação ou logs. |
| Qualidade proporcional | PASS | Nenhum teste automatizado por não ter sido solicitado; build/verificação de schema/validação manual proporcionais ao risco; nenhum framework de DI, cache ou refactor não relacionado. |
| Navegação | PASS | Rotas centralizadas em `PitGoRoute`/`UnauthenticatedRoute`; transição de sessão limpa corretamente as pilhas privada/pública; comportamento de Voltar especificado. |
| Persistência | PASS | `UserDefaults` é usado somente para a preferência simples de onboarding pendente; nenhum cache ou rascunho sensível persistido. |

Nenhuma violação constitucional exige exceção.

### Post-design re-evaluation

| Design concern | Status | Resolution |
|---|---|---|
| Fronteiras de Repository | PASS | O acesso ao SDK Auth é centralizado em `SessionStore`; responsabilidades de sessão/conta/veículo têm consumidores demonstrados e nenhum Use Case pass-through. |
| Dependências adicionais | PASS | Nenhuma dependência nova é adicionada nesta feature (nem imagem assíncrona, nem DI). |
| RPCs `SECURITY DEFINER` | PASS | Já existentes/revisadas no repositório Android; reutilizadas sem alteração porque o schema é compartilhado. |
| Armazenamento de sessão | PASS | Usa o ciclo de vida/rotação do SDK; removido localmente no logout; item de Keychain verificado/ajustado para não sincronizar entre dispositivos (ver `research.md §9`); o app nunca manipula o valor do token. |
| Estado sensível de UI | PASS | Senha e rascunho de veículo ficam em memória e são limpos em falha remota/perda de sessão; snapshots privados existem somente em `.authenticated`. |
| Divergência de schema remoto | PASS | Nenhuma — o schema já foi reconciliado pelo Android; o iOS apenas verifica, nunca aplica. |

A fase 1 de design não introduz nova falha de gate.

## Project Structure

### Documentation (this feature)

```text
specs/006-auth-vehicle-registration/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── navigation.md
│   └── supabase.md                  # contrato do schema/RPCs já existentes; nenhuma migration aqui
└── tasks.md                         # criado posteriormente por $speckit-tasks
```

### Source Code (repository root)

```text
pitgo/
├── pitgoApp.swift                    # @State private var sessionStore = SessionStore(); .environment(sessionStore)
├── Core/
│   ├── Navigation/
│   │   ├── PitGoRootView.swift       # switch em AppSessionState; monta NavigationStack pública, VehicleOnboardingView ou TabView
│   │   ├── UnauthenticatedRoute.swift # .signUp (de 005) + .login
│   │   └── PitGoBottomTabs.swift     # inalterado; Garagem/Perfil passam a navegar de fato
│   ├── Account/
│   │   ├── Model/AccountModels.swift      # Profile, AccountSnapshot
│   │   └── Repository/AccountRepository.swift
│   ├── Auth/
│   │   ├── Model/AppSessionState.swift
│   │   ├── Store/SessionStore.swift       # @Observable, @MainActor
│   │   └── Repository/SessionRepository.swift (ou lógica direto no SessionStore)
│   ├── Network/SupabaseClientProvider.swift  # inalterado
│   ├── Preferences/VehicleOnboardingStore.swift  # UserDefaults, Set<UUID> pendente
│   └── Vehicle/
│       ├── Model/VehicleModels.swift      # Vehicle, VehicleDraft, VehicleField/Error
│       ├── Repository/VehicleRepository.swift
│       └── Validation/VehicleValidation.swift
└── Features/
    ├── Session/Views/SessionGateView.swift
    ├── Login/
    │   ├── Model/LoginModels.swift
    │   ├── ViewModel/LoginViewModel.swift
    │   └── Views/LoginView.swift
    ├── Onboarding/
    │   ├── ViewModel/VehicleOnboardingViewModel.swift
    │   └── Views/VehicleOnboardingView.swift
    ├── Garage/
    │   ├── Model/GarageUiModels.swift
    │   ├── ViewModel/GarageViewModel.swift
    │   ├── ViewModel/VehicleFormViewModel.swift
    │   └── Views/GarageView.swift, VehicleFormView.swift
    ├── Profile/Views/ProfileView.swift
    ├── Home/
    │   ├── Model/HomeContent.swift       # remove modelos demonstrativos
    │   ├── ViewModel/HomeViewModel.swift
    │   └── Views/HomeView.swift
    └── SignUp/  # de 005; Repository ajustado para não fazer upsert e para marcar onboarding pendente

# Nenhum diretório supabase/ novo — a migration continua vivendo apenas no repositório Android.
```

**Structure Decision**: manter o alvo único e feature-first. `Account`/`Auth`/`Vehicle` vão para
`Core` porque são consumidos por múltiplas Features; estados e componentes exclusivamente visuais
permanecem em cada Feature. `pitgoApp.swift` cria `SessionStore` uma única vez por processo e o
injeta via `Environment` — o equivalente iOS ao `PitGoApplication`/`PitGoAppContainer` do Android,
sem framework de DI. Diferente do Android, **nenhum diretório `supabase/` é criado neste
repositório**.

## Implementation Design

### Session composition and lifecycle

1. `pitgoApp.swift` cria `SessionStore` uma vez por processo, a partir do `SupabaseClientProvider`
   singleton, e o injeta via `.environment(sessionStore)`.
2. `PitGoRootView` observa somente `SessionStore.state` (`AppSessionState`) mais ações de
   retry/logout.
3. `SessionStore.initialize()` aguarda o armazenamento do SDK, verifica remotamente o usuário Auth
   atual, carrega perfil e veículo principal, e emite um único estado exclusivo.
4. Login delega à mesma instância; o cadastro (`005`) usa a mesma fronteira Auth, mas só ativa o
   estado de sessão após confirmação de perfil e persistência bem-sucedida do onboarding pendente.
5. Perda de sessão do SDK limpa o snapshot antes que a navegação raiz remova destinos privados.

### Account and Home

1. `AccountRepository` decodifica uma projeção estreita de perfil e a projeção do principal ativo.
2. Dado de perfil inconsistente mapeia para `.profileBlocked(.inconsistent)`, não uma exceção de
   decodificação exibida à UI.
3. `HomeViewModel` combina o snapshot autenticado com o catálogo de serviços inalterado e recarrega
   a conta quando a Home volta ao topo após uma mutação na Garagem.
4. `HomeView` substitui cabeçalho/veículo/localização demonstrativos por perfil, avatar/iniciais,
   principal real ou um estado acionável sem veículo, e endereço neutro.

### Login/signup/onboarding

1. `LoginViewModel` mantém e-mail normalizado (trim + lowercase) e senha em memória, valida
   localmente, serializa o envio e mapeia falhas sanitizadas.
2. O cadastro existente (`005`) mantém seu formulário/validação, mas não faz mais upsert de perfil
   ausente; a recuperação apenas reconfirma o perfil criado pelo trigger.
3. Antes do sucesso do cadastro, `VehicleOnboardingStore.markPending(userID)` deve completar.
4. A navegação raiz consulta o estado pendente após todo bootstrap autenticado.
5. Qualquer escolha do onboarding resolve a preferência primeiro; o cadastro abre o formulário de
   veículo compartilhado com apenas um argumento de origem não sensível.

### Garage and vehicle form

1. `VehicleRepository` lista linhas ativas próprias explícitas e invoca somente as duas RPCs para
   mutações.
2. Estados de lista/vazio/erro da Garagem são exclusivos e atualizam o principal retornado
   imediatamente.
3. O formulário de veículo mantém campos brutos em memória, gera um `VehicleDraft` normalizado no
   submit, foca o primeiro erro local e desabilita eventos duplicados durante o envio.
4. As decisões de primeiro-principal e principal-posterior são de responsabilidade do servidor; o
   iOS nunca envia `user_id`, `active` ou `is_primary` final.
5. Perda de sessão limpa o estado do formulário e a pilha privada, sem caminho de salvar/restaurar.

### Database (no migration authored here)

Nenhuma etapa de migration pertence a este plano. A verificação (leitura) do schema já reconciliado
está descrita em `quickstart.md` e `research.md §10`.

## Complexity Tracking

Nenhuma violação constitucional ou complexidade excepcional está presente. `SessionStore`, os
Repositories e a reutilização das RPCs já existentes têm múltiplos consumidores atuais ou impõem um
requisito de segurança/atomicidade declarado; nenhuma alternativa mais simples satisfaz o mesmo
contrato.
