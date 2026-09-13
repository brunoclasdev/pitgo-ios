# Contract: Provider address geocoding (shared Edge Function)

## Status: already implemented and deployed

`geocode-provider-address` e `refresh-provider-geocodes` são Edge Functions Deno já publicadas no
projeto Supabase compartilhado. Código/deploy são independentes de plataforma cliente — nenhuma
mudança de função é feita por esta feature iOS.

## Runtime boundary

Endpoint: Supabase Edge Function autenticada `geocode-provider-address`, invocada via
`supabase-swift`:

```swift
struct GeocodeVerificationResponse: Decodable { /* ver "Success" abaixo */ }

let response: GeocodeVerificationResponse = try await client.functions
    .invoke("geocode-provider-address", options: .init(body: requestPayload))
    .value
```

Autorização: sessão PROVIDER válida em `.authenticatedProviderOnboarding` ou fluxo de edição do
owner. A função valida o JWT/contexto de conta; nenhum ID de conta é aceito do corpo da requisição.

Request (`Encodable` Swift struct, mesmo shape JSON):

```json
{
  "address": {
    "street": "Av. Paulista",
    "number": "1500",
    "neighborhood": "Bela Vista",
    "zip_code": "01310200",
    "city": "São Paulo",
    "state": "SP",
    "country": "BR",
    "complement": null
  },
  "device_fix": {
    "latitude": -23.5613,
    "longitude": -46.6559,
    "accuracy_m": 24.5,
    "captured_at": "2026-08-21T15:00:00Z"
  }
}
```

`device_fix` vem de um `CLLocation` obtido por `CLLocationManager.requestLocation()` — nunca da
última posição conhecida em cache. A função só aceita endereços brasileiros estruturados, fixes de
alta qualidade e atuais, endpoint/máscara de campos fixos do Google, idioma pt-BR e região BR — nunca
aceita uma URL upstream arbitrária.

Success:

```json
{
  "outcome": "VERIFIED",
  "verification_id": "uuid",
  "normalized_address": "Av. Paulista, 1500 - Bela Vista, São Paulo - SP",
  "distance_m": 42.7,
  "requires_confirmation": false,
  "expires_at": "2026-08-21T15:15:00Z"
}
```

Falhas fechadas: `NO_MATCH`, `AMBIGUOUS_OR_PARTIAL`, `WRONG_REGION`, `FIX_TOO_OLD`,
`FIX_TOO_IMPRECISE`, `INVALID_ADDRESS`, `RATE_LIMITED`, `UPSTREAM_UNAVAILABLE`, `SESSION_BLOCKED`.
Payload bruto do Google, a chave de API e detalhes técnicos de erro nunca chegam à UI/logs do app
iOS.

O ID retornado referencia uma prova privada de 15 minutos. A resposta omite deliberadamente as
coordenadas canônicas — o cadastro consome a prova no servidor. Distância acima de 500m define
`requires_confirmation: true`; a UI iOS deve mostrar a distância e submeter uma confirmação
explícita.

## Retention and refresh (inalterado, backend-only)

- **Não há chave de mapa a gerenciar no client iOS**: diferente do Android (`MAPS_API_KEY` como
  manifest placeholder restrito por package/SHA-1), o MapLibre Native iOS aponta para o provedor de
  tiles gerenciado por URL de estilo/configuração de ambiente, sem exigir uma chave de SDK de mapa
  proprietário. Nenhuma chave de mapa entra no bundle iOS.
- A chave web de Geocoding é um Supabase Secret; nunca aparece em `Config/Secrets.xcconfig` nem em
  qualquer arquivo rastreado do repositório iOS.
- Persistência de `place_id`/coordenadas por no máximo 30 dias a partir do geocode (inalterado).
- `refresh-provider-geocodes` roda diariamente e renova linhas a partir do dia 25 (inalterado,
  backend-only — nenhuma ação do client).
- Uma divergência material de coordenada/endereço marca a linha para reverificação em vez de mover
  silenciosamente uma empresa. Linhas expiradas são excluídas da descoberta até renovação/
  reverificação.
- Atribuição/termos do provedor de tiles permanecem visíveis/obedecidos; chaves são separadas por
  ambiente (backend-only).

## iOS state contract

A View possui os launchers de permissão/settings (`CLLocationManager`, deep link para
`UIApplication.openSettingsURLString`); o ViewModel possui o estado de verificação
(`ProviderAddressVerificationState`, ver `data-model.md`). Editar qualquer campo do endereço cancela
uma requisição em andamento, invalida a prova e limpa a confirmação de divergência. O fix do
dispositivo vive só em memória e é limpo após sucesso/falha/navegação/troca de sessão.
