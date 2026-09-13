# Contract: RPCs de localização pontual do cliente durante o atendimento (shared backend, already implemented)

## Status: already implemented and deployed

`publish_client_location`/`get_appointment_client_location` e `public.client_current_locations` já
existem e estão aplicadas no projeto compartilhado com o Android (ver
[research.md §0](../research.md)). Espelham o padrão já usado por `publish_provider_location`/
`provider_current_locations` (`009`), sem campos de lease entre trackers (leitura única por abertura
de tela, não um stream contínuo disputado por múltiplos publicadores).

## Regras comuns (inalteradas)

- `SECURITY DEFINER SET search_path = ''`, `EXECUTE` revogado de `public`/`anon`, concedido só a
  `authenticated`.
- Participante derivado de `auth.uid()` contra `appointments.client_id`/`provider.account_id` —
  mesma verificação já usada por `appointments_select_participant` (`009`/`013`).
- Só é possível publicar/ler enquanto o atendimento estiver `ACCEPTED` ou `IN_PROGRESS`; fora disso,
  a linha é removida (mesmo padrão de `provider_current_locations`).
- `public.client_current_locations` tem RLS habilitada e nenhum grant direto de tabela ao bundle iOS.

## `publish_client_location(p_appointment_id, p_latitude, p_longitude, p_accuracy_m, p_captured_at)`

```swift
try await client.rpc("publish_client_location", params: payload).execute()
```

Chamável apenas pelo cliente dono do atendimento. Valida faixas de latitude/longitude, precisão
`<=100m` e captura recente (mesma janela de `publish_provider_location`). Faz upsert da única linha
do atendimento e dispara o mesmo evento de broadcast (`CHANGED`) já usado pelo canal privado
`appointment-location:<id>` (`009`) — nenhuma nova policy de `realtime.messages` é necessária.

Chamado pelo app iOS ao abrir `AppointmentTrackingView` e, se o usuário sair e voltar, a cada
reabertura (nunca em background — ver `data-model.md §3` e `research.md §2`).

## `get_appointment_client_location(p_appointment_id)`

```swift
let response: ClientLocationResponse = try await client
    .rpc("get_appointment_client_location", params: ["p_appointment_id": appointmentID])
    .execute()
    .value
```

Retorna a posição pontual mais recente do cliente para o atendimento, ou `.notFound` quando ainda
não houve nenhuma publicação. Chamável pelos dois participantes — é a RPC que o novo mapa do
provider (US3) usa para posicionar o marcador de destino.

```json
{
  "outcome": "FOUND",
  "location": {
    "latitude": -23.55, "longitude": -46.63, "accuracy_m": 15.0,
    "captured_at": "2026-08-23T18:00:00Z", "published_at": "2026-08-23T18:00:01Z"
  }
}
```

Outcomes fechados: `FOUND`, `NOT_FOUND` (ver edge case "mapa do guincho sem localização do cliente"
no spec — gera aviso textual, nunca marcador na origem `(0,0)`).

## Autorização (inalterada)

Só os dois participantes do atendimento (cliente dono e provider aceito) podem ler a posição;
nenhum outro cliente, provider ou conta anônima tem acesso — mesmo modelo de autorização já validado
para `provider_current_locations`.
