# Implementation Plan: Criar conta de usuário (iOS)

**Branch**: `005-create-user-account` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/005-create-user-account/spec.md`

## Summary

Implementar uma `SignUpView` SwiftUI empilhada a partir da Welcome, com escolha de pessoa física ou
jurídica, nome dinâmico, e-mail, telefone, CPF/CNPJ, senha e confirmação. O `SignUpViewModel`
(`@Observable`) mantém estado imutável, validação/normalização brasileira — incluindo CNPJ
alfanumérico vigente —, foco no primeiro erro, proteção contra toque duplo e falhas tipadas. Um
`SignUpRepository` usa os produtos `Auth`/`PostgREST` do `SupabaseClient` já configurado em
`004-configure-supabase`: o signup envia metadata normalizada, o trigger transacional já existente
no backend compartilhado cria `public.profiles` com o mesmo UUID, e uma consulta/recuperação
idempotente garante o perfil antes de liberar a Home. **Nenhuma migration nova é criada** — o schema,
trigger, grants e RLS já estão aplicados e ativos no mesmo projeto Supabase usado pelo Android (ver
[research.md §0](research.md)); esta feature cobre exclusivamente o client iOS.

## Technical Context

**Language/Version**: Swift 6, modo de concorrência estrita

**Primary Dependencies**: `supabase-swift` (produtos `Auth` e `PostgREST`, adicionados ao pacote já
resolvido em `004`); SwiftUI, Foundation; nenhuma biblioteca de máscara/formulário de terceiros

**Storage**: Supabase Auth (`auth.users`) e PostgreSQL `public.profiles` — schema já existente e
compartilhado, sem migration nova; nenhuma persistência local nova (sem SwiftData/UserDefaults para
dados desta feature; sessão gerenciada pelo armazenamento padrão do `supabase-swift`)

**Testing**: build via `xcodebuild`, verificação de schema já aplicado (leitura, sem `db reset`/`db
push`) e validação manual end-to-end conforme `quickstart.md`; nenhum teste automatizado, conforme
governança atual do projeto

**Target Platform**: iOS 17+, iPhone e iPad, Debug e destino `generic/platform=iOS`

**Project Type**: aplicativo iOS nativo de alvo único, com backend Supabase compartilhado com o
projeto Android (mesmo projeto remoto, mesma tabela `profiles`)

**Performance Goals**: feedback visual em até 1 segundo após envio válido; UI responsiva sem I/O na
main thread (chamadas de rede em `Task` assíncrona); no máximo uma operação remota simultânea por
tela; uma consulta de confirmação e, só quando necessário, uma inserção idempotente de recuperação

**Constraints**: Confirm email desabilitado e senha mínima 8 já configurados no ambiente
compartilhado; exatamente CPF ou CNPJ; CNPJ numérico e alfanumérico oficial; zero senha/token/
documento completo ou `Error` bruto em logs; somente chave publishable/anon no bundle; Home somente
com sessão e perfil confirmados; RLS do próprio UUID (já aplicada); sem login visível, recuperação
de senha, login social, edição de perfil, persistência local nova ou service-role

**Scale/Scope**: uma View/rota (`.signUp` na `NavigationStack` não autenticada), dois tipos de
pessoa, seis campos de texto visíveis por vez, um Repository, um ViewModel; nenhuma tabela nova,
nenhuma migration nova

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Gate evaluation before research

- **Simplicidade e YAGNI — PASS**: o escopo cobre somente cadastro, perfil e navegação client-side.
  Login, recuperação, edição, DI framework, cache e módulos Supabase sem uso ficam fora; nenhuma
  migration nova é criada por decisão explícita (backend compartilhado).
- **iOS nativo e MVVM — PASS**: SwiftUI apenas renderiza/emite eventos; `@Observable` ViewModel
  controla estado/validação; Repository encapsula Auth/PostgREST.
- **Estado previsível — PASS**: `editing`/`submitting`/`failure`/`success` são exclusivos; um único
  campo de documento impede CPF/CNPJ simultâneos e senha não é persistida.
- **Organização por feature — PASS**: `Features/SignUp` contém Model/ViewModel/Views/Repository;
  `Core/Navigation` recebe apenas o novo caso de rota e o `RootPhase`.
- **Dados e segurança — PASS**: validação local + validação SQL já ativa (backend compartilhado),
  recuperação idempotente, chaves de cliente e erros sanitizados cobrem os riscos sem service-role
  no app iOS, replicando exatamente as garantias já auditadas no Android.
- **Design system, HIG e acessibilidade — PASS**: a View reutiliza tema/tokens existentes,
  `NavigationStack` nativo, `@FocusState`, Dynamic Type, alvos mínimos de 44pt e
  `.scrollDismissesKeyboard`.
- **Navegação — PASS**: `RootPhase` (`unauthenticated`/`home`) mantém a troca Welcome→SignUp→Home
  centralizada e descarta a pilha não autenticada no sucesso, sem exigir NavController/back stack
  manual.
- **Qualidade proporcional — PASS**: nenhum teste automatizado é criado; build/lint, verificação de
  schema existente e matriz manual são proporcionais ao risco, sem repetir trabalho de backend já
  feito pelo Android.

## Project Structure

### Documentation (this feature)

```text
specs/005-create-user-account/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── account-registration.md
│   └── profiles-schema.md          # contrato do schema já existente; nenhuma migration aqui
└── tasks.md                         # criado posteriormente por $speckit-tasks
```

### Source Code (repository root)

```text
pitgo.xcodeproj/                      # target pitgo ganha os produtos Auth/PostgREST do supabase-swift

