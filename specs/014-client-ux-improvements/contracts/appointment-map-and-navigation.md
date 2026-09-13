# Contract: Mapa do atendimento e navegação de retomada (iOS)

Este contrato é comportamental (UI/navegação), não uma API de rede — documenta como os dados já
existentes (posição do provider em tempo real, leitura pontual do cliente, revisão do atendimento)
são apresentados e quando a navegação automática pode disparar.

## Mapa do cliente (`AppointmentTrackingView`, US2)

- Câmera inicial enquadra a posição do próprio cliente (leitura pontual, `data-model.md §3`) e a
  posição do provider (tempo real, `009`).
- O marcador do cliente é estático entre reaberturas da tela (não recentraliza sozinho a cada
  segundo); o marcador do provider se move conforme novas posições chegam pelo canal já existente
  (`appointment-location:<id>`).
- Se a posição do provider ainda não chegou: mostrar a posição do cliente normalmente e um aviso
  textual de que a localização do guincho ainda não está disponível (não travar o mapa nem deixar em
  branco).
- Gesto manual do usuário (arrastar/zoom no `MLNMapView`) suspende o recentramento automático até uma
  ação explícita retomá-lo — mesmo padrão de `.stale`/"Seguir prestador" já especificado em `010`/
  `013`, generalizado para dois pontos.

## Mapa do provider (`ProviderIncomingRequestView`, US3 — novo)

- Câmera inicial enquadra a posição do provider (tempo real) e a posição do cliente (leitura
  pontual repassada pelo snapshot do atendimento via `get_appointment_client_location`).
- Se o cliente ainda não tiver uma posição conhecida: mostrar um aviso textual equivalente, nunca um
  marcador na origem `(0,0)` nem mapa vazio sem explicação.
- Mesma regra de suspensão de recentramento automático após gesto manual do provider.

## Retomada automática de navegação (US4)

Contrato para `DispatchResumeCoordinator` (`013`), especificando o mecanismo exato de disparo:

1. A navegação automática para a tela de um atendimento ativo (`AppointmentTrackingView` para
   cliente, `ProviderIncomingRequestView` para provider) só é disparada quando a `revision` do
   `snapshot.appointment`/busca observada for **maior** que `lastTriggeredRevision` (guardada no
   próprio `DispatchResumeCoordinator`, em memória, para esta sessão do app).
2. Ao iniciar/retomar a sessão (login, cold start com o app reaberto), a navegação automática é
   sempre avaliada uma vez a partir da revisão restaurada — preservando o comportamento de retomada
   já coberto pelo cenário 3 de US4.
3. Um "voltar" manual do usuário (gesto de borda ou botão) **não** altera nem reseta
   `lastTriggeredRevision`; ele apenas move o `NavigationPath`. A próxima mudança real de revisão
   (novo evento, mudança de status) é que pode disparar a navegação automática de novo — nunca a
   simples repetição do mesmo snapshot (ex.: uma nova emissão do `@Observable` sem mudança de dado).
4. Este contrato vale igualmente para `AppSessionState.authenticatedClient` e
   `.authenticatedProviderReady` (`006`/`009`).

```swift
// DispatchResumeCoordinator (013), reforço desta feature:
private var lastTriggeredRevision: Int64?

func evaluateResumeNavigation(for snapshot: MobileDispatchSnapshot) -> ResumeDestination? {
    guard snapshot.revision > (lastTriggeredRevision ?? .min) else { return nil }
    lastTriggeredRevision = snapshot.revision
    return resumeDestination(for: snapshot)
}
```
