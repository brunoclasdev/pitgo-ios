# Contract: Realtime Appointment Marker (iOS)

## Authorization (inalterado, backend compartilhado)

- Tópico privado `appointment-location:<appointmentId>`.
- Somente cliente/provider participantes assinam ou obtêm snapshot.
- Publish continua por RPC e exige provider MOBILE elegível em `ACCEPTED`/`IN_PROGRESS`.
- Discovery pública nunca lê o stream.
- Nenhuma service-role/admin key entra no bundle iOS.

## Repository events

```swift
enum AppointmentLocationEvent {
    case snapshot(AppointmentProviderLocation?)
    case upsert(AppointmentProviderLocation)
    case removed(LocationRevision)
    case ended(TerminalAppointmentStatus)
    case sessionExpired
    case offline
    case failure
}
```

`Error` bruto, headers, tokens, IDs em log e payload bruto não chegam à UI.

## Subscription sequence

1. Validar sessão/`appointmentID`.
2. Criar o canal privado e iniciar a observação de INSERT/UPDATE/DELETE/ENDED (`RealtimeChannelV2`
   do `supabase-swift`, via `AsyncStream`).
3. Autenticar (`client.realtime.setAuth()`) e assinar, aguardando confirmação.
4. Buscar o snapshot via RPC.
5. Reduzir snapshot e eventos de broadcast pela mesma ordenação (`LocationRevision`).
6. Em reconexão, repetir auth + subscribe + snapshot.
7. Ao finalizar (View desaparece/logout), remover o canal numa `Task` desacoplada do escopo que pode
   ser cancelado (equivalente ao `NonCancellable` do Kotlin), garantindo que a remoção do canal
   sempre complete.

Os observadores de evento antecedem o snapshot. `.snapshot(nil)` é explícito; um snapshot atrasado
não apaga um evento novo já recebido.

## Ordering/tombstone (inalterado, mesma lógica client-side do Android)

A revisão é `(publishedAt, version)` em ordem lexicográfica (`LocationRevision: Comparable`).

- `.upsert` só é aplicado se maior que `acceptedRevision`.
- `DELETE` lê o registro `old`, remove o marcador e conserva o tombstone.
- Um evento igual ou mais antigo é ignorado.
- Uma reinserção com `version = 1` é aceita se `publishedAt` for posterior ao tombstone.
- `capturedAt` não ordena o stream.
- `.ended` é terminal e ignora qualquer evento posterior.

## SQL hardening (já aplicado, backend compartilhado)

A migration de hardening (`20260821030000_appointment_location_stream_hardening.sql`, já existente
via `009 §0`) garante: autenticação do participante antes de considerar o status; `ENDED` para
COMPLETED/CANCELLED; `EMPTY` para atendimento ativo sem linha; `LIVE`/`STALE` com revisão
server-side quando há linha; join de tópico permitido a participantes mesmo após terminal; Broadcast
`ENDED` privado e remoção da linha ao terminal; publish proibido fora de status ativo. Nenhum
histórico, grant direto ou acesso a terceiro é criado.

## ViewModel

`AppointmentTrackingViewModel` (`@Observable`, `@MainActor`) mantém `acceptedRevision`/tombstone, a
última posição não terminal, `TrackingDataState`, `MapSurfaceState`, uma única assinatura visível e
um timer (`Task` com `Task.sleep`) somente enquanto há posição.

- idade `<=30s` → live; `>30s` → stale;
- offline/falha conserva a última posição como stale;
- mudança de sessão/`.ended` limpa a posição antes de qualquer refresh/navegação;
- `CancellationError` é relançado, nunca tratado como falha de domínio;
- View oculta (`.onDisappear`) cancela a assinatura/timer e limpa a posição da UI;
- View visível (`.onAppear`/`.task`) cria uma nova assinatura.

## MapLibre boundary

O ViewModel entrega `MapMarkerSpec`, nunca GeoJSON/`MLNStyle`/`MLNMapView`. O `Coordinator` do
`UIViewRepresentable` converte:

- `.live` → feature com ícone/label "ao vivo";
- `.stale` → ícone/label "desatualizado";
- vazio/`.ended`/sessão expirada → `FeatureCollection` vazia.

Uma atualização aceita chama `source.shape = ...` na source já instalada. Um reload de estilo
reaplica o modelo mais recente; um callback iniciado antes de `.ended` não pode restaurar a
coordenada. Não há interpolação, rota ou histórico.
