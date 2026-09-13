# Implementation Plan: Mapa iOS em paridade de produção com o Android

**Branch**: `019-map-production-tiles` | **Date**: 2026-09-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/019-map-production-tiles/spec.md`

## Summary

Fechar a lacuna de configuração entre o mapa iOS (MapLibre Native, já funcional desde `010`) e o
Android: trocar o estilo de demonstração pública (`demotiles.maplibre.org`) pelo mesmo provedor de
tiles gerenciado que o Android já usa em produção, copiando os quatro valores (`mapStyleUrl`,
`mapStyleProviderName`, `mapStyleAttribution`, `mapStyleAttributionUrl`) do `local.properties`
Android para `Config/Secrets.xcconfig` iOS (local, não rastreado). A pesquisa (Phase 0) encontrou
que a validação de build para esses campos, prometida no contrato de `010`, nunca foi implementada
— esta feature a implementa agora, estendendo `Scripts/validate-supabase-config.sh` com a mesma
grammar de validação já especificada em `010`. Nenhuma mudança na camada de renderização do mapa
(`PitGoMapView`, já funcional) é necessária.

## Technical Context

**Language/Version**: Swift 6 (Run Script Build Phase em `sh` POSIX, mesmo shell de `004`)

**Primary Dependencies**: nenhuma nova. MapLibre Native iOS (`010`, inalterado);
`ManagedMapStyleConfiguration` (`010`, sem mudança de comportamento, só de comentário desatualizado)

**Storage**: N/A — configuração de build (`Config/Shared.xcconfig`/`Config/Secrets.xcconfig`),
sem persistência em runtime

**Testing**: build via `xcodebuild` com e sem `Config/Secrets.xcconfig` presente, para exercitar os
caminhos de sucesso/falha do Run Script; validação manual comparativa com o app Android via
`quickstart.md`; nenhum teste automatizado, conforme governança do projeto

**Target Platform**: iOS 17+, todas as configurações de build (Debug e Release, sem distinção —
mesmo padrão do Android, que aplica o valor em `defaultConfig` para todos os build types)

**Project Type**: aplicativo iOS nativo de alvo único, com backend Supabase compartilhado com o
Android (config de mapa também compartilhada, mas por cópia de valor local, não por código)

**Performance Goals**: nenhum novo — herda os alvos já definidos em `010` (mapa/resultados em até
3s p95); esta feature não muda o caminho de rendering, só a origem dos tiles

**Constraints**: credencial de produção NUNCA entra no controle de versão (constitution,
Restrições Técnicas); build DEVE falhar citando o campo específico, nunca aceitar silenciosamente
um host demo/público ou valor ausente; nenhuma outra dependência de mapa introduzida

**Scale/Scope**: um único Run Script Build Phase estendido (2 seções: Supabase existente + mapa
novo); quatro valores de configuração local trocados; nenhuma tela ou fluxo novo

## Constitution Check

*GATE inicial e pós-design: aprovado sem exceções.*

- **Simplicidade/YAGNI — PASS**: reaproveita o único Run Script Build Phase existente (uma segunda
  seção/função no mesmo arquivo, espelhando a estrutura de duas funções já usada no
  `build.gradle.kts` Android) em vez de criar um segundo mecanismo. Nenhuma camada, abstração ou
  dependência nova.
- **iOS nativo/MVVM — PASS**: não há View, ViewModel ou Repository nesta feature — é configuração
  de build e um script de validação, fora da árvore MVVM.
- **Estado/UX — PASS**: nenhum estado de UI novo; a UI já trata loading/erro/degradado do mapa
  desde `010` e continua inalterada.
- **Dados/segurança — PASS**: FR-004 e a constitution (Restrições Técnicas — "segredos de build...
  DEVEM vir de configuração de build não versionada") são atendidos da mesma forma que Supabase
  (`004`) e Mercado Pago (`018`) — valor real só em `Config/Secrets.xcconfig`, nunca commitado,
  nunca logado.
- **Qualidade proporcional — PASS**: o script estendido segue o mesmo estilo (`fail`, `trim`, sem
  ecoar valores) já estabelecido em `Scripts/validate-supabase-config.sh`; nenhum teste automatizado
  criado, conforme a governança.

O design pós-Phase 1 mantém o gate aprovado. Nenhuma exceção a registrar em Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/019-map-production-tiles/
├── plan.md              # este arquivo
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   └── map-style-build-validation.md
└── tasks.md              # criado posteriormente por $speckit-tasks
```

### Source Code (repository root)

```text
Scripts/
└── validate-supabase-config.sh   # ESTENDIDO: nova seção/função de validação do mapa

Config/
└── Secrets.xcconfig               # local, não rastreado — recebe os 4 valores reais (cópia do
                                    # local.properties Android, com correção de encoding)

pitgo/Core/Map/Config/
└── ManagedMapStyleConfiguration.swift   # comentário desatualizado corrigido; nenhuma mudança de
                                          # comportamento (fallback defensivo permanece como rede de
                                          # segurança em tempo de execução, não substitui o gate de
                                          # build)
```

**Structure Decision**: nenhuma estrutura nova. O único arquivo de produção editado é
`Scripts/validate-supabase-config.sh` (mais o comentário em `ManagedMapStyleConfiguration.swift`);
`Config/Secrets.xcconfig` é configuração local, não código versionado.

## Complexity Tracking

Nenhuma violação constitucional. Estender o script existente (em vez de criar um segundo Run
Script Build Phase) é a opção de menor complexidade que ainda atende ao requisito, mesma estrutura
de duas seções de validação já usada no `build.gradle.kts` do Android.