pitgo/
├── Core/
│   ├── Navigation/
│   │   ├── PitGoRootView.swift       # RootPhase (.unauthenticated/.home), NavigationStack não autenticada
│   │   └── UnauthenticatedRoute.swift # enum Hashable com .signUp
│   └── Network/
│       └── SupabaseClientProvider.swift # inalterado; já expõe Auth/PostgREST habilitados
└── Features/
    ├── Welcome/
    │   └── Views/WelcomeView.swift   # onCreateAccount agora empurra .signUp (era no-op em 002)
    └── SignUp/
        ├── Model/
        │   ├── SignUpModels.swift        # PersonType, draft, estado, erros, RegistrationResult
        │   └── SignUpValidation.swift    # normalização, CPF/CNPJ/e-mail/telefone
        ├── Data/
        │   └── ProfileDTOs.swift          # ProfileInsertDTO/ProfileDTO Codable
        ├── Repository/
        │   └── SignUpRepository.swift     # Auth + perfil + recovery + error mapping
        └── ViewModel/
        │   └── SignUpViewModel.swift
        └── Views/
            └── SignUpView.swift            # form completo, sem TabView

pitgo.xcassets/  # ícones de olho (mostrar/ocultar senha) e voltar, se ainda não existirem de 001–004

# Nenhum diretório supabase/ novo — a migration continua vivendo apenas no repositório Android.
```

**Structure Decision**: manter o alvo único e feature-first. O Repository recebe o `SupabaseClient`
por `init`, sem framework de DI nem Use Case. Validação é feature-local; DTOs não vazam para a View.
Diferente do Android, **nenhuma pasta `supabase/` é criada neste repositório** — o schema é a mesma
fonte de verdade já versionada no repositório Android, e este plano documenta explicitamente essa
dependência cross-repo em vez de duplicá-la. `RootPhase` substitui o `NavHost`/`popUpTo` do Android
por uma troca de identidade de View no `PitGoRootView` já existente.

### Post-design constitution re-check

- `research.md` resolve módulos/versões, sessão via `supabase-swift`, fluxo híbrido trigger +
  recovery (client-side apenas), CPF/CNPJ em Swift, RLS/grants (herdados, inalterados), erros
  sanitizados, estado `@Observable`, UI/foco e `RootPhase`, sem pendências.
- `data-model.md` separa rascunho, request normalizado, metadata não confiável, identidade, perfil,
  DTOs, resultados e estados sem modelos ou campos futuros — mesma forma do Android, tipada em
  Swift.
- Os contratos fixam pré-requisitos Auth (já satisfeitos), sequência do Repository, idempotência,
  esquema exato `profiles` (já aplicado) e nomes de constraint para a allowlist de erros.
- `quickstart.md` cobre build iOS, verificação (não aplicação) do schema, PF/PJ, CNPJ legado/novo,
  validação, Dynamic Type/VoiceOver, conflitos, rede, recovery, `RootPhase` e ausência de vazamento.
- Nenhuma View acessa `SupabaseClient` diretamente; nenhum service-role, `Error` bruto em log, senha
  persistida, módulo desnecessário, teste não solicitado, migration duplicada ou permissão nova é
  introduzido.

**Resultado pós-design**: PASS. Os produtos `Auth`/`PostgREST` do `supabase-swift` e a policy INSERT
de recuperação (já existente no backend) são complexidade justificada exclusivamente pela
recuperação idempotente esclarecida no spec; não há violação constitucional.

## Complexity Tracking

Nenhuma violação constitucional requer exceção.
