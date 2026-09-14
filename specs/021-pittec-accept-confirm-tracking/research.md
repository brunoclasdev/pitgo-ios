# Phase 0 Research: Aceite do PitTec com confirmação de valor e mapa conjunto

## 1. Como sincronizar "o cliente confirmou o valor" entre dois aparelhos diferentes

**Decision**: Uma nova RPC no backend Supabase compartilhado (`confirm_pittec_appointment`) grava um
novo campo (`confirmed_at`) no mesmo registro de atendimento já lido por cliente e provider; ambos
continuam observando essa mudança pelos mesmos dois canais Realtime já existentes
(`mobile-dispatch:<searchID>` do lado cliente, `provider-dispatch:<providerID>` do lado provider),
sem nenhum canal novo. Essa RPC e a coluna são responsabilidade do usuário/administrador do backend
compartilhado — confirmado explicitamente nesta sessão — e ficam documentadas como dependência
externa em `contracts/confirm-pittec-value-rpc.md`, não implementadas por este repositório iOS.

**Rationale**: A investigação do código atual (`PitTecRepository.swift:221-247`) confirma que os
dois canais hoje só emitem `onBroadcast(event: "*")` como um sinal genérico de "algo mudou, refaça
`get_my_active_pittec_dispatch()`" — nenhum payload rico trafega no broadcast em si; a fonte de
verdade real é sempre o snapshot recarregado via RPC. Isso significa que qualquer novo fato que um
lado precise saber sobre o outro (como "o cliente confirmou") só pode chegar ao segundo aparelho se
esse fato for persistido no mesmo registro que os dois já leem — não existe hoje nenhum client-side
trick (WebSocket direto, notificação local, etc.) capaz de replicar isso sem tocar o backend, porque
os dois processos rodam em aparelhos físicos diferentes, sem nenhuma comunicação direta entre si.

**Alternatives considered** (apresentadas ao usuário nesta sessão):

- *B — Reverter para o PitTec ver o mapa assim que aceita, sem esperar confirmação nenhuma*:
  eliminaria a necessidade de qualquer sinal novo (100% client-side), mas contraria a decisão já
  tomada na sessão de `/speckit-clarify` anterior (manter os dois lados simétricos). Rejeitada pelo
  usuário nesta sessão.
- *C — Tela de espera do PitTec liberada por timeout/heurística local (sem sinal real)*: evitaria
  backend novo, mas não garante que o PitTec só veja o mapa depois que o cliente de fato confirmou —
  poderia liberar cedo demais (cliente ainda não confirmou) ou tarde demais (cliente já confirmou e
  o PitTec continua esperando por um tempo arbitrário), quebrando a garantia central da User Story 2.
  Rejeitada pelo usuário nesta sessão.
- **Escolhida — A**: usuário assume a criação da RPC/coluna no backend compartilhado; este plano
  consome esse contrato como dependência externa, no mesmo padrão já usado por todas as demais RPCs
  do PitTec (`contracts/pittec-rpcs.md` de `015`, todas descritas como "já implementadas e
  implantadas" antes de o client iOS ser escrito). Esta é a primeira feature deste histórico de specs
  em que o client iOS é escrito **antes** da RPC existir — por isso o contrato correspondente
  (`confirm-pittec-value-rpc.md`) é redigido como especificação a implementar, não como documentação
  de algo já pronto.

## 2. Onde a recusa do valor deve ser tratada (nova política ou reaproveitamento)

**Decision**: Recusar o card de confirmação chama a RPC já existente `cancel_mobile_appointment`
(mesma usada hoje por "Cancelar atendimento" em um atendimento já aceito), com um motivo de sistema
fixo (ex.: "Cliente não confirmou o valor apresentado") em vez de abrir a sheet de texto livre
(`DispatchCancellationSheet`) já usada para cancelamento manual mais tarde no fluxo.

**Rationale**: A spec (`Assumptions`) já define que a recusa reaproveita "a mesma política de
cancelamento/estorno já existente para atendimentos já aceitos" — não uma política nova. A RPC
`cancel_mobile_appointment` já aceita `p_appointment_id`/`p_reason`/`p_expected_revision` e já está
implementada; nenhuma mudança de backend é necessária para a recusa. Um motivo de sistema (em vez de
pedir texto ao cliente) mantém o botão "Recusar" do card como uma ação de um toque só, compatível
com o Acceptance Scenario 3 da spec ("o atendimento é encerrado ... e o cliente é informado", sem
menção a digitar um motivo).

**Alternatives considered**:

- *Reaproveitar a sheet `DispatchCancellationSheet` (texto livre) também aqui*: rejeitado — adiciona
  fricção a uma decisão que na spec é binária (confirmar/recusar), sem pedido explícito de capturar
  o motivo do cliente nesse ponto específico do fluxo.
- *Criar uma RPC de "recusa de valor" dedicada*: rejeitado — duplicaria `cancel_mobile_appointment`
  sem necessidade; a constituição (I) pede a solução mais simples entre equivalentes.

## 3. Como enquadrar duas posições juntas no mapa

**Decision**: Adicionar a `PitGoMapView` uma nova capacidade que, quando há mais de uma coordenada
relevante (cliente + PitTec), usa `MLNMapView.setVisibleCoordinates(_:count:edgePadding:animated:)`
(API nativa do MapLibre Native iOS já vendorizado, confirmada em
`MapLibre.framework/Headers/MLNMapView.h`) para enquadrar as duas com um padding seguro, em vez de
depender de `centerCoordinate` (que só posiciona um único ponto) ou do zoom padrão do mapa.

**Rationale**: Fecha uma lacuna já documentada (mas nunca implementada) em `015-pittec-on-demand`
(FR-021: "inicialmente enquadrando ambos"). Nenhuma dependência nova — a API já existe no SDK
vendorizado usado desde `009`. Mantém `centerCoordinate` intacto para os demais consumidores de
`PitGoMapView` (descoberta do PitTec `020`, `ServiceMapView`), que continuam com um único ponto.

**Alternatives considered**:

- *Calcular um centro/zoom manualmente a partir das duas coordenadas*: rejeitado — reinventaria o
  que `setVisibleCoordinates` já faz de forma nativa e testada pelo próprio MapLibre.
- *Manter o comportamento atual (sem enquadramento, só marcadores soltos)*: rejeitado — é exatamente
  a lacuna que a User Story 2 pede para fechar.

## 4. Onde o novo sub-estado "aguardando"/"confirmado" deve viver

**Decision**: Não criar um novo caso em `PitTecClientUiState`/`ProviderDispatchUiStatePitTec`. O
sub-estado é derivado, na View, a partir de `snapshot.appointment?.confirmedAt` já dentro do
`.content(snapshot, pendingAction)` existente (cliente) e do `.reserved(snapshot, pendingAction)`
existente (provider) — o mesmo padrão já usado hoje para diferenciar `searching`/`optionFound`/
`awaitingProvider` dentro de um único caso `.content` via `switch snapshot.status`.

**Rationale**: Consistente com o princípio III (estado modelado por enum único, sem Bool paralelo) e
com o padrão já estabelecido no mesmo arquivo — `confirmedAt` é só mais um campo do mesmo snapshot
que já determina outras bifurcações de tela hoje. Evita inflar o enum de estado de tela com casos
que só existem para representar uma combinação de campos já presente no snapshot.

**Alternatives considered**:

- *Novo caso `.awaitingConfirmation`/`.confirmed` no enum de estado*: rejeitado — duplicaria
  informação já carregada por `appointment.status`/`confirmedAt`, contrariando o padrão já
  estabelecido no mesmo arquivo para bifurcações equivalentes.
