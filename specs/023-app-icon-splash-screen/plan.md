# Implementation Plan: Ícone do app e tela de splash

**Branch**: `023-app-icon-splash-screen` | **Date**: 2026-09-14 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/023-app-icon-splash-screen/spec.md`

## Summary

`Assets.xcassets/AppIcon.appiconset` já existe com os 3 slots exigidos pelo catálogo moderno de
ícone único (universal/escuro/tintado, todos 1024×1024) mas sem nenhuma imagem atribuída — o app
hoje usa o placeholder do Xcode. `Info.plist`'s `UILaunchScreen` está vazio (`<dict/>`) — hoje não
há splash nenhuma, só uma tela em branco no instante da abertura.

Esta feature processa as duas imagens fornecidas (fora do repositório, em `~/Pictures/`) com
ferramentas de linha de comando já disponíveis no Mac (`sips` + um script Swift/CoreGraphics de
~15 linhas só para achatar o canal alfa, já que nem ImageMagick nem PIL estão instalados) e as
integra: o ícone recortado (1024×1024, sem faixas, sem alfa) preenche os 3 slots do
`AppIcon.appiconset`; a logo do splash (já quadrada) vira um `ImageSet` novo referenciado por
`UILaunchScreen.UIImageName`, com `UILaunchScreen.UIColorName` apontando pra um `ColorSet` na cor
roxa já presente na própria imagem — nenhum código Swift novo, nenhuma dependência nova.

## Technical Context

**Language/Version**: Swift 6.0 (só para o script utilitário de processamento de imagem, descartável — nenhuma mudança de código do app em si)

**Primary Dependencies**: `sips` (CLI já disponível no macOS) para recorte/redimensionamento;
AppKit/CoreGraphics (via um script Swift avulso, não parte do target do app) só para achatar o
canal alfa do ícone — nenhuma dependência nova adicionada ao projeto Xcode

**Storage**: N/A — apenas arquivos de imagem no bundle (`Assets.xcassets`), nenhuma persistência

**Testing**: XCTest disponível no projeto; não solicitado explicitamente para esta feature (regra V
da constituição) — validação por `quickstart.md` (inspeção visual em device/simulador)

**Target Platform**: iOS 17+ (mesmo catálogo de ícone único usado por visionOS/iOS 17+, já
refletido no `Contents.json` existente)

**Project Type**: App iOS nativo (Xcode single project) — mudança restrita a assets
(`Assets.xcassets/AppIcon.appiconset`, novo `Assets.xcassets/LaunchImage.imageset`, novo
`Assets.xcassets/LaunchBackground.colorset`) e a duas chaves de `AppInfo/Info.plist`
(`UILaunchScreen.UIImageName`/`UIColorName`); nenhum arquivo `.swift` do app é alterado

**Performance Goals**: nenhum atraso adicional perceptível na abertura (SC-004) — `UILaunchScreen`
nativo é renderizado pelo próprio SpringBoard antes do processo do app sequer iniciar, então não há
custo de código a otimizar

**Constraints**: App Icon não pode ter canal alfa (rejeitado pela validação da App Store) — a
imagem de origem tem (`hasAlpha: yes`), precisa ser achatada antes de entrar no asset catalog;
nenhuma das duas imagens pode ser ampliada além da resolução de origem (FR-008)

**Scale/Scope**: 2 imagens de origem processadas em pouco mais de meia dúzia de arquivos de saída
(3 do ícone + 3 escalas do splash); 1 catálogo de assets + 1 arquivo `Info.plist` tocados

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Simplicidade/YAGNI**: PASS — usa só ferramentas de sistema já disponíveis (`sips`) e um
  script Swift avulso e descartável (não integrado ao app) para o único passo que `sips` sozinho
  não resolve (achatar alfa); nenhuma dependência nova no projeto Xcode, nenhuma abstração.
- **II. MVVM**: N/A — não há código de app envolvido, só assets estáticos e configuração de
  `Info.plist`.
- **III. Estado previsível**: N/A — sem estado de UI (o splash é renderizado pelo sistema, fora do
  ciclo de vida de qualquer View/ViewModel).
- **IV. Dados/segurança/falhas explícitas**: PASS — nenhum dado sensível envolvido; a única
  "falha" possível (imagem com alfa rejeitada pela App Store) é tratada no próprio pipeline antes
  de entrar no asset catalog, não em runtime.
- **V. Qualidade proporcional**: PASS — sem testes automatizados não solicitados; escopo
  estritamente limitado às duas imagens pedidas, sem tocar em nenhuma outra tela (`WelcomeView`
  permanece intocada, conforme Assumption do spec.md).

Nenhuma violação a justificar em Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/023-app-icon-splash-screen/
├── plan.md              # This file ($speckit-plan command output)
├── research.md          # Phase 0 output ($speckit-plan command)
├── data-model.md        # Phase 1 output ($speckit-plan command)
├── quickstart.md        # Phase 1 output ($speckit-plan command)
├── contracts/           # Phase 1 output ($speckit-plan command)
└── tasks.md             # Phase 2 output ($speckit-tasks command - NOT created by $speckit-plan)
```

### Source Code (repository root)

```text
pitgo/
├── Assets.xcassets/
│   ├── AppIcon.appiconset/
│   │   ├── Contents.json          # já existe — ganha 3 chaves "filename"
│   │   ├── AppIcon-1024.png       # NOVO — pitgo-icon.png recortado + sem alfa
│   │   ├── AppIcon-1024-dark.png  # NOVO — mesma imagem (Assumption do spec.md)
│   │   └── AppIcon-1024-tinted.png # NOVO — mesma imagem
│   ├── LaunchImage.imageset/       # NOVO
│   │   ├── Contents.json
│   │   ├── LaunchImage@1x.png      # pitgo-image1200.png reduzida (418×418)
│   │   ├── LaunchImage@2x.png      # pitgo-image1200.png reduzida (836×836)
│   │   └── LaunchImage@3x.png      # pitgo-image1200.png sem redimensionar (1254×1254)
│   └── LaunchBackground.colorset/  # NOVO — roxo amostrado da própria imagem
│       └── Contents.json
└── (AppInfo/)Info.plist            # UILaunchScreen.UIImageName/UIColorName preenchidos
```

**Structure Decision**: mudança restrita a `Assets.xcassets` (3 novos ImageSet/ColorSet + 3
arquivos preenchidos num appiconset já existente) e duas chaves de `Info.plist`. Nenhum arquivo
`.swift` é criado ou alterado — consistente com o resumo/Technical Context acima.

## Complexity Tracking

*Sem violações à Constitution Check — seção não aplicável.*
