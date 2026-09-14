# Contract: Confirmação de valor e mapa conjunto do PitTec (UI, iOS)

Este contrato **refina** a tabela "Map presentation" de
`specs/015-pittec-on-demand/contracts/pittec-routing-ui.md` para as fases `ACCEPTED`/`IN_PROGRESS`,
fechando o FR-021 daquela spec ("inicialmente enquadrando ambos"), nunca implementado até aqui.
Depende da RPC externa descrita em `confirm-pittec-value-rpc.md`.

## Estados por lado

| `appointment.status` | `appointment.confirmedAt` | Tela do cliente (`PitTecClientView`) | Tela do PitTec (`PitTecIncomingRequestView`) |
|---|---|---|---|
| `accepted`/`inProgress` | `nil` | Card de confirmação: valor do atendimento (já pago, FR-002), botões "Confirmar" e "Recusar" | Tela "Aguardando confirmação do cliente" — sem ações, só um indicador de espera |
| `accepted`/`inProgress` | presente | Mapa de acompanhamento, `PitGoMapView` enquadrando cliente + PitTec juntos | Mapa de acompanhamento, `PitGoMapView` enquadrando PitTec + cliente juntos |

Todos os demais `status` (`searching`, `optionFound`, `awaitingProvider`, `completed`, `cancelled`,
`exhausted`) permanecem exatamente como hoje — inalterados por esta feature.

## Ações

- **Confirmar** (cliente): chama `confirmValue(appointmentID:expectedRevision:)` → RPC
  `confirm_pittec_appointment`. Botão desabilitado enquanto uma ação já está pendente (mesmo padrão
  de `PendingDispatchAction` já usado por cancelar/aceitar/recusar).
- **Recusar** (cliente): chama o já existente `cancelAppointment(appointmentID:reason:expectedRevision:)`
  com um motivo de sistema fixo (não uma sheet de texto livre — ver `research.md` §2), aplicando a
  mesma política de cancelamento/estorno já existente para atendimentos aceitos.
- **PitTec**: nenhuma ação nova nesta tela de espera — só observa o mesmo snapshot via o canal
  Realtime já existente (`provider-dispatch:<providerID>`), sem polling adicional.

## Comportamento do mapa (enquadramento conjunto)

- Quando `confirmedAt` está presente e as duas posições (cliente e PitTec) são conhecidas,
  `PitGoMapView` usa a nova capacidade de enquadrar múltiplas coordenadas
  (`setVisibleCoordinates(_:count:edgePadding:animated:)`) em vez de `centerCoordinate` — ver
  `research.md` §3.
- O enquadramento é reaplicado sempre que a posição do PitTec se move o suficiente para sair da
  área visível confortável (mesmo espírito do já existente `onRegionChanged`/refresh reativo — não
  é um requisito de "sempre recentralizar a cada pixel de movimento", só manter os dois visíveis).
- Um pan/zoom manual do usuário não deve ser sobrescrito imediatamente pelo próximo enquadramento
  automático (mesma regra já documentada em `pittec-routing-ui.md`: "não sobrescrever continuamente
  um pan/zoom manual do usuário").
- Se a posição do PitTec ainda não tiver chegado (`routeContext` não pronto), a tela mostra o mesmo
  estado de espera de posição já existente hoje (`"Aguardando localização…"`), antes de qualquer
  enquadramento.

## Atualização periódica de posição (User Story 3)

Reaproveita integralmente o mecanismo já existente e funcional: `ProviderLocationTracker` publica a
cada ~10s (`ProviderLocationTracker.swift`) enquanto o PitTec está com um atendimento aceito; o
cliente recebe a invalidação via o canal `mobile-dispatch:<searchID>` já existente e refaz
`get_pittec_route_context`. Nenhuma mudança nesse mecanismo — esta feature só garante que ele
continua alimentando o mapa de acompanhamento agora gated por `confirmedAt`, em vez de logo após o
aceite bruto.

## Fora de escopo deste contrato

- Notificação push real (APNs) para o PitTec enquanto o app está em segundo plano/fechado —
  documentada como lacuna existente desde `015`, não resolvida por esta feature (ver Assumptions do
  `spec.md`).
- Indicador de "posição desatualizada" após 30s sem atualização (FR-025 de `015`, ainda não
  implementado) — fora do pedido original desta feature; não introduzido aqui.
- Reenquadramento manual sob demanda (botão "recentralizar", FR-027 de `015`) — não pedido nesta
  feature; o enquadramento automático descrito acima já cobre o cenário pedido.
