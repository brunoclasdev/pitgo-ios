# Implementation Plan: Experiência mockada de UI do PitTec (iOS)

**Branch**: `017-pittec-mocked-ui` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/017-pittec-mocked-ui/spec.md`

## Summary

Entregar um protótipo navegável e inteiramente local da jornada PitTec no client iOS. No perfil
prestador, a Home passa a ter mapa com a localização real do dispositivo, solicitação destacada por
três pulsos roxos, aceite/recusa, acompanhamento e navegação inferior com Mapa, Dados da corrida,
Valores e Perfil. No perfil cliente, a tela existente permanece igual até "Buscar PitTec"; depois
exibe uma estimativa de R$ 50,00 mais R$ 10,00 por faixa de 5km, confirmação, busca sequencial
simulada, acompanhamento e confirmações bilaterais simuladas.

A implementação mantém autenticação, catálogo e mapa existentes, mas isola o protótipo dos RPCs,
Realtime, tracking publicado, rotas externas e pagamentos reais (`013`/`015`). Dois `@Observable`
ViewModels independentes, escopados acima das rotas e identificados pela sessão autenticada, mantêm
as máquinas de estado somente em memória. `Task`s controlam as respostas automáticas de 3s, a
posição simulada de 30s e a indicação de desatualização após 35s. O mapa reutiliza MapLibre Native
iOS e os modelos atuais (`010`); a câmera recebe comando apenas na abertura do acompanhamento e no
botão "Centralizar", preservando qualquer exploração manual.

## Technical Context

**Language/Version**: Swift 6, modo de concorrência estrita

**Primary Dependencies**: SwiftUI, MapLibre Native iOS (`010`), `CoreLocation` (`009`). Nenhuma
dependência nova.

**Storage**: nenhum armazenamento novo; estado mockado exclusivamente em memória nos ViewModels,
sem Supabase, `SwiftData`, `UserDefaults` ou persistência de qualquer tipo

**Testing**: validação manual orientada pelos cenários, build via `xcodebuild`; nenhum teste
automatizado será criado porque não foi solicitado

**Target Platform**: iOS 17+, iPhone e iPad

**Project Type**: aplicativo iOS nativo de módulo único, organizado por feature

**Performance Goals**: Home PitTec pronta em até 3s quando houver fix recente; aceite abre o
acompanhamento em até 2s; exatamente uma atualização simulada por intervalo de 28–32s enquanto o
mapa do atendimento estiver ativo; resposta automática bilateral em aproximadamente 3s; mapa
permanece responsivo nos dispositivos suportados

**Constraints**: posição inicial do prestador deve ser real e precisa; sem fallback de localização
mockada na Home do prestador; três pulsos em no máximo 3s com variante estática quando redução de
movimento estiver ativa; preço em centavos inteiros (`Int`); perímetros múltiplos de 5km; stale em
35s; fluxos cliente/prestador independentes; nenhum efeito real de despacho, publicação de posição,
notificação, rota ou pagamento

**Scale/Scope**: duas jornadas mockadas por perfil, um shell PitTec provider com quatro abas, uma
máquina de estado de busca, uma máquina de atendimento compartilhável na UI, fixtures
determinísticas para 5/10/15km e busca vazia, sem alterações em backend

## Constitution Check

*GATE inicial e pós-design: aprovado sem exceções.*

- **Simplicidade/YAGNI — PASS**: protótipo local, sem backend novo, feature flag remota ou
  persistência especulativa. Dois ViewModels independentes e Views stateless cobrem apenas os
  fluxos solicitados; fixtures e temporizadores têm uso atual.
- **iOS nativo/MVVM — PASS**: SwiftUI, `@Observable`, `NavigationStack`/`TabView`, Swift
  Concurrency já são o padrão do app. Views emitem eventos, ViewModels controlam estado; não há
  Repository porque não existe acesso a dados externo/persistente nesta feature.
- **Estado/UX — PASS**: estados exclusivos, `TabView` e feedback textual estão previstos; contratos
  definem máquinas de estado, idempotência, Live Regions, alvos de toque, rolagem e alternativa sem
  movimento.
- **Dados/segurança — PASS**: nenhum segredo ou dado externo novo; permissão, GPS, timeout e
  ausência de fix são explícitos. O desenho desconecta restauração, tracking, alertas e despacho
  reais; valores usam centavos e localização não é registrada nem publicada.
- **Qualidade proporcional — PASS**: reutiliza mapa, localização e design system; sem dependência ou
  teste não solicitado. O fluxo real de `013`/`015` fica preservado, porém sem wiring no protótipo.

## Design Decisions

1. O protótipo usa `PitTecClientMockViewModel` e `PitTecProviderMockViewModel` independentes,
   instanciados acima das rotas e chaveados pela sessão. Não há sincronização entre perfis.
2. A rota cliente `PitGoRoute.pitTec(serviceID:)` deixa de criar o Repository real e não empurra
   `AppointmentTrackingView` real. O `DispatchResumeCoordinator` PitTec (`015`) e seu
   redirecionamento global deixam de ser compostos durante o protótipo; as classes de `013`/`015`
   permanecem no código.
3. Para providers cujo modo efetivo é `.pittec`, `PitGoRootView` renderiza um shell mockado e não
   cria `ProviderDashboardViewModel` real. FIXED e MOBILE continuam no Dashboard real atual.
4. O `ProviderLocationTracker` (`009`/`013`) real passa a iniciar tracking somente para MOBILE. Uma
   parada exclusivamente local encerra eventual tracking PitTec legado e seus alertas sem chamar
   Supabase nem mudar a disponibilidade remota.
5. A localização real do prestador é lida por `DeviceLocationRepository` somente enquanto a Home
   mockada está visível. O mapa não é composto antes do estado `.ready`; permissão, precisão
   insuficiente, serviços desligados e timeout têm Views e ações próprias.
6. A busca do cliente usa fixtures determinísticas com candidatos ordenados. A fixture principal
   recusa candidatos em 5 e 10km e aceita em 15km; uma tentativa posterior cobre esgotamento. Cada
   expansão atualiza imediatamente a composição do valor sem criar nova busca ou exigir nova
   confirmação.
7. Dinheiro é representado em centavos (`Int`): `5000 + 1000 × (perimeterKm / 5)`. Distância do mapa
   é uma estimativa local entre pontos simulados; não existe cálculo de rota, cobrança ou saldo.
8. Após o aceite, a primeira câmera enquadra os dois participantes. Ticks de posição alteram apenas
   marcador, distância e timestamp; somente "Centralizar" gera novo comando de câmera.
9. A animação é um efeito visual finito, consumido uma única vez por revisão da solicitação. Se
   `UIAccessibility.isReduceMotionEnabled`, a UI pula o efeito e mostra diretamente o card roxo
   persistente, sempre com texto e botões acessíveis.

Detalhes, fontes e alternativas em [research.md](research.md).

## Project Structure

### Documentation (this feature)

```text
specs/017-pittec-mocked-ui/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── client-pittec-ui.md
│   ├── mock-appointment-state.md
│   └── provider-pittec-ui.md
└── tasks.md                         # criado posteriormente por $speckit-tasks
```

### Source Code (repository root)

```text
pitgo/
├── Core/
│   ├── Map/{Model,UI}/                              # 010, reutilizado sem nova câmera automática
│   ├── Navigation/PitGoRootView.swift                 # wiring mock e isolamento do fluxo real
│   └── UI/PitGoBottomTabs.swift                       # variante PitTecProviderTabs
└── Features/
    ├── AppointmentTracking/Views/AppointmentMapCoordinator.swift  # promovido/reutilizado (014)
    ├── PitTec/
    │   ├── Model/
    │   │   ├── PitTecModels.swift          # contratos reais preservados (015)
    │   │   └── PitTecMockModels.swift      # estados/fixtures/valor/atendimento locais
    │   ├── Views/
    │   │   ├── PitTecView.swift             # apresentação inicial preservada + fluxo mock cliente
    │   │   ├── PitTecMockComponents.swift   # estimativa, busca e confirmações stateless
    │   │   ├── PitTecMockTrackingContent.swift  # mapa/card compartilhado pelos perfis
    │   │   └── PitTecProviderMockView.swift # shell de quatro abas
    │   └── ViewModel/
    │       ├── PitTecClientMockViewModel.swift
    │       └── PitTecProviderMockViewModel.swift
    └── ProviderTracking/
        ├── Repository/ProviderTrackingStateRepository.swift  # parada local sem backend
        └── ProviderLocationTracker.swift                       # nova ação local-only

# Nenhuma migration/Edge Function — feature inteiramente client-side.
```

**Structure Decision**: manter o alvo único e concentrar as duas experiências na feature `PitTec`,
que representa o mesmo produto nos dois perfis. O Dashboard real continua responsável por FIXED/
MOBILE. O `Coordinator` de mapa de participantes é reutilizado de `Core/Map`/`AppointmentTracking`
porque terá dois consumidores reais. Nenhuma pasta `Data`/`Repository` é criada para o mock; as
fixtures são valores de domínio locais e o estado permanece nos ViewModels.

## Complexity Tracking

Nenhuma violação constitucional foi identificada.
