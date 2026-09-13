# Data Model: Solicitar Atendimento (iOS)

## Overview

Os dados são locais e temporários. O catálogo e o veículo demonstrativo são fontes compartilhadas
entre Home e RequestService; a View recebe somente o identificador do serviço e deriva nome,
ícone, endereço e preço dessas fontes. Não há entidade de atendimento persistida, DTO, backend,
cache, localização real ou dados de cartão.

## DemoServiceID

Identificador canônico e estável transportado pela navegação.

```swift
enum DemoServiceID: CaseIterable {
    case battery, oilChange, tires, dashboardLight, smallRepairs, carWontStart
}
```

| Case | Display order | Starting price (BRL) |
|---|---:|---:|
| `.battery` | 0 | 320 |
| `.oilChange` | 1 | 220 |
| `.tires` | 2 | 180 |
| `.dashboardLight` | 3 | 150 |
| `.smallRepairs` | 4 | 260 |
| `.carWontStart` | 5 | 280 |

## DemoService

```swift
struct DemoService: Identifiable {
    let id: DemoServiceID
    let name: LocalizedStringResource
    let startingPrice: Int // > 0
    let symbolName: String
    let displayOrder: Int
}
```

O lookup usa igualdade exata do `DemoServiceID` (`enum` — não há representação textual ambígua).
Não existe serviço padrão para entrada inválida.

## DemoVehicle

```swift
struct DemoVehicle {
    let model: LocalizedStringResource   // "BMW 320i M Sport"
    let year: Int                         // 2020
    let plate: LocalizedStringResource    // "PGO-2A20"; reutilizada pela Home, não exibida aqui
    let address: LocalizedStringResource  // "Av. Paulista, 1500 · São Paulo"
    let symbolName: String
}
```

RequestService formata veículo como `"\(model) · \(year)"` e expõe o endereço separadamente.

## PaymentMethod

Forma de pagamento exclusivamente selecionável para a simulação.

```swift
enum PaymentMethod: CaseIterable {
    case pix, credit, debit // pix é o valor inicial
}
```

Regras:

- exatamente um valor existe em todo estado `.content`;
- selecionar um valor substitui atomicamente o anterior;
- não há dados de conta, cartão, autorização ou cobrança.

## SubmissionStatus

Estado local da ação mockada, sem equivalência com um atendimento real.

```swift
enum SubmissionStatus { case ready, triggered }
```

### State transition

```text
.ready --first accepted tap--> .triggered
.triggered --additional tap--> .triggered
```

Não há transição para PENDING/ACCEPTED/Booking, pois nenhum atendimento é criado.

## RequestServiceUiState

Tipo raiz mutuamente exclusivo.

```swift
enum RequestServiceUiState {
    case content(RequestServiceContent)
    case invalidService
}

struct RequestServiceContent {
    let selectedService: DemoService
    let vehicle: DemoVehicle
    var problemDescription: String = "" // opcional, multiline, temporária
    let estimatedArrival: LocalizedStringResource // "20-40 min"
    var paymentMethod: PaymentMethod = .pix
    var submissionStatus: SubmissionStatus = .ready

    var address: LocalizedStringResource { vehicle.address }
    var estimatedPrice: Int { selectedService.startingPrice }
}
```

`.invalidService` é usado quando o argumento está ausente, desconhecido ou não corresponde a
nenhum `DemoServiceID`. Não contém serviço, preço, formulário ou fallback; oferece mensagem e
retorno.

## Bottom tab model (compartilhado com `002`)

| Case | Label | Selected nesta feature |
|---|---|---|
| `.home` | Início | Yes |
| `.services` | Serviços | No |
| `.garage` | Garagem | No |
| `.appointments` | Atendimentos | No |
| `.profile` | Perfil | No |

Nesta etapa, selecionar outra aba produz feedback e não muda seleção nem conteúdo funcional.

## Relationships and invariants

```text
DemoServiceCatalog 1 ─── 6 DemoService
RequestServiceUiState ─── .content(RequestServiceContent) | .invalidService
RequestServiceContent 1 ─── 1 DemoService
                       1 ─── 1 DemoVehicle
                       1 ─── 1 PaymentMethod
                       1 ─── 1 SubmissionStatus
```

- IDs e ordens do catálogo não se repetem (`CaseIterable`, sem duplicatas possíveis).
- Nome, ícone e preço são sempre obtidos do mesmo `DemoService`.
- Trocar descrição ou pagamento não altera serviço, veículo, endereço, chegada ou preço.
- `.invalidService` nunca contém preço anterior nem substitui o ID por Bateria.
- `.triggered` impede nova execução do callback enquanto a View existir.
- Nenhum estado contém referência de navegação, credencial, coordenada, token ou dado de cartão.
- O estado existe somente durante a instância da View; términação do app não exige restauração da
  descrição ou pagamento.

## Navigation state transitions

```text
HOME --select valid DemoServiceID--> REQUEST_SERVICE(.content)
HOME --select invalid/missing DemoServiceID--> REQUEST_SERVICE(.invalidService)
REQUEST_SERVICE --Back/swipe--> HOME
REQUEST_SERVICE --bottom tab--> REQUEST_SERVICE
```

- A pilha normal preserva Welcome e Home abaixo de RequestService.
- Seleções rápidas do mesmo card criam no máximo um destino no topo (ver `research.md`).
- Em entrada direta inválida sem Home na pilha, a ação de retorno usa Home como fallback seguro.
