# Contract: PitTec Realtime and provider alerts (iOS)

## Objective

Entregar uma oferta visível e sonora a um PitTec disponível enquanto o app está em primeiro plano,
segundo plano ou com a tela bloqueada, sem tratar Realtime como fonte de verdade e sem expor
coordenadas privadas em eventos.

## Availability lifecycle

1. Provider seleciona modalidade efetiva PITTEC e ativa disponibilidade.
2. O app verifica autorização de localização (`.authorizedWhenInUse`/`.authorizedAlways`, mesmo
   tracker de `009`/`013`), autorização de notificação (`UNAuthorizationOptions.alert`/`.sound`,
   equivalente iOS ao `POST_NOTIFICATIONS`/canal habilitado do Android) e que a categoria de
   notificação de ofertas PitTec está registrada.
3. `ProviderLocationTracker` (`009`/`013`, generalizado) inicia/permanece ativo com
   `allowsBackgroundLocationUpdates = true` e exibe o indicador de sistema de uso de localização.
4. O tracker publica pontos de discovery e observa o tópico privado de despacho do provider.
5. Desativar disponibilidade, perder elegibilidade ou sair da conta para a observação/publicação
   conforme o ciclo de vida já especificado.

Se a autorização de notificação estiver ausente/negada, a UI não anuncia disponibilidade PitTec bem
-sucedida — explica o requisito e oferece um link para `UIApplication.openSettingsURLString`.

## Private topics (inalterados, backend compartilhado)

```text
provider-dispatch:<providerID>   // oferta criada/alterada/retirada
client-dispatch:<clientID>       // busca/atendimento alterados
appointment:<appointmentID>      // estado/localização/rota do atendimento aceito invalidados
```

Políticas de autorização permitem somente o usuário assunto ou participante do atendimento.

## Event envelope (inalterado)

```json
{
  "event": "DISPATCH_INVALIDATED",
  "entity_id": "uuid",
  "revision": 7,
  "state": "PENDING",
  "occurred_at": "2026-09-02T15:00:01Z"
}
```

```swift
enum PitTecEventClass: String, Decodable {
    case dispatchInvalidated = "DISPATCH_INVALIDATED"
    case appointmentInvalidated = "APPOINTMENT_INVALIDATED"
    case locationInvalidated = "LOCATION_INVALIDATED"
    case routeInvalidated = "ROUTE_INVALIDATED"
}
```

Eventos são apenas dicas — sem latitude/longitude, geometria, texto de motivo, nome, telefone,
endereço ou token de acesso.

## Source of truth and recovery (idêntico ao padrão de `009`/`010`/`013`)

- Ao iniciar/reiniciar o tracker, entrar em primeiro plano, reconectar o Realtime ou receber um
  evento, buscar o snapshot autoritativo (`get_my_active_pittec_dispatch`).
- Ignorar um evento com `revision` mais antiga que a última aplicada.
- Enquanto disponível e o Realtime estiver desconectado/suspeito de estar obsoleto, fazer polling do
  snapshot a cada 5s com no máximo uma requisição em voo e retry/backoff limitado.
- O backend usa tempo de servidor para a oferta de 60s; o app renderiza um countdown derivado de
  `offerExpiresAt`, mas não pode aceitar após a expiração no servidor.
- Reconectar nunca reproduz efeitos colaterais de UI já notificados para o mesmo par
  `(appointmentID, revision)`.

## Local notification

```swift
let content = UNMutableNotificationContent()
content.title = String(localized: "Novo chamado PitTec")
content.body = /* solicitação genérica + tempo restante, sem endereço exato */
content.sound = .default
content.categoryIdentifier = "PITTEC_INCOMING_REQUEST"
content.userInfo = ["appointmentID": appointmentID.uuidString]

let request = UNNotificationRequest(
    identifier: appointmentID.uuidString,   // hash estável — atualiza em vez de duplicar
    content: content,
    trigger: nil   // entrega imediata
)
try await UNUserNotificationCenter.current().add(request)
```

Propriedades: importância alta (`UNNotificationInterruptionLevel.timeSensitive` quando disponível);
som habilitado por padrão; visibilidade de tela bloqueada privada (sem endereço/nome do cliente no
preview); categoria de "chamado/solicitação de serviço". Ao encerrar a oferta (aceita por outro
motivo, cancelada, expirada), remover a notificação pendente via
`UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers:)`.

Toque na notificação usa o `UNNotificationDelegate` para navegar diretamente à
`ProviderIncomingRequestView` (`013`), carregando apenas o `appointmentID` e recarregando o snapshot
autoritativo antes de mostrar detalhes — nunca confia em dados embutidos na notificação como estado
atual.

## Foreground/background tracker behavior

- Generalizar o predicado do tracker de "somente MOBILE" para "`locationMode` em
  `{.mobile, .pittec}`" enquanto disponível.
- Manter um único `ProviderLocationTracker`, nunca dois trackers/observadores concorrentes.
- Revalidar sempre conta autenticada, modo efetivo e disponibilidade antes de assinar o canal —
  mesmo após reinicialização do processo pelo sistema.
- Nunca colocar o client Supabase, Repositories ou estado mutável de UI diretamente num contexto de
  `BGTaskScheduler`/extensão — a lógica de negócio vive no app principal.
- Tocar a notificação abre o app, que restaura o snapshot autoritativo e roteia para a tela correta
  do provider.
- Ao encerrar uma oferta, cancelar seu alerta e renderizar o novo estado/próxima oferta.

## UI reactions (idênticas ao Android)

| Estado autoritativo | Efeito no provider |
|---|---|
| nenhuma oferta ativa | Dashboard/tracker continua disponibilidade silenciosamente |
| `PENDING` não expirada | notificação uma vez por revisão; tela de oferta mostra Aceitar/Recusar e countdown |
| `ACCEPTED` | cancela alerta; abre tracking com ação "A caminho" |
| `IN_PROGRESS` | mostra "Cheguei"; habilita Concluir/Cancelar |
| terminal/oferta substituída | cancela notificação obsoleta e busca o próximo snapshot |

## Failure behavior

- Realtime indisponível: polling mantém entrega best-effort.
- Rede indisponível: mantém a UI de disponibilidade, mas marca reconectando; posição de discovery
  obsoleta torna o provider inelegível no backend.
- Autorização de notificação negada/desabilitada: desativa ou recusa ativar disponibilidade, com um
  prompt acionável de configurações.
- App finalizado pelo sistema/dispositivo reiniciado: sem garantia de entrega nesta versão (mesma
  limitação consciente do Android sem FCM — aqui, sem APNs).

## Verification matrix

Validar em iOS 17/18: primeiro plano, segundo plano e tela bloqueada; autorização concedida/negada/
revogada; Realtime conectado/desconectado/reconectado; invalidações duplicadas e fora de ordem;
oferta aceita, recusada, expirada e retirada com a notificação visível; logout ou troca de
modalidade enquanto assinado; recriação do processo sem vazar a oferta de um usuário anterior.
