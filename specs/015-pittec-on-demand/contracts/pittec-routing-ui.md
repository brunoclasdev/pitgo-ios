# Contract: PitTec route and map UI (iOS)

## Edge Function `pittec-route` (shared backend, already implemented)

`POST /functions/v1/pittec-route`, autenticada, chamada via:

```swift
struct PitTecRouteRequest: Encodable { let appointmentID: UUID; let providerLocationRevision: Int64 }

let response: PitTecRouteResponse = try await client.functions
    .invoke("pittec-route", options: .init(body: request))
    .value
```

### Success response

```json
{
  "status": "ROUTE",
  "appointment_id": "uuid",
  "provider_location_revision": 14,
  "distance_meters": 6840,
  "geometry": { "type": "LineString", "coordinates": [[-46.6401, -23.5602], [-46.6333, -23.5505]] },
  "generated_at": "2026-09-02T15:12:20Z"
}
```

Se o snapshot armazenado já tiver revisão igual/mais nova e permanecer utilizável, ele é retornado
com HTTP 200 — o client nunca depende de um corpo 304.

### Error response

```json
{ "status": "UNAVAILABLE", "code": "ROUTER_TIMEOUT", "retryable": true }
```

| HTTP | Code | Meaning |
|---:|---|---|
| 400 | `INVALID_REQUEST` | UUID/revisão malformados |
| 401 | `AUTH_REQUIRED` | sessão ausente/inválida |
| 403 | `NOT_PARTICIPANT` | caller não é cliente/provider do atendimento |
| 409 | `APPOINTMENT_NOT_TRACKABLE` | atendimento não está aceito/em andamento |
| 409 | `LOCATION_NOT_READY` | um dos pontos exatos dos participantes ainda não existe |
| 429 | `RATE_LIMITED` | requisição cedo demais; usar snapshot atual/fallback |
| 502 | `ROUTER_FAILURE` | resposta upstream inválida/erro |
| 504 | `ROUTER_TIMEOUT` | prazo upstream excedido |

## Function behavior (inalterado, backend-only)

Validação de JWT/participação, exigência de `ACCEPTED`/`IN_PROGRESS`, leitura server-side dos dois
pontos exatos (nunca aceitos do corpo da requisição), rate limit por atendimento (refresh só quando
o provider se moveu ≥50m e a rota anterior tem ≥15s), chamada HTTPS a um endpoint OSRM-compatível
configurado via Supabase Secrets, validação de geometria/tamanho, upsert de uma única linha por
atendimento. Nenhuma credencial de roteamento entra no bundle iOS.

## Refresh policy no client iOS

- Buscar quando um atendimento se torna `ACCEPTED` pela primeira vez, quando não existe rota, ou
  após uma invalidação de localização do provider que atenda ao limiar de movimento/tempo.
- Manter no máximo uma requisição em voo por atendimento (um `Task` dedicado); revisões mais novas
  recebidas durante o voo são conflated e disparam uma nova requisição ao término.
- Não limpar uma rota válida só porque um refresh falhou; marcá-la como stale e retê-la até haver
  substituição/fallback.
- Quando o fix mais recente do provider tiver mais de 30s, preservar o último marcador e rota, mas
  mostrar um aviso explícito de localização desatualizada; nunca rotular como "ao vivo".
- Parar requisições e limpar geometria em memória imediatamente em estado terminal ou logout.
- Os dois participantes consomem a mesma revisão armazenada; o provider é o gatilho principal de
  refresh, mas qualquer participante pode solicitar uma rota ausente.

## Fallback (client iOS, sem backend)

Quando nenhuma geometria roteada está disponível: calcular distância haversine localmente a partir
dos dois pontos exatos (só participantes); desenhar uma linha direta tracejada de dois pontos;
rotular a distância como aproximada (`~6,8 km`) com descrição semântica; retry só com backoff
limitado e os mesmos gatilhos de refresh; nunca bloquear aceite, chegada, conclusão ou cancelamento
por causa do roteamento.

## Map presentation

MapLibre Native iOS (`010`) continua o renderizador.

| Fase | Marcadores | Linha | Card inferior / ações |
|---|---|---|---|
| descoberta | cliente exato (self); PitTecs aproximados anônimos | nenhuma | "Chamar PitTec" |
| buscando/solicitando | marcador do cliente; aproximados podem permanecer neutros | nenhuma | progresso "Buscando PitTec…"; Cancelar |
| oferta ao provider | cliente vê busca genérica; provider só vê destino após aceitar | nenhuma | cliente continua progresso; provider Aceitar/Recusar/countdown |
| `ACCEPTED` | cliente exato + PitTec aceito, visualmente distintos | linha roteada sólida ou fallback tracejado | distância, "PitTec a caminho"; cancelamento cliente/provider |
| `IN_PROGRESS` | ambos exatos | última rota pode permanecer | "PitTec chegou"; Concluir/Cancelar do provider |
| terminal | nenhum marcador de participante ao vivo após limpeza | nenhuma | resultado terminal e navegação/retry |

Comportamento do mapa: enquadrar ambos os marcadores exatos e os limites da rota com padding seguro
após o aceite; não sobrescrever continuamente um pan/zoom manual do usuário. Usar uma
`MLNShapeSource` + `MLNLineStyleLayer`, atualizando a source em vez de recriar o mapa inteiro. Linha
sólida (roteada) e tracejada (estimativa) devem diferir por mais que só a cor. Formatar abaixo de
1km em metros, acima em quilômetros localizados com uma casa decimal. Marcadores aproximados de
descoberta comunicam incerteza e não expõem um perfil de provider tocável.

## Compose state contract (equivalente iOS)

O ViewModel PitTec expõe um único estado imutável (`PitTecClientUiState`/`PitTecProviderUiState`,
`data-model.md`) contendo: prontidão de permissão/localização; carregamento/erro/marcadores de
descoberta; status e revisão autoritativos do despacho; modelos de marcador permitidos para a fase
atual; estado de rota, rótulo de distância e flag de stale/fallback; ações disponíveis e loading/
erro por ação; efeitos de navegação one-shot separados do estado durável.

Views são stateless e emitem eventos como `.requestService`, `.cancelSearch`, `.retryDiscovery`,
`.accept`, `.reject`, `.arrive`, `.complete` e `.cancelAppointment`. Não chamam Supabase, o roteador
ou APIs de localização diretamente.

## Navigation/deep links

- O card PitTec da Home abre a rota de descoberta/solicitação.
- A notificação do provider carrega apenas o `appointmentID`; o destino recarrega o snapshot antes
  de mostrar detalhes.
- Início/retomada do app restaura o despacho sequencial ativo antes de aceitar uma nova solicitação.
- Deep links para atendimento ausente/terminal roteiam para Dashboard/Home com mensagem breve não
  sensível.

## Accessibility and privacy

Todos os marcadores/ações têm rótulos de acessibilidade localizados e o status é anunciado sem
atualizações repetidas de Live Region; loading é representado em texto, não só animação; o tipo de
rota (real/estimada) é expresso em texto e padrão de linha; texto de notificação/tela bloqueada não
contém endereço exato ou identidade do cliente; esta feature não introduz logging de coordenadas ou
analytics.
