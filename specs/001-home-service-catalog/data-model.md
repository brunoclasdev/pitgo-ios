# Data Model: Catálogo de Serviços na Homepage (iOS)

## Scope

O modelo é totalmente local e em memória. Não existe esquema de banco, DTO remoto, cache ou
migração. Textos são localizados (`String(localized:)`/Strings Catalog) e ícones são SF Symbols ou
assets locais resolvidos somente pela View.

## ServiceCategoryID

Identidade canônica e estável de uma categoria.

```swift
enum ServiceCategoryID: String, Hashable, CaseIterable {
    case tireShop = "tire-shop"
    case vehicleElectrician = "vehicle-electrician"
    case battery = "battery"
    case tireChange = "tire-change"
    case mechanic = "mechanic"
}
```

| Case | Meaning | Raw value (route) |
|------|---------|--------------------|
| `.tireShop` | Borracharia | `tire-shop` |
| `.vehicleElectrician` | Eletricista veicular | `vehicle-electrician` |
| `.battery` | Assistência de bateria | `battery` |
| `.tireChange` | Troca de pneu | `tire-change` |
| `.mechanic` | Mecânico | `mechanic` |

### Validation rules

- Cada `rawValue` é único e não muda após publicado (é `String`, estável para navegação/logs).
- O `rawValue` usa apenas ASCII minúsculo e hífen.
- `CaseIterable` garante que só estes cinco casos existem nesta feature.

## ServiceCategory

Representa um item apresentável e selecionável do catálogo.

```swift
struct ServiceCategory: Identifiable, Hashable {
    let id: ServiceCategoryID
    let name: LocalizedStringResource
    let symbolName: String              // SF Symbol ou asset local
    let accessibilityAction: LocalizedStringResource // "Buscar prestadores de {categoria}"
    let displayOrder: Int
}
```

| Field | Type | Rules |
|-------|------|-------|
| `id` | `ServiceCategoryID` | Obrigatório e único no catálogo |
| `name` | `LocalizedStringResource` | Nome completo não vazio |
| `symbolName` | `String` | SF Symbol ou nome de asset válido em `Assets.xcassets`; ícone decorativo |
| `accessibilityAction` | `LocalizedStringResource` | Descreve "Buscar prestadores de {categoria}" |
| `displayOrder` | `Int` | Único, de 0 a 4 |

### Initial records

| displayOrder | id | Visible name |
|--------------|----|--------------|
| 0 | `.tireShop` | Borracharia |
| 1 | `.vehicleElectrician` | Eletricista veicular |
| 2 | `.battery` | Bateria |
| 3 | `.tireChange` | Troca de pneu |
| 4 | `.mechanic` | Mecânico |

## HomeUiState

Estado imutável observado pela homepage.

```swift
struct HomeUiState {
    let categories: [ServiceCategory] // exatamente 5, ordenadas por displayOrder
}
```

### State lifecycle

1. `HomeViewModel` (`@Observable`, `@MainActor`) é criado com o catálogo completo já no `init`.
2. O mesmo conteúdo é exposto imediatamente e permanece válido offline.
3. Recriação da View/ViewModel (ex.: app terminado e reaberto) reconstrói o mesmo catálogo
   determinístico — não há estado a restaurar via `@SceneStorage`.

Loading, Error e Empty não são estados válidos porque não existe fonte externa nem catálogo
opcional neste escopo.

## CategorySelection

Evento efêmero emitido pela View ao usuário tocar em um card.

| Field | Type | Rules |
|-------|------|-------|
| `categoryID` | `ServiceCategoryID` | Deve pertencer ao catálogo atual |

O evento não é persistido no ViewModel — é um closure síncrono (`onCategorySelected:
(ServiceCategoryID) -> Void`). O host de navegação converte o ID na rota `PitGoRoute
.providerSearch(categoryID:)`. Enquanto já houver uma navegação em andamento para a mesma seleção,
novos toques são ignorados (ver `research.md` §7).

## Relationships and invariants

- `HomeUiState` contém exatamente cinco `ServiceCategory`.
- Cada `ServiceCategory` possui um `ServiceCategoryID` exclusivo.
- Uma `CategorySelection` referencia exatamente uma categoria existente.
- O destino de busca recebe somente o `ServiceCategoryID`; nome, ícone e ordem não atravessam a
  fronteira de navegação.
- Nenhuma entidade contém localização, autenticação, dados pessoais ou dados de prestadores.
