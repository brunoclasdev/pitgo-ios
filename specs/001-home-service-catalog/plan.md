# Implementation Plan: Catálogo de Serviços na Homepage (iOS)

**Branch**: `001-home-service-catalog` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/001-home-service-catalog/spec.md`

**Note**: Porta a spec `001-home-service-catalog` do app Android para o app iOS nativo do mesmo
produto PitGo. O backend Supabase é compartilhado; esta feature em particular não toca nele (é
100% local), então nada muda de infraestrutura — só o app cliente.

## Summary

Converter o template padrão do Xcode (`ContentView.swift` "Hello, world") em um app SwiftUI de
alvo único e entregar uma homepage offline com cinco categorias veiculares locais. A UI usa SwiftUI
nativo, `LazyVGrid` adaptável, tema claro/escuro do sistema, acessibilidade (VoiceOver/Dynamic
Type) e um `HomeViewModel` `@Observable` com estado imutável. A seleção envia somente o
identificador estável da categoria (`ServiceCategoryID`) ao destino mínimo de entrada da busca de
prestadores, com retorno padrão do `NavigationStack` e proteção contra navegação duplicada.

Não serão adicionados Repository, Use Case, rede, persistência, Swift Package externo, DI ou
testes. Sem incompatibilidade de toolchain a corrigir (projeto novo, sem scaffold legado como no
Android) — só a substituição do conteúdo padrão do template.

## Technical Context

**Language/Version**: Swift 6 (modo de concorrência estrita), toolchain do Xcode estável mais
recente

**Primary Dependencies**: Nenhum Swift Package externo — SwiftUI, Foundation e SF Symbols do SDK
da Apple

**Storage**: N/A; catálogo imutável embutido no app, sem banco, arquivo ou preferência

**Testing**: Nenhum novo teste automatizado conforme a constituição; validação por
`xcodebuild build`, o Xcode's build-time warnings e roteiro manual do `quickstart.md`

**Target Platform**: iOS 17+; iPhone e iPad (Slide Over/Split View); app de alvo único no Xcode

**Project Type**: Aplicativo móvel iOS nativo, alvo único `pitgo`

**Performance Goals**: Conteúdo útil visível em até 2 segundos; rolagem e interação sem
travamentos perceptíveis; uma navegação por seleção

**Constraints**: Offline; sem autenticação, localização ou dados pessoais; Light/Dark pelo sistema;
Dynamic Type; alvos de toque mínimos de 44×44pt (HIG); sem dependência de cor; cinco categorias
fixas

**Scale/Scope**: Uma homepage, cinco categorias, um destino mínimo de entrada da busca e nenhum
dado de prestadores

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-design gate

- **PASS — Simplicidade/KISS/YAGNI**: um único alvo Xcode e as camadas necessárias; sem
  Repository, Use Case, DI, rede, persistência ou abstrações especulativas.
- **PASS — Stack e arquitetura**: Swift, SwiftUI, `@Observable`, `NavigationStack`; fluxo View ->
  ViewModel para dados locais sem acesso externo.
- **PASS — Organização por feature**: homepage em `Features/Home`; tema e navegação realmente
  compartilhados em `Core`.
- **PASS — Estado previsível**: `HomeUiState` imutável e sempre preenchido; Loading, Error e Empty
  não existem porque o catálogo local garante cinco itens.
- **PASS — UI/UX e acessibilidade**: componentes SwiftUI nativos, grade adaptável, design system
  central, VoiceOver, Dynamic Type, alvo de toque mínimo e identificação além de cor.
- **PASS — Segurança e dados**: a feature não solicita permissões, não coleta dados, não acessa
  rede e transmite somente um identificador interno de categoria.
- **PASS — Dependências**: nenhum Swift Package externo; SF Symbols evitam biblioteca de imagens.
- **PASS — Testes**: nenhum teste será criado sem solicitação explícita; build e validação manual
  verificam a entrega.
- **PASS — Escopo**: a fronteira de busca confirma categoria e retorno, sem simular prestadores,
  proximidade, solicitação, pagamento ou contratação.

### Post-design gate

- **PASS**: `research.md` resolve todas as decisões de stack e toolchain sem marcadores pendentes.
- **PASS**: `data-model.md` contém somente categoria, estado de UI e argumento efêmero de
  navegação; não introduz persistência.
- **PASS**: `contracts/home-navigation.md` mantém a View stateless, rotas centralizadas, argumento
  mínimo, proteção contra toques repetidos e retorno padrão.
- **PASS**: `quickstart.md` valida requisitos funcionais, responsividade, acessibilidade, temas e
  funcionamento offline sem gerar testes.

**Gate result**: aprovado antes e depois do design; nenhuma exceção constitucional necessária.

## Project Structure

### Documentation (this feature)

```text
specs/001-home-service-catalog/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── home-navigation.md
└── tasks.md                    # Criado posteriormente por $speckit-tasks
```

### Source Code (repository root)

```text
pitgo/
├── pitgoApp.swift
├── Core/
│   ├── DesignSystem/
│   │   ├── Colors.swift
│   │   ├── Typography.swift
│   │   └── PitGoTheme.swift
│   └── Navigation/
│       ├── PitGoRoute.swift
│       └── PitGoRootView.swift
└── Features/
    ├── Home/
    │   ├── Model/ServiceCategory.swift
    │   ├── ViewModel/HomeViewModel.swift
    │   └── Views/HomeView.swift
    └── Provider/
        └── Views/ProviderSearchEntryView.swift

pitgo.xcodeproj/
Assets.xcassets/ (AppIcon, AccentColor)
```

**Structure Decision**: manter um único alvo Xcode `pitgo` e organizar o código Swift por feature,
espelhando exatamente a convenção `core/`/`features/` já usada no app Android (nomes capitalizados
por convenção Swift: `Core/`, `Features/`). A implementação substitui o `ContentView.swift` padrão
do template: remove o "Hello, world" e a `Image(systemName: "globe")` de exemplo. `pitgoApp.swift`
e `Assets.xcassets` permanecem como ponto de entrada e recursos de ícone/cor de destaque.

## Complexity Tracking

Nenhuma violação constitucional requer justificativa.
