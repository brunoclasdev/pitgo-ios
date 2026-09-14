---

description: "Task list template for feature implementation"
---

# Tasks: Ícone do app e tela de splash

**Input**: Design documents from `/specs/023-app-icon-splash-screen/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/asset-catalog-contract.md, quickstart.md

**Tests**: não solicitados explicitamente (regra V da constituição) — validação por `quickstart.md` (inspeção visual).

**Organization**: Tasks agrupadas por user story (US1 = P1 ícone, US2 = P2 splash) — totalmente independentes entre si (arquivos de origem, pastas de destino e chaves de `Info.plist` distintas).

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivos diferentes, sem dependência)
- **[Story]**: US1 ou US2
- Caminhos de arquivo exatos em cada descrição; caminhos relativos à raiz do repo
  (`/Users/brunocesar/projetos-mobile/ios/pitgo`)

---

## Phase 1: Setup

**Purpose**: Confirmar ferramentas e localizar os arquivos de origem

- [X] T001 Confirmar que `/Users/brunocesar/Pictures/pitgo-icon.png` (1536×1024) e `/Users/brunocesar/Pictures/pitgo-image1200.png` (1254×1254) existem e conferir com `sips -g pixelWidth -g pixelHeight -g hasAlpha` que as dimensões batem com `research.md`/`data-model.md`

---

## Phase 2: Foundational

**Purpose**: N/A — as duas user stories não compartilham nenhum arquivo, pasta ou pré-requisito; nenhuma tarefa bloqueante entre elas.

---

## Phase 3: User Story 1 - Ícone do app (Priority: P1) 🎯 MVP

**Goal**: Substituir o ícone placeholder pelo ícone oficial da marca, preenchendo os 3 slots já declarados em `AppIcon.appiconset`.

**Independent Test**: Instalar o app e conferir na tela inicial/busca/Configurações que o ícone é o círculo roxo com a chave inglesa, preenchendo o quadrado inteiro, sem faixas — `quickstart.md` Cenário 1.

### Implementation for User Story 1

- [X] T002 [US1] Recortar `pitgo-icon.png` para 1024×1024 com `sips -c 1024 1024 pitgo-icon.png --out <tmp>/icon-cropped.png` (recorte central — remove só os 256px de fundo preto vazio de cada lado, conforme clarificação do spec.md)
- [X] T003 [US1] Criar um script Swift avulso (CoreGraphics/ImageIO puro — `CGContext` com `CGImageAlphaInfo.noneSkipLast`, **não** `AppKit`/`NSGraphicsContext`, que produziu um PNG preto quando testado em `research.md` §3) que abre `icon-cropped.png` e grava uma cópia sem canal alfa
- [X] T004 [US1] Rodar o script de T003 e confirmar com `sips -g hasAlpha` (deve ser `no`) e abrindo a imagem resultante (deve mostrar o círculo/chave inglesa, não uma imagem em branco/preta) que o achatamento funcionou de verdade
- [X] T005 [P] [US1] Copiar o resultado de T004 três vezes para `pitgo/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`, `AppIcon-1024-dark.png` e `AppIcon-1024-tinted.png` (mesma imagem nas 3 — Assumption do spec.md, nenhuma arte alternativa fornecida)
- [X] T006 [US1] Atualizar `pitgo/Assets.xcassets/AppIcon.appiconset/Contents.json` adicionando a chave `"filename"` correspondente em cada uma das 3 entradas já existentes, conforme `contracts/asset-catalog-contract.md`
- [X] T007 [US1] Build (`xcodebuild -project pitgo.xcodeproj -scheme pitgo build`) e instalar num device/simulador; conferir visualmente o ícone na tela inicial (Cenário 1 do `quickstart.md`)

**Checkpoint**: US1 completa e testável isoladamente.

---

## Phase 4: User Story 2 - Tela de splash (Priority: P2)

**Goal**: Mostrar a logo completa do PitGo centralizada na abertura do app, via `UILaunchScreen` nativo.

**Independent Test**: Cold start do app em telas de tamanhos diferentes e conferir que a logo aparece inteira, centralizada, sem cortes — `quickstart.md` Cenário 2.

### Implementation for User Story 2

- [X] T008 [P] [US2] Gerar as 3 escalas de `pitgo-image1200.png`: copiar o original (1254×1254) como `LaunchImage@3x.png` (sem redimensionar, evita upscaling), e gerar `LaunchImage@2x.png` (836×836, `sips -z 836 836`) e `LaunchImage@1x.png` (418×418, `sips -z 418 418`)
- [X] T009 [P] [US2] Amostrar a cor de fundo roxa sólida de `pitgo-image1200.png` (ex.: `sips -g` num pixel de canto, ou inspeção do arquivo) para obter os componentes RGB exatos a usar em `LaunchBackground`
- [X] T010 [US2] Criar `pitgo/Assets.xcassets/LaunchImage.imageset/Contents.json` + as 3 imagens de T008, conforme `contracts/asset-catalog-contract.md`
- [X] T011 [US2] Criar `pitgo/Assets.xcassets/LaunchBackground.colorset/Contents.json` com a cor amostrada em T009, conforme `contracts/asset-catalog-contract.md`
- [X] T012 [US2] Atualizar `AppInfo/Info.plist`: preencher `UILaunchScreen` com `UIImageName` = `LaunchImage`, `UIColorName` = `LaunchBackground`, `UIImageRespectsSafeAreaInsets` = `false` (hoje é `<dict/>` vazio)
- [X] T013 [US2] Build, forçar cold start (remover do app switcher antes de reabrir) num device/simulador; conferir visualmente a splash (Cenário 2 do `quickstart.md`), idealmente em mais de um tamanho de tela

**Checkpoint**: US2 completa e testável isoladamente.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [X] T014 [P] Rodar o Cenário 3 do `quickstart.md` (comparar ícone/splash instalados com os arquivos originais — sem pixelização/borrão perceptível, FR-008)
- [X] T015 Conferir com `git status`/`git diff --stat` que nenhum arquivo fora de `Assets.xcassets`/`AppInfo/Info.plist` foi tocado (em particular, `WelcomeView.swift` permanece intocada — Assumption do spec.md)
- [X] T016 [P] Apagar os arquivos temporários de processamento de imagem criados fora de `Assets.xcassets` (recortes/scripts intermediários no scratchpad) — nenhum artefato de trabalho deve ficar no repositório

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: sem dependências
- **Foundational (Phase 2)**: N/A — vazia, nenhuma tarefa
- **US1 (Phase 3)**: depende só do Setup — pode começar imediatamente
- **US2 (Phase 4)**: depende só do Setup — pode começar imediatamente, em paralelo com US1 (arquivos e pastas totalmente distintos)
- **Polish (Phase 5)**: depende de US1 e US2 completas

### Dentro de cada story

- US1: T002 → T003 → T004 (sequencial, cada um usa a saída do anterior) → T005 (pode paralelizar as 3 cópias) → T006 → T007
- US2: T008 e T009 podem rodar em paralelo (fontes/saídas diferentes) → T010 e T011 (podem paralelizar entre si, cada um depende só de T008/T009 respectivamente) → T012 → T013

### Parallel Opportunities

- T002-T007 (US1) e T008-T013 (US2) podem ser feitas inteiramente em paralelo por pessoas diferentes — nenhum arquivo em comum
- Dentro de US1: as 3 cópias de T005 em paralelo
- Dentro de US2: T008/T009 em paralelo; T010/T011 em paralelo
- T014 e T016 (Polish) podem rodar em paralelo com T015

---

## Parallel Example: User Story 2

```bash
# T008 e T009 em paralelo (fontes/saídas diferentes):
Task: "Gerar as 3 escalas de pitgo-image1200.png via sips -z"
Task: "Amostrar a cor de fundo roxa de pitgo-image1200.png"

# Depois, T010 e T011 em paralelo:
Task: "Criar LaunchImage.imageset com as 3 escalas"
Task: "Criar LaunchBackground.colorset com a cor amostrada"
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Completar Phase 1 (Setup)
2. Completar Phase 3 (US1 — ícone)
3. **Parar e validar**: Cenário 1 do `quickstart.md` isoladamente
4. Demonstrar/entregar se for suficiente para essa entrega

### Incremental Delivery

1. Setup → confirma origem dos arquivos
2. US1 → ícone oficial em todo lugar (MVP demonstrável)
3. US2 → splash com a logo completa
4. Polish → confirmação de que nada fora do escopo foi tocado + limpeza de arquivos temporários
