# UI and Navigation Contract: Homepage to Provider Search (iOS)

## Purpose

Definir a fronteira verificável entre o catálogo local da homepage e o início do fluxo de busca de
prestadores, sem incluir a listagem ou fontes de dados de prestadores.

## Home destination

- **Route**: raiz da `NavigationStack` (`PitGoRoute` não se aplica à Home; ela é o conteúdo raiz).
- **Input**: `HomeUiState` produzido por `HomeViewModel` (`@Observable`).
- **Output**: `onCategorySelected: (ServiceCategoryID) -> Void`.
- **Ownership**: `Features/Home`.
- **Navigation dependency**: nenhuma dentro de `HomeView`; o host de navegação
  (`PitGoRootView`) fornece o closure.

### UI contract

- Renderizar exatamente os cinco itens na ordem definida em `data-model.md`.
- Usar `ScrollView` + `LazyVGrid` adaptável à largura disponível.
- Tratar cada card como um único elemento de acessibilidade, com nome e finalidade acessíveis.
- Manter o nome completo com quebra de linha; não usar truncamento (`.lineLimit`) como
  comportamento normal.
- Preservar estado de rolagem ao retornar do destino seguinte (automático em SwiftUI — ver
  `research.md` §7).
- Funcionar sem internet, autenticação, localização ou dados pessoais.

## Provider-search entry destination

- **Route value**: `PitGoRoute.providerSearch(categoryID: ServiceCategoryID)`.
- **Argument**: `categoryID`, um dos casos de `ServiceCategoryID`.
- **Ownership**: fronteira mínima em `Features/Provider`; a futura busca substitui/expande o
  conteúdo sem alterar o contrato de entrada.
- **Current content**: título "Busca de prestadores", nome da categoria recebida e botão/gesto de
  voltar nativo do `NavigationStack`.
- **Out of scope**: lista de prestadores, disponibilidade, proximidade, rede, solicitação,
  pagamento e contratação.

### Navigation rules

1. O card emite somente seu `ServiceCategoryID`.
2. O host de navegação converte o ID na rota `PitGoRoute.providerSearch(categoryID:)` e o empilha
   via `path.append(...)`.
3. A seleção só é aceita quando nenhuma navegação para a mesma categoria já está em andamento
   (`isNavigating` local — ver `research.md` §7).
4. `.navigationDestination(for: PitGoRoute.self)` resolve a `enum` para a View de destino; não há
   duplicação porque a rota é empilhada uma única vez por seleção aceita.
5. O destino valida o `ServiceCategoryID` recebido (é um `enum` — valor inválido é
   irrepresentável em tempo de compilação, ao contrário de uma string bruta).
6. O gesto de borda ("swipe back") e o botão de voltar padrão removem o destino do topo da
   `NavigationPath` e revelam a mesma instância lógica da `HomeView`.

## Accepted values

| categoryID (rawValue) | Destination label |
|------------------------|--------------------|
| `tire-shop` | Borracharia |
| `vehicle-electrician` | Eletricista veicular |
| `battery` | Bateria |
| `tire-change` | Troca de pneu |
| `mechanic` | Mecânico |

## Invariants

- Um toque válido produz no máximo uma entrada nova na `NavigationPath`.
- Toques rápidos posteriores são ignorados enquanto a navegação para a mesma seleção está em
  andamento.
- O identificador recebido corresponde exatamente ao card selecionado.
- Nenhum objeto completo ou texto visível é usado como argumento de navegação — só o `enum`
  `ServiceCategoryID`.
- Rotas e construção de destino ficam centralizadas em `Core/Navigation` (`PitGoRoute` +
  `PitGoRootView`).
- `HomeView` permanece stateless em relação à navegação.
