# Contract: PitTec discovery and dispatch RPCs (shared backend, already implemented)

## Status: already implemented and deployed

Todas as RPCs abaixo já existem e estão aplicadas no projeto Supabase compartilhado com o Android
(ver [research.md §0](../research.md)). Nenhuma migration nova é criada por esta feature iOS.

## General rules (inalteradas)

- Expostas somente a `authenticated`, derivam identidade de `auth.uid()`.
- Mutations rodam numa única transação, travam a busca/atendimento atual e aceitam
  `expected_revision` quando alteram uma entidade existente.
- Repetir o mesmo `p_request_id` (gerado uma vez no client como `UUID()`) é idempotente e retorna o
  resultado autoritativo em vez de duplicar linhas.
- Erros de domínio usam códigos estáveis (`enum` fechado); texto localizado pertence ao client iOS.

## `list_nearby_pittecs`

```swift
let response: NearbyPitTecsResponse = try await client
    .rpc("list_nearby_pittecs", params: payload)
    .execute()
    .value
```

Lista posições aproximadas e anônimas para o mapa pré-solicitação. Caller deve ser cliente ativo;
serviço deve usar `PITTEC_AUTO_SEQUENTIAL`. Retorna no máximo `min(max(limit, 1), 200)` marcadores
dentro de 50km. `markers` vazio é sucesso, não erro. Nunca retorna ID/nome de provider, distância
exata, preço, localização exata ou contato direto.

## `start_pittec_dispatch`

```swift
let response: PitTecStartResponse = try await client
    .rpc("start_pittec_dispatch", params: payload)
    .execute()
    .value
```

Inicia uma solicitação e oferece imediatamente ao provider elegível mais próximo ainda não tentado.
Reaproveita a entidade para o mesmo `p_request_id` se já commitado. Sem candidato, retorna
`.noProvider` diretamente — não existe `OPTION_FOUND` intermediário para PitTec (o cliente não
escolhe um candidato).

## `advance_pittec_dispatch` (privada, não chamada diretamente pelo client)

Helper `SECURITY DEFINER` interno, acionado por recusa/timeout/cancelamento do provider. Marca o
candidato atual como terminal exatamente uma vez, incrementa a revisão e seleciona o próximo
provider ainda não tentado.

## `respond_to_mobile_dispatch` (estendida, já existente desde `013`)

Ramo PitTec: somente o provider designado pode responder a uma oferta `PENDING` não expirada.
`.accept` marca `ACCEPTED`, copia o ponto exato do cliente para `client_current_locations` e remove
a linha de discovery exata do provider. `.reject` marca o candidato/atendimento e chama o helper de
avanço sem repetição. Uma resposta após expiração retorna o estado já avançado.

## `expire_pittec_offer`

Helper de backend/agendado; client iOS pode acionar um wrapper autorizado por polling (fallback de
Realtime, `research.md §6`), mas o relógio do dispositivo nunca decide a expiração.

## `get_my_active_pittec_dispatch`

```swift
let snapshot: PitTecDispatchSnapshot? = try await client
    .rpc("get_my_active_pittec_dispatch")
    .execute()
    .value
```

Retorna no máximo um despacho PitTec ativo para o caller (cliente ou provider). Garante
`dispatchKind` em toda resposta; um `dispatch_kind` futuro desconhecido falha fechado com
`.unsupportedDispatch`, nunca tratado como `.browse`.

## `cancel_pittec_search`

Usada pelo cliente solicitante antes do aceite. Aceita somente `SEARCHING`/`AWAITING_PROVIDER`
pertencente ao cliente. Motivo não é exigido antes do aceite.

## `arrive_pittec_appointment`

Provider confirma "Cheguei". Somente o provider designado; somente despacho PitTec; status deve ser
`ACCEPTED`. Transição atômica para `IN_PROGRESS`, define `arrivedAt` uma vez, incrementa revisão.

## `complete_mobile_appointment` / `cancel_mobile_appointment` (estendidas, já existentes desde `013`)

Para `PITTEC_AUTO_SEQUENTIAL`: conclusão exige `IN_PROGRESS` e só o provider designado pode
concluir; cancelamento exige motivo (`trim`, obrigatório), aceita cliente ou provider designado em
`ACCEPTED`/`IN_PROGRESS`. Cancelamento do cliente termina a busca; cancelamento do provider avança
para o próximo candidato elegível sem repetir o cancelador.

## Error codes (inalterados)

```swift
enum PitTecErrorCode: String, Decodable {
    case authRequired = "AUTH_REQUIRED"
    case clientRequired = "CLIENT_REQUIRED"
    case providerRequired = "PROVIDER_REQUIRED"
    case pittecServiceRequired = "PITTEC_SERVICE_REQUIRED"
    case invalidLocation = "INVALID_LOCATION"
    case staleLocation = "STALE_LOCATION"
    case activeDispatchExists = "ACTIVE_PITTEC_DISPATCH_EXISTS"
    case offerExpired = "OFFER_EXPIRED"
    case revisionConflict = "REVISION_CONFLICT"
    case invalidTransition = "INVALID_TRANSITION"
    case cancellationReasonRequired = "CANCELLATION_REASON_REQUIRED"
    case noProvider = "NO_PROVIDER"
    case unsupportedDispatch = "UNSUPPORTED_DISPATCH"
}
```

Cada código mapeia para uma ação de UI específica (restaurar snapshot, reabrir diálogo com
validação, refresh sem retry cego, etc.) — mesmo comportamento do Android, ver spec Android original
para a tabela completa de mapeamento se necessário.

## Security acceptance criteria (inalterados)

Usuários anônimos não executam nenhuma RPC; um cliente não forja resposta de provider nem lê
identidades de candidato; um provider não inspeciona a coordenada da solicitação antes de aceitar;
DML direto não contorna as transições da RPC; operações concorrentes de aceite/timeout/cancelamento
produzem um único ramo terminal válido; payloads de Realtime contêm apenas ID/revisão/estado, nunca
coordenadas.
