# Contract: Realtime e publicação contínua (iOS)

## Tópicos privados (inalterados, backend compartilhado)

```text
mobile-dispatch:<searchID>
provider-dispatch:<providerID>
```

RLS em `realtime.messages` permite receber apenas quando a conta CLIENT é proprietária da busca (no
primeiro tópico) ou a conta PROVIDER é proprietária do provider (no segundo). Não existe policy
INSERT para o client; triggers do banco emitem eventos após transições.

## Payload de invalidação (inalterado)

```json
{
  "search_id": "uuid-or-null",
  "appointment_id": "uuid-or-null",
  "status": "AWAITING_PROVIDER",
  "revision": 7,
  "response_deadline": "2026-08-23T18:01:00Z"
}
```

```swift
struct DispatchInvalidationPayload: Decodable {
    let searchID: UUID?
    let appointmentID: UUID?
    let status: ServiceSearchStatus
    let revision: Int64
    let responseDeadline: Date?
}
```

O payload não contém coordenadas, preço, nome, contato, CNPJ, motivo de cancelamento ou ponto do
cliente — apenas acorda o Repository, que busca o snapshot autorizado via RPC. Atualizações da
posição do provider corrente também invalidam `mobile-dispatch:<searchID>` somente para a busca
cuja proposta atual referencia aquele provider.

## Sequência de assinatura (idêntica ao padrão já estabelecido em `009`/`010`)

1. Validar a sessão/owner esperados.
2. Criar o `AsyncStream` de observação antes de assinar.
3. Chamar `client.realtime.setAuth()` e assinar o canal privado, aguardando confirmação.
4. Consultar `get_my_active_mobile_dispatch()`/`get_my_pending_mobile_dispatch()`.
5. Em evento, buscar novo snapshot; aceitar somente `revision > acceptedRevision` ou snapshot
   semanticamente terminal da mesma revisão.
6. Em reconexão/rejoin, repetir autenticação, subscribe e snapshot.
7. Em cancelamento/logout, remover o canal numa `Task` desacoplada do escopo cancelável (mesma
   técnica de `010 contracts/realtime-marker.md`), zerar estado/IDs imediatamente e relançar
   `CancellationError`.

Broadcast perdido não perde estado; Broadcast duplicado não duplica comando; evento antigo nunca
move o fluxo para trás.

## `ProviderLocationTracker` (substitui o Foreground Service Android)

Um `AsyncStream<CLLocation>` sequencial e "conflated": no máximo uma publicação em voo e somente o
fix mais recente aguardando (equivalente ao stream sem `collectLatest` cancelando continuamente uma
RPC lenta, do Android) — implementado descartando fixes intermediários se uma publicação anterior
ainda estiver em `await`. Não mantém fila offline.

### Início

- ação visível no `ProviderDashboardView`;
- provider `MOBILE`, ativo, com intenção disponível;
- `.authorizedWhenInUse` (mínimo) concedida e serviços de localização habilitados;
- `allowsBackgroundLocationUpdates = true` ativado imediatamente após a autorização adequada
  (`.authorizedAlways` quando o toggle "Disponível" for ligado, ver `research.md §3`);
- inicialização de sessão idempotente também funciona se o processo for recriado pelo sistema.

### Continuidade

- alvo aproximado de 10s, fix `<=100m` e idade `<=30s`;
- não há garantia de reinício automático após o sistema finalizar o app — mesma limitação
  "best-effort" do `START_STICKY` Android;
- o indicador de sistema de uso de localização em background substitui a notificação persistente
  construída manualmente pelo Android;
- minimizar o app não interrompe a publicação (com `.authorizedAlways`); finalizar o app pelo
  sistema deixa o heartbeat stale e exige retomada visível posterior;
- a preferência técnica leve pode guardar tracker/conta/sequência, nunca coordenada.

### Interrupção/degradação

- indisponível/fixo/inativo/logout/permissão revogada/localização desligada: parada best-effort
  remota e fim do tracker;
- offline/fix impreciso: manter apenas o fix atual em memória; após 30s o servidor exclui o
  registro de discovery;
- a ação "Ficar indisponível" sincroniza o backend antes de parar;
- durante um appointment, essa ação abre o fluxo de cancelamento com motivo em vez de cancelar
  silenciosamente;
- o aceite projeta no tópico privado `appointment-location:<appointmentID>` já existente (`009`);
- o término remove o tracking privado e só volta à discovery com um novo fix elegível.

## Snapshot versus countdown

`responseDeadline` e `serverNow` ancoram a exibição local. Um `Timer`/`Task.sleep` de 1 segundo não
é autoritativo nem Live Region. Ao exibir zero, a UI mostra "Tempo esgotado. Atualizando…" e
solicita um novo snapshot. Apenas a transição persistida pelo servidor muda o estado.
