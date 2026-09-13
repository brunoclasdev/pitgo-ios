# Contract: Mapa do PitTec centralizado no cliente (iOS)

Este contrato **refina** a tabela "Map presentation" de
`specs/015-pittec-on-demand/contracts/pittec-routing-ui.md`, cuja linha "descoberta" já prometia
"cliente exato (self)" mas nunca chegou a ser implementada dessa forma. Nenhuma RPC, Edge Function
ou schema muda — é um contrato de comportamento de UI (`PitGoMapView` + `PitTecClientView`).

## Estados afetados

| Estado (`PitTecClientUiState` / `ServiceSearchStatus`) | `centerCoordinate` | `showsUserLocation` | `annotations` | Mensagem |
|---|---|---|---|---|
| `.discovering([])` (nenhum PitTec elegível) | posição do cliente (`viewModel.lastFix`) | `true` | vazio | nenhuma *(revisado — a descoberta não informa proativamente disponibilidade)* |
| `.discovering([marcadores])` (≥1 PitTec elegível) | posição do cliente | `true` | marcadores aproximados de PitTec (`symbolName: "wrench.and.screwdriver.fill"`) | nenhuma *(revisado — contagem removida pelo mesmo motivo acima)* |
| `.terminal(snapshot)`, `status == .exhausted` | posição do cliente | `true` | vazio | mensagem de busca esgotada + ações "Buscar novamente"/"Voltar", sobrepostas ao mapa |

## Estados explicitamente fora deste contrato (inalterados)

- `.locationRequired` (permissão negada/desativada, timeout): continua bloqueado, sem mapa — a
  ausência de um fix válido é pré-condição para todo este contrato.
- `.content`/aceito (`.accepted`/`.inProgress`): já centraliza corretamente via `routeContext`
  (cliente + PitTec exatos, linha estimada) — inalterado.
- `.terminal(snapshot)` com `status == .completed` ou `.cancelled`: permanece tela só-texto.
- `.failure`, `.sessionExpired`, `.restoring`: inalterados.
- Mapa genérico de outros serviços/prestadores (`Features/ProviderMap/ServiceMapView`): fora de
  escopo desta spec (ver `research.md` §4), mesmo tendo um gap equivalente.

## Comportamento do mapa

- `centerCoordinate` é sempre o último fix one-shot obtido para a descoberta do PitTec
  (`PitTecClientViewModel.lastFix`), nunca um novo fix pedido só para centralizar.
- `showsUserLocation: true` habilita o indicador nativo de posição do usuário (ponto azul do
  MapLibre) além do `centerCoordinate` — os dois já são suportados por `PitGoMapView`
  (`Core/UI/PitGoMapView.swift`), sem mudança nesse componente.
- A ausência de marcador de PitTec (`annotations` vazio) nunca esconde o mapa nem o indicador de
  posição do cliente.
- A mensagem informativa (sem PitTec / busca esgotada) é sempre uma sobreposição sobre o mapa
  (mesmo padrão de `MapAttributionView`), nunca uma tela substituta.
- Se `lastFix` for `nil` no momento de renderizar um destes estados (não deveria ocorrer no fluxo
  atual, já que ambos só são alcançados após um fix bem-sucedido), a tela mantém o comportamento
  anterior (mensagem só-texto) como salvaguarda defensiva — não é um estado a testar ativamente.

## Acessibilidade

Sem mudança em relação ao contrato de `015`: o indicador de posição do cliente não precisa de
`accessibilityLabel` próprio (é o indicador nativo do sistema); a mensagem sobreposta mantém o
mesmo texto e tratamento de Live Region (`.accessibilityAddTraits(.updatesFrequently)`) já usados
hoje pelos estados só-texto equivalentes.
