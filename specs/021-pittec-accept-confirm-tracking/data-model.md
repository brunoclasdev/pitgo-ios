# Phase 1 Data Model: Aceite do PitTec com confirmação de valor e mapa conjunto

## Entidades alteradas

### `PitTecAppointment` (existente — `Features/PitTec/Model/PitTecModels.swift`)

Ganha um único campo novo, opcional, no mesmo padrão de `acceptedAt`/`arrivedAt` já existentes:

| Campo | Tipo | Descrição |
|---|---|---|
| `appointmentID` | `UUID` | *(inalterado)* |
| `status` | `AppointmentStatus` | *(inalterado)* — `pending`/`accepted`/`inProgress`/`providerRejected`/`expired`/`completed`/`cancelled` |
| `responseDeadline` | `Date?` | *(inalterado)* |
| `revision` | `Int64` | *(inalterado)* |
| `acceptedAt` | `Date?` | *(inalterado)* |
| `arrivedAt` | `Date?` | *(inalterado)* |
| `cancelledBy` | `CancelledBy?` | *(inalterado)* |
| **`confirmedAt`** | **`Date?`** | **Novo.** `nil` enquanto o cliente não confirmou o valor após o aceite; preenchido pela RPC `confirm_pittec_appointment` (`contracts/confirm-pittec-value-rpc.md`). Só é significativo quando `status` é `accepted`/`inProgress` — em qualquer outro status, é irrelevante para a UI. |

**Coding key**: `confirmed_at` (mesmo padrão snake_case dos demais campos de data).

**Ciclo de vida**: `nil` no momento em que `status` passa a `accepted` (aceite do PitTec); recebe um
timestamp uma única vez, quando `confirm_pittec_appointment` é chamada com sucesso pelo cliente;
nunca é limpo de volta a `nil` no mesmo atendimento (é preenchido no máximo uma vez, como
`acceptedAt`/`arrivedAt`).

## Sub-estado derivado (não é uma entidade nova, é uma leitura do campo acima)

Nem `PitTecClientUiState` nem `ProviderDispatchUiStatePitTec` ganham um caso novo (ver
`research.md` §4). A View deriva o sub-estado assim:

| `appointment.status` | `appointment.confirmedAt` | Tela do **cliente** | Tela do **PitTec** |
|---|---|---|---|
| `accepted`/`inProgress` | `nil` | Card de confirmação de valor (Confirmar/Recusar) | Tela "aguardando confirmação do cliente" (sem ações) |
| `accepted`/`inProgress` | presente | Mapa de acompanhamento, enquadrando cliente + PitTec juntos | Mapa de acompanhamento, enquadrando PitTec + cliente juntos |

Qualquer outro `status` (searching/optionFound/awaitingProvider/completed/cancelled) segue
exatamente o comportamento já existente hoje, inalterado por esta feature.

## Nenhuma entidade nova de domínio

`Atendimento PitTec`, `Posição do PitTec`, `Marcador de PitTec` — todos já existentes, sem mudança
de forma além do campo único acima. Nenhuma tabela, DTO ou modelo de UI adicional é criado.

## Dependência externa (fora deste repositório)

Uma coluna equivalente a `confirmed_at` precisa existir na tabela de atendimentos do backend
compartilhado, e ser exposta tanto na projeção do cliente quanto na do provider de
`get_my_active_pittec_dispatch()`/`list_nearby_pittecs`-adjacent snapshot — ver
`contracts/confirm-pittec-value-rpc.md` para o contrato completo que quem for implementar essa parte
deve seguir.
