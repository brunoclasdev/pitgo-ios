# Implementation Plan: Configurar Supabase (iOS)

**Branch**: `004-configure-supabase` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/004-configure-supabase/spec.md`

## Summary

Disponibilizar um `SupabaseClient` único e compartilhado para o app iOS, configurado a partir de
`supabaseUrl`/`supabaseKey` fornecidos externamente ao repositório (Xcode Build Settings, resolvidos
via `.xcconfig` local não rastreado ou override de CI), validados antes de qualquer artefato ser
gerado por um Run Script Build Phase que rejeita valores ausentes, malformados ou administrativos
(`sb_secret_`/`service_role`) sem nunca ecoar seu conteúdo. O mesmo projeto/schema Supabase já usado
pelo app Android é reutilizado sem alteração — esta feature cobre exclusivamente a configuração do
lado cliente iOS. Sem Repository, autenticação, consulta, Storage, Realtime, Functions, UI nova ou
testes automatizados.

## Technical Context

**Language/Version**: Swift 6, modo de concorrência estrita

**Primary Dependencies**: `supabase-swift` (Swift Package Manager), somente o produto central
`Supabase` — sem `Auth`/`PostgREST`/`Storage`/`Realtime`/`Functions` isolados; sem engine HTTP
adicional (usa `URLSession` nativo)

**Storage**: N/A; nenhuma persistência local ou remota nesta feature

**Testing**: build via `xcodebuild` (positivo e matriz negativa via Run Script), seguido pelo
roteiro manual de `quickstart.md`; nenhum teste automatizado será criado

**Target Platform**: iOS 17+, iPhone e iPad, Debug e Release

**Project Type**: aplicativo iOS nativo de alvo único

**Performance Goals**: `SupabaseClientProvider.client` disponível sem I/O na inicialização; nenhuma
requisição de rede ocorre durante build ou startup

**Constraints**: sem permissão de sistema (iOS não tem equivalente a `INTERNET`), sem log ou
diagnóstico contendo a chave/URL completa, sem fallback silencioso entre fontes de configuração,
sem novo módulo funcional do Supabase, sem Repository/DI/Use Case, sem mudança visual em fluxos
existentes (Welcome → Home → RequestService)

**Scale/Scope**: dois valores de configuração, um arquivo `.xcconfig` local não rastreado, um script
de validação, duas chaves de `Info.plist`, um provider Swift com uma única propriedade

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Gate evaluation before research

- **Simplicidade e YAGNI — PASS**: adiciona somente o pacote central do SDK, o script de validação e
  o provider. Sem Repository, Use Case, DI, persistência ou infraestrutura futura.
- **iOS nativo e MVVM — PASS**: nenhuma View ou ViewModel é criada; a feature prepara apenas a
  fronteira de configuração que features futuras (com MVVM completo) consumirão.
- **Organização por feature — PASS**: `Core/Network/SupabaseClientProvider.swift` é infraestrutura
  compartilhada legítima, não pertence a uma feature específica, mesmo racional do `core/network` do
  Android.
- **Estado previsível — PASS**: não há estado de UI nesta feature; a "validação" é um gate de build,
  não um `enum` de estado de tela.
- **Design system e HIG — PASS**: nenhuma UI é adicionada ou alterada.
- **Tema, responsividade e acessibilidade — PASS**: não aplicável; nenhuma tela nova.
- **Navegação — PASS**: nenhuma rota nova; fluxos existentes permanecem intactos (SC-005).
- **Dados e segurança — PASS**: chave publishable/anon é client-safe por definição do Supabase;
  chaves administrativas são recusadas antes de chegar ao artefato de build; nenhum dado real é
  consultado.
- **Qualidade proporcional — PASS**: nenhum teste automatizado é criado por proibição explícita da
  governança atual; build positivo/negativo e roteiro manual cobrem o risco.

## Project Structure

### Documentation (this feature)

```text
specs/004-configure-supabase/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── supabase-configuration.md
└── tasks.md                         # criado posteriormente por $speckit-tasks
```

### Source Code (repository root)

```text
pitgo/
├── Config/
│   ├── Shared.xcconfig              # xcconfig base do projeto, com #include? "Secrets.xcconfig"
│   └── Secrets.xcconfig             # NÃO rastreado — supabaseUrl/supabaseKey locais
├── Scripts/
│   └── validate-supabase-config.sh  # Run Script Build Phase, roda antes de Compile Sources
├── Core/
│   └── Network/
│       └── SupabaseClientProvider.swift   # enum com static let client: SupabaseClient
└── Info.plist                       # SUPABASE_URL = $(supabaseUrl), SUPABASE_KEY = $(supabaseKey)

pitgo.xcodeproj/  # target principal ganha o Run Script Build Phase e referencia Config/Shared.xcconfig
```

**Structure Decision**: manter o alvo único. A configuração vive inteiramente em `Config/` +
`Scripts/` (mecanismo de build, não código do app) e `Core/Network/` recebe apenas a fronteira de
acesso ao cliente (`SupabaseClientProvider`), espelhando `core/network/SupabaseClientProvider.kt` do
Android. Nenhum Swift Package local, Repository ou pasta de feature é criado.

### Post-design constitution re-check

- `research.md` resolve todas as decisões técnicas (SDK, permissão, precedência, validação, geração
  de valores para o código, ownership do cliente, logs) sem pendências e sem dependências novas além
  do pacote central `supabase-swift`.
- `data-model.md` documenta o fluxo `Secrets.xcconfig`/CI → Build Settings → Run Script → `Info.plist`
  → `SupabaseClientProvider.client` sem introduzir entidade de domínio nem estado de UI.
- O contrato (`contracts/supabase-configuration.md`) define nomes canônicos, precedência de fontes,
  regras de validação idênticas ao Android (adaptadas ao mecanismo Xcode) e a fronteira única do
  provider, preservando as regras de segurança (nunca ecoar credencial, rejeitar `sb_secret_`/
  `service_role`).
- O quickstart cobre build positivo, matriz negativa, precedência de fontes, inspeção de
  Git/`.gitignore`, e regressão manual dos fluxos existentes offline.

**Resultado pós-design**: PASS; nenhuma violação constitucional ou complexidade que exija exceção foi
introduzida.
