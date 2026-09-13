# Contract: Mobile provider current location and Realtime (iOS)

## iOS device-location boundary

`DeviceLocationRepository` (Swift) expõe:

- um fix preciso, cancelável, one-shot para cadastro (`CLLocationManager.requestLocation()`);
- um `AsyncStream<CLLocation>` de fixes de alta precisão para tracking do provider;
- nenhum conhecimento de sessão, provider ou atendimento;
- nenhuma persistência em disco.

Fix válido de provider: WGS84, `horizontalAccuracy <= 100m`, idade `<= 30s`. O one-shot de cadastro
expira em 15 segundos (timeout implementado no ViewModel, já que `CLLocationManager` não tem timeout
nativo). Tracking solicita um intervalo alvo de 10 segundos, sem batching e sem distância mínima
(`distanceFilter = kCLDistanceFilterNone`).

## Atualização em background (substitui o Foreground Service Android)

`ProviderLocationTracker` (uma classe Swift, não um serviço de sistema separado) usa
`CLLocationManager` com:

- `allowsBackgroundLocationUpdates = true`;
- capability "Background Modes → Location updates" habilitada no target;
- `pausesLocationUpdatesAutomatically = false` (o iOS não deve pausar durante um atendimento ativo).

Pré-condições (idênticas em espírito ao Android):

- tracking iniciado por uma ação visível na tela de atendimento aceito;
- sessão `.authenticatedProviderReady` para a mesma conta de processo;
- Provider MOBILE/ativo/disponível;
- autorização `.authorizedAlways` concedida (solicitada nesse momento, não no cadastro) e serviços de
  localização habilitados;
- snapshot do atendimento `ACCEPTED` ou `IN_PROGRESS` e pertencente ao Provider.

Diferente do Android, **não há notificação persistente para construir**: o iOS mostra
automaticamente um indicador de sistema (barra/pílula azul) sempre que o app atualiza localização em
background, cumprindo o mesmo objetivo de transparência sem código de notificação. O tracker observa
elegibilidade de sessão/tracking e para em toda condição terminal (ver `data-model.md`). Não há
reinício automático depois que o sistema suspende o app (equivalente ao `START_NOT_STICKY`/sem boot
receiver do Android) — o app precisa ser reaberto e o provider precisa reiniciar o tracking
manualmente se elegível. Offline mantém somente o fix válido mais recente em memória.

Entradas obrigatórias de `Info.plist`: `NSLocationWhenInUseUsageDescription`,
`NSLocationAlwaysAndWhenInUseUsageDescription` (com justificativa textual revisada pela Apple no App
Review) e a entrada de `PrivacyInfo.xcprivacy` para uso de API de localização. Se `.authorizedAlways`
for negada, o tracking fica limitado à tela visível (`.authorizedWhenInUse` continua funcionando
enquanto o app está em primeiro plano) — mesma degradação graciosa do "modo somente tela visível" do
Android quando a notificação é negada no Android 13+.

## Publish RPC (inalterado, backend-only)

```text
publish_provider_location(
  p_appointment_id uuid,
  p_latitude numeric,
  p_longitude numeric,
  p_accuracy_m numeric,
  p_captured_at timestamptz,
  p_tracker_instance_id uuid,
  p_tracker_sequence bigint
) -> {outcome:PUBLISHED|IGNORED_OLDER|PUBLISHER_CONFLICT, version, published_at}
```

Regras do servidor (inalteradas): deriva `auth.uid()`; exige owner PROVIDER, MOBILE, ativo/
disponível; exige atendimento participante em ACCEPTED/IN_PROGRESS; aceita tempo capturado entre
`now()-30s` e `now()+10s`, ponto e precisão válidos (`<=100`); advisory lock por atendimento; o mesmo
tracker exige sequência maior e tempo capturado não regressivo; um tracker diferente é rejeitado
enquanto o `published_at` atual tem menos de 30s, podendo assumir depois; upsert da única linha,
incrementa `version` e usa `published_at` do servidor; um update rejeitado nunca sobrescreve o dado
atual.

`tracker_instance_id` (`UUID`) é gerado uma vez por sessão de tracking no client iOS
(`ProviderLocationTracker.trackerInstanceID`); `tracker_sequence` é um contador `Int64` local
crescente.

`stop_provider_location(appointmentId, trackerId)` apaga somente a linha ativa do caller. Triggers de
banco também a apagam quando o atendimento se torna terminal ou o Provider vira fixo/inativo/
indisponível (inalterado).

`get_appointment_provider_location(appointmentId)` é somente-participante e retorna ponto/precisão/
timestamps/`version` atuais mais `fresh` derivado no servidor; requisições terminais/de terceiros não
retornam dado.

## Private Broadcast (inalterado, backend-only)

Tópico: `appointment-location:<appointmentId>`, canal `isPrivate: true`. Um trigger de banco
`AFTER INSERT/UPDATE/DELETE` emite um payload mínimo:

```json
{
  "event": "UPSERT",
  "latitude": -23.5,
  "longitude": -46.6,
  "accuracy_m": 18.0,
  "captured_at": "...",
  "published_at": "...",
  "version": 12
}
```

Delete emite `event=CLEARED` com apenas `version`/contexto do tópico. Nenhum ID de conta/provider/
cliente ou dado de empresa é transmitido.

RLS em `realtime.messages` permite SELECT/join somente quando `realtime.topic()` identifica um
atendimento cuja conta cliente ou provider é `auth.uid()` e o status é ACCEPTED/IN_PROGRESS. Clients
autenticados não têm policy de INSERT em Broadcast; só o trigger de banco publica. Acesso a canal
público está desabilitado.

## Ordem de consumo (client iOS)

1. `client.realtime.setAuth()`;
2. criar e assinar o canal privado via `RealtimeChannelV2`;
3. buscar o snapshot via RPC **depois** da confirmação de assinatura;
4. mesclar snapshot/eventos somente quando a `version` for mais nova;
5. ao reconectar, buscar o snapshot novamente;
6. em `published_at + 30s`, marcar como stale localmente mesmo sem evento;
7. remover o canal ao sair da tela/logout/troca de sessão (`.onDisappear`/observação de
   `SessionStore`).

## Client discovery location

O mapa do cliente não usa esta tabela/canal. Um fix one-shot do cliente é mantido em memória e
enviado apenas como centro da consulta RPC. Negação de permissão usa a região selecionada/manual do
mapa. Sair do mapa visível cancela a aquisição e limpa o ponto.
