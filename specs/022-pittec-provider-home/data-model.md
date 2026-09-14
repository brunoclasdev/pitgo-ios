# Data Model: Home do PitTec

Nenhuma tabela, coluna, RPC ou Edge Function nova no Supabase — esta feature só organiza dados já
existentes numa nova apresentação em 4 abas. As entidades abaixo são as já usadas por
`ProviderDashboardView`/`PitTecClientView`, aqui documentadas do ponto de vista desta tela.

## Provider (existente — `pitgo/Features/ProviderRegistration/Data/ProviderRegistrationDTOs.swift`)

Já decodificado de `public.providers`. Campos relevantes para esta feature:

| Campo | Uso nesta feature |
|---|---|
| `locationMode` | decide se esta home (PitTec) ou a `ProviderDashboardView` (Fixo/Móvel) é exibida |
| `available` | valor exibido/alternado pelo card de disponibilidade (aba Mapa) |
| `active` | condição (já existente) para a tracker publicar localização |
| `name`, `email` | exibidos na aba Perfil |

Sem novos campos.

## Posição atual do PitTec (nova exposição, mesma fonte)

Não é uma entidade persistida — é o último `DeviceLocationFix` (já existente,
`pitgo/Core/Location/...`) recebido pelo stream que `ProviderDiscoveryTracker` já consome para
publicar a localização de despacho. Passa a ser exposto (`private(set)`) para a `PitTecHomeViewModel`
usar como `centerCoordinate` de `PitGoMapView`.

| Campo | Tipo | Origem |
|---|---|---|
| `latitude`, `longitude` | `Double` | `DeviceLocationFix` (já existente) |
| `horizontalAccuracy` | `Double` | `DeviceLocationFix` (já existente) — não exibido, só disponível |
| `timestamp` | `Date` | `DeviceLocationFix` (já existente) — usado só para saber se o fix é recente |

## PitTecPricingInfo (novo, somente leitura)

Agregado fino lido de `public.provider_services` (via Postgrest, mesmo padrão de
`ProviderServiceRow`) filtrado pelo serviço com `dispatch_kind = PITTEC_AUTO_SEQUENTIAL`. Exibido
na aba Valores; não editável por esta feature (clarificação registrada em spec.md).

| Campo | Tipo | Origem |
|---|---|---|
| `price` | `Decimal` | `provider_services.price` |
| `serviceName` | `String` | `services.name` (join, mesmo padrão de `fetchOwnAggregate`) |

Sem estado/transição — é uma leitura pontual ao abrir a aba (com possibilidade de recarregar ao
puxar para atualizar, mesmo padrão de outras leituras simples do app).

## Atendimento PitTec ativo (existente — `PitTecDispatchSnapshot`/`PitTecAppointment`)

Já decodificado por `PitTecRepository.getActiveDispatch()` e já consumido por
`ProviderDashboardViewModel.checkPitTecIncoming()`. Nesta feature, o mesmo snapshot alimenta a aba
"Dados da corrida":

| Status (`AppointmentStatus`, já existente) | Exibição em "Dados da corrida" |
|---|---|
| nenhum atendimento ativo | mensagem vazia ("as informações aparecem aqui depois de aceitar uma solicitação") |
| `PENDING` | não exibido aqui — segue o fluxo existente de push automático para aceitar/recusar |
| `AWAITING_CLIENT_CONFIRMATION`, `AWAITING_PAYMENT` | resumo "aguardando o cliente" |
| `ACCEPTED`, `IN_PROGRESS` | resumo do atendimento em andamento (cliente, distância/rota se disponível) |

Nenhum novo status — reaproveita o `enum AppointmentStatus` já compartilhado com o backend.

## PitTecHomeTab (novo, local à View)

`enum` puramente de UI (não persistido), análogo ao `BottomItemID` já existente para o cliente:

```
enum PitTecHomeTab: CaseIterable, Hashable {
    case map, ride, values, profile
}
```

## PitTecHomeUiState (novo, local ao ViewModel)

Estado agregado da tela, seguindo o mesmo padrão de `enum` de estado único já usado em
`ProviderDashboardUiState`/`PitTecClientUiState` (sem `Bool`s paralelos):

```
enum PitTecHomeUiState {
    case content(ProviderSnapshot)
    case failure(ProviderDashboardFailureReason)  // reaproveita o enum já existente
}
```

A aba selecionada, o último fix de localização, o preço carregado e o atendimento ativo são
propriedades `private(set)` separadas na ViewModel (cada uma com seu próprio ciclo de
carregamento/erro quando aplicável) — não fazem parte deste estado principal, pelo mesmo motivo que
`ProviderDashboardViewModel` já trata `discoveryTracker`/`incomingAppointmentID` como propriedades
à parte do `state` principal.
