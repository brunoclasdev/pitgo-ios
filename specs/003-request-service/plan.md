# Implementation Plan: Solicitar Atendimento (iOS)

**Branch**: `003-request-service` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/003-request-service/spec.md`

## Summary

Conectar os seis cards de serviço da Home a uma nova View de solicitação que recebe somente o
`DemoServiceID?`, resolve localmente nome, ícone e preço, e apresenta veículo, endereço, descrição
opcional, estimativas, pagamento exclusivo e uma ação simulada protegida contra repetição. A
implementação mantém um único alvo iOS, extrai apenas os dados e a `TabView` agora reutilizados por
duas features, usa estado imutável em `@Observable`, navegação centralizada (`NavigationStack`
dentro da aba Início) e uma UI SwiftUI rolável entre barra de navegação e barra de abas fixas, sem
Repository, backend, persistência, permissões, novos Swift Packages ou testes automatizados.

## Technical Context

**Language/Version**: Swift 6, modo de concorrência estrita

**Primary Dependencies**: Nenhuma — SwiftUI, Foundation, SF Symbols

**Storage**: N/A; catálogo, veículo e estimativas são locais, temporários e não persistidos

**Testing**: build via `xcodebuild`, seguido pelo roteiro manual de `quickstart.md`; nenhum teste
automatizado será criado

**Target Platform**: iOS 17+, iPhone e iPad

**Project Type**: aplicativo iOS nativo de alvo único

**Performance Goals**: conteúdo local disponível na primeira renderização da View; rolagem,
seleção e edição visualmente fluidas nos dispositivos suportados; um toque aceito produz feedback
no mesmo ciclo de interação

**Constraints**: SwiftUI-only, MVVM, tema existente, `TabView` fixa, conteúdo responsivo e
acessível, operação offline, sem backend, Supabase, rede, autenticação adicional, localização,
persistência, cobrança, Repository, Use Case, DI, testes ou dependências novas

**Scale/Scope**: um novo destino, seis casos de serviço, um veículo/endereço demonstrativo, três
formas de pagamento, dois estados raiz de View, dois estados de acionamento e cinco abas
demonstrativas de navegação inferior

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Gate evaluation before research

- **Simplicidade e YAGNI — PASS**: adiciona somente a View, estado, rota, recursos e extrações
  exigidas por reutilização real. Sem backend, Repository, Use Case, DI, persistência, deep link
  ou infraestrutura futura.
- **iOS nativo e MVVM — PASS**: Swift, SwiftUI, `@Observable`, `NavigationStack`/`TabView` já
  disponíveis. A View renderiza estado e emite eventos; o ViewModel resolve dados locais e
  controla descrição, pagamento e acionamento.
- **Organização por feature — PASS**: `Features/RequestService` contém apenas `Model`, `Views` e
  `ViewModel`; catálogo/veículo e `TabView` movem para `Core` somente porque passam a ter dois
  consumidores reais.
- **Estado previsível — PASS**: um `enum` separa conteúdo válido de serviço inválido; pagamento e
  acionamento usam `enum` exclusivos. `.loading`/`.empty` não são inventados.
- **Design system e HIG — PASS**: `NavigationStack`, `TextEditor`, `Button`, `TabView` e
  superfícies selecionáveis nativas preservam comportamento padrão. Tokens compartilhados
  existentes são reutilizados.
- **Tema, responsividade e acessibilidade — PASS**: a View usa os papéis Light/Dark existentes,
  respeita safe areas/teclado, permite rolagem, quebra de linha e Dynamic Type, mantém alvos
  mínimos de 44pt e representa pagamento selecionado por semântica e indicador visual além da cor.
- **Navegação — PASS**: rota e argumento ficam centralizados; somente `DemoServiceID?` é
  transportado; proteção local de toque único e back stack padrão evitam duplicação e preservam
  Home no retorno. Abas mantêm o comportamento demonstrativo atual.
- **Dados e segurança — PASS**: somente dados mockados não sensíveis; sem cartão, permissão, rede,
  segredo, log sensível ou criação de atendimento.
- **Qualidade proporcional — PASS**: nenhum teste é criado por proibição explícita; build e
  roteiro manual cobrem o risco visual, de estado e de navegação.

## Project Structure

### Documentation (this feature)

```text
specs/003-request-service/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── request-service-navigation.md
└── tasks.md                         # criado posteriormente por $speckit-tasks
```

### Source Code (repository root)

```text
pitgo/
├── Core/
│   ├── Common/Model/
│   │   ├── DemoServiceCatalog.swift   # extrair ID, modelo e catálogo dos serviços
│   │   └── DemoVehicle.swift          # extrair veículo/endereço demonstrativo
│   ├── Navigation/
│   │   ├── PitGoRoute.swift           # adicionar .requestService(serviceID:)
│   │   └── PitGoRootView.swift        # TabView com NavigationStack por aba
│   └── UI/
│       └── PitGoBottomTabs.swift      # extrair modelo/View já reutilizados por Home
└── Features/
    ├── Home/
    │   ├── Model/HomeContent.swift     # manter somente conteúdo exclusivo da Home
    │   └── Views/HomeView.swift        # propagar seleção real de serviço, usar TabView comum
    └── RequestService/
        ├── Model/RequestServiceContent.swift
        ├── ViewModel/RequestServiceViewModel.swift
        └── Views/RequestServiceView.swift

pitgo/Assets.xcassets/  # SF Symbols locais quando necessário: voltar, relógio, check
```

**Structure Decision**: manter o alvo único e feature-first. A nova feature possui uma View
stateless, um ViewModel e tipos de estado locais. `DemoServiceCatalog`, `DemoVehicle` e
`PitGoBottomTabs` deixam de pertencer exclusivamente à Home porque passam a ter dois consumidores;
a extração elimina dependência `RequestService → Home` e mantém uma fonte única de preço, veículo
e barra. Sem `Data`, Repository ou Use Case.

### Post-design constitution re-check

- `research.md` resolve todas as decisões técnicas sem pendências e sem dependências novas.
- `data-model.md` usa uma única fonte para catálogo/preço e modela conteúdo válido, ID inválido,
  pagamento exclusivo e acionamento único sem estados booleanos conflitantes.
- O contrato transporta somente `DemoServiceID?`, mantém Views desacopladas do host de navegação,
  define back seguro e preserva explicitamente a `TabView` demonstrativa da Home.
- O design mantém uma única rolagem entre barras fixas, adapta estimativas à largura/fonte via
  `ViewThatFits`, usa semântica de seleção e evita alturas rígidas que cortem texto.
- O quickstart cobre build, seis serviços/preços, ID ausente, edição/teclado, pagamento,
  acionamento único, back stack, barra fixa, temas, Dynamic Type, VoiceOver e operação offline.

**Resultado pós-design**: PASS; nenhuma violação constitucional ou complexidade que exija exceção
foi introduzida.
