# Implementation Plan: Layouts iniciais do PitGo (iOS)

**Branch**: `002-initial-layouts` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/002-initial-layouts/spec.md`

## Summary

Substituir a homepage de `001` por uma experiência local de duas telas: uma Welcome rolável com
identidade roxa fixa e uma Home responsiva com dados demonstrativos, seis serviços em duas colunas
e barra inferior nativa fixa (`TabView`). O fluxo ativo será apenas Welcome → Home; todos os
demais controles fornecerão feedback visual sem mudar de destino. A implementação reutiliza o alvo
único, o design system e as dependências atuais (nenhuma), mantém MVVM com estados imutáveis em
`@Observable` e remove o fluxo de busca de prestadores de `001`, que se tornou incompatível com a
nova especificação.

## Technical Context

**Language/Version**: Swift 6, modo de concorrência estrita

**Primary Dependencies**: Nenhuma — SwiftUI, Foundation e SF Symbols do SDK da Apple

**Storage**: N/A; todo o conteúdo é local, fixo e não persistido

**Testing**: build via `xcodebuild`, seguido pelo roteiro manual de `quickstart.md`; nenhum teste
automatizado será criado

**Target Platform**: iOS 17+, iPhone e iPad

**Project Type**: aplicativo iOS nativo de alvo único

**Performance Goals**: conteúdo útil da Welcome em até 2 segundos em condições normais e
interações/rolagem visualmente fluidas nos dispositivos suportados

**Constraints**: telas SwiftUI-only, MVVM, offline, sem backend, Supabase, rede, autenticação,
localização, persistência, DI, imagens remotas, telas adicionais ou novas dependências

**Scale/Scope**: dois destinos, três benefícios, um perfil/veículo/endereço demonstrativo, um card
de diagnóstico, seis serviços e cinco itens de navegação inferior

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Gate evaluation before research

- **Simplicidade/YAGNI — PASS**: alvo único, sem Repository, Use Case, DI, rede, persistência,
  backend ou destinos sem comportamento solicitado.
- **iOS nativo e MVVM — PASS**: Swift, SwiftUI, `@Observable`, `TabView`/`NavigationStack` já
  disponíveis nativamente. Welcome e Home expõem estado imutável e Views stateless.
- **Organização por feature — PASS**: Welcome recebe seu próprio grupo; Home reutiliza o grupo
  existente de `001`; design system e navegação continuam em `Core`.
- **Estado previsível — PASS**: dados fixos entram imediatamente em estados de sucesso. Loading,
  Error e Empty não são modelados porque não podem ocorrer sem fonte externa.
- **Design system e HIG — PASS**: cores, tipografia, espaçamento e elevação são centralizados;
  `Button`, `TabView` e componentes nativos fornecem interação e feedback.
- **Temas e acessibilidade — PASS**: Welcome conserva o gradiente nos dois modos; Home usa
  `colorScheme` do sistema. Conteúdo rola, aceita Dynamic Type, respeita safe areas, possui alvos
  mínimos de 44pt e não comunica estado somente por cor.
- **Navegação — PASS**: uma única flag local evita duplicação de Home (ver `research.md` §9); a
  pilha lógica é sempre `[Welcome, Home]`.
- **Dados e segurança — PASS**: somente dados demonstrativos não sensíveis; sem permissões,
  credenciais, logs sensíveis ou integrações.
- **Qualidade proporcional — PASS**: não serão criados testes por proibição explícita do usuário e
  da constituição; build e validação manual são proporcionais ao risco visual.

## Project Structure

### Documentation (this feature)

```text
specs/002-initial-layouts/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── initial-ui-navigation.md
└── tasks.md                         # criado posteriormente por $speckit-tasks
```

### Source Code (repository root)

```text
pitgo/
├── pitgoApp.swift
├── Core/
│   ├── DesignSystem/
│   │   ├── Colors.swift              # atualizar identidade e esquemas
│   │   ├── Typography.swift          # estender estilos realmente usados
│   │   └── PitGoTheme.swift          # Home claro/escuro do sistema
│   └── Navigation/
│       └── PitGoRootView.swift       # Welcome inicial e fluxo Entrar
└── Features/
    ├── Welcome/
    │   ├── Model/WelcomeBenefit.swift
    │   ├── ViewModel/WelcomeViewModel.swift
    │   └── Views/WelcomeView.swift
    └── Home/
        ├── Model/HomeContent.swift    # substitui ServiceCategory.swift de 001
        ├── ViewModel/HomeViewModel.swift
        └── Views/HomeView.swift       # substitui a grade de categorias de 001

# Removido por ter sido supersedido:
pitgo/Features/Provider/Views/ProviderSearchEntryView.swift
pitgo/Features/Home/Model/ServiceCategory.swift
pitgo/Core/Navigation/PitGoRoute.swift  # sem mais destinos a centralizar nesta feature
```

**Structure Decision**: manter o alvo único e feature-first. `WelcomeViewModel` representa a lista
ordenada de benefícios e `HomeViewModel` agrega todo o conteúdo demonstrativo da Home; ambos
expõem um único estado imutável. Sem camadas `Repository`/`UseCase`, pois não existe fonte de
dados nem regra de negócio. Componentes como `BenefitCard`, `VehicleCard`, `DiagnosticCard` e
`ServiceCard` permanecem privados à `HomeView`/`WelcomeView` até existir reutilização real.

### Post-design constitution re-check

- `research.md` resolve todas as escolhas técnicas sem novas dependências ou clarificações.
- `data-model.md` contém somente entidades demonstrativas e invariantes exigidos.
- O contrato de UI mantém Views desacopladas do host de navegação, sem argumento entre Welcome e
  Home.
- O quickstart cobre build, conteúdo offline, responsividade, temas, acessibilidade, feedback,
  safe areas, proteção contra duplicação/reentrada e retorno.

**Resultado pós-design**: PASS; nenhuma violação constitucional nova ou complexidade que exija
exceção foi introduzida.
