# Research: Solicitar Atendimento (iOS)

## 1. Base técnica e dependências

**Decision**: manter integralmente Swift 6, iOS 17+, sem Swift Package novo.

**Rationale**: SwiftUI já oferece navegação, `@Observable`, componentes de formulário, layout
responsivo e semântica de acessibilidade suficientes para esta tela local.

**Alternatives considered**: mesma lista de `002` (rede, persistência, DI, bibliotecas de ícone) —
rejeitadas por ausência de requisito.

## 2. Contrato de navegação e argumento

**Decision**: estender `PitGoRoute` com `.requestService(serviceID: DemoServiceID?)`. A Home emite
somente o `DemoServiceID` do card tocado; o parâmetro é opcional apenas para representar
corretamente a ausência (não há necessidade de parsear uma `String`, como no Android).

**Rationale**: um `enum Hashable` como argumento de rota já impede por construção qualquer valor
"desconhecido" — a categoria de erro "ID com case diferente" do Android simplesmente não existe em
Swift. Nome, ícone e preço continuam fora da rota.

**Alternatives considered**: transportar o `DemoService` completo — rejeitado, mesma razão do
Android (duplicaria a fonte de verdade do preço).

## 3. Resolução do serviço e propriedade dos dados

**Decision**: mover `DemoServiceID`, `DemoService` e o catálogo de Home para
`Core/Common/Model/DemoServiceCatalog.swift`. Mover `DemoVehicle` para
`Core/Common/Model/DemoVehicle.swift`. Home e RequestService importam essas fontes compartilhadas.

**Rationale**: mesmo racional do Android — dois consumidores reais, uma única fonte de verdade
para os valores 320/220/180/150/260/280.

**Alternatives considered**: duplicar mocks na nova feature — rejeitado pelo risco de divergência.

## 4. Estado MVVM e serviço inválido

**Decision**: `RequestServiceViewModel` (`@Observable`, `@MainActor`) recebe o `DemoServiceID?` no
`init` e expõe `RequestServiceUiState` (`enum` com `.content`/`.invalidService`). A resolução é
síncrona; não há `.loading`.

**Rationale**: o `enum` com associated value impede por construção que "conteúdo válido" e
"serviço nulo" coexistam — mais forte ainda que o sealed type do Android, porque o compilador
exige tratar os dois casos em todo `switch`.

**Alternatives considered**: `struct` única com propriedades opcionais — rejeitada, mesmos motivos
do Android (estados contraditórios representáveis).

## 5. Pagamento, descrição e ação simulada

**Decision**: `PaymentMethod` (`.pix`/`.credit`/`.debit`, inicial `.pix`) e `SubmissionStatus`
(`.ready`/`.triggered`). `onSubmit()` muda sincronamente `.ready → .triggered`, retornando se o
callback mock deve executar; toques em `.triggered` são ignorados e o `Button` some
`.disabled(true)` até a View ser recriada.

**Rationale**: mesmo racional do Android — a transição síncrona evita chamadas duplicadas sem
precisar de debounce, `Task` ou fluxo de efeitos.

**Alternatives considered**: `Task` com `Bool isSubmitting` — rejeitado, `enum` de dois casos é
mais explícito.

## 6. Shell, rolagem e teclado

**Decision**: `NavigationStack` (título + botão voltar nativos) + `TabView` fixo por baixo, com uma
única `ScrollView` para o corpo. `TextEditor` para a descrição (`.frame(minHeight: 120)`, sem
altura máxima rígida) e `.scrollDismissesKeyboard(.interactively)` para não bloquear o CTA/aviso.

**Rationale**: uma única superfície rolável evita rolagens aninhadas — mesmo racional do Android.
`NavigationStack`/`TabView` já entregam back/título/barra fixa sem controles manuais.

**Alternatives considered**: `TextField` com `axis: .vertical` em vez de `TextEditor` — viável, mas
`TextEditor` dá controle de altura mínima mais direto para "aproximadamente quatro linhas".

## 7. Cards, estimativas e pagamento responsivos

**Decision**: `InfoCard`, `EstimateCard` e um seletor de pagamento privados ao arquivo da View.
Estimativas usam `ViewThatFits` (lado a lado quando cabem, empilhadas quando não) ou checagem de
`horizontalSizeClass`/Dynamic Type. Pagamento é um grupo de `Button`s customizados com borda/fundo
reagindo ao estado selecionado, cada um um elemento de acessibilidade único.

**Rationale**: `ViewThatFits` é o equivalente nativo direto ao layout condicional manual que o
Android precisa construir à mão para "duas colunas quando cabe, uma quando não cabe" — vantagem do
SwiftUI aqui.

**Alternatives considered**: `HStack` fixo — rejeitado, mesma razão do Android (aperta conteúdo em
telas estreitas/Dynamic Type grande).

## 8. Ação gradiente e design system

**Decision**: `Button` com `.background(LinearGradient(colors: [.brandPurple, .darkPurple], ...))`,
`.clipShape(Capsule())`, largura máxima e altura mínima de 56pt. Reaproveitar cores/tipografia
existentes; SF Symbols para voltar, relógio e check (ver `002` research §7).

**Rationale**: `Button` preserva estado disabled, foco e VoiceOver enquanto o gradiente atende à
identidade visual — mesmo racional do Android.

**Alternatives considered**: `Rectangle` customizado com `.onTapGesture` — rejeitado, reimplementa
comportamento que `Button` já dá de graça.

## 9. Bottom tab bar e back stack

**Decision**: reutilizar a `TabView` de `002` sem alteração de modelo. RequestService é empilhado
via `NavigationStack` **dentro** da aba Início (`TabView { NavigationStack { HomeView() } .tabItem
{...} }`), então a barra permanece visível e fixa durante toda a navegação Home → RequestService.

**Rationale**: esse é exatamente o padrão idiomático SwiftUI para "barra de abas persistente +
navegação hierárquica dentro de uma aba" — corresponde ao requisito "mesma bottom navigation da
Home" sem duplicar componente nem criar acoplamento a `NavigationPath` de fora da feature.

**Alternatives considered**: `RequestServiceView` como uma nova aba — rejeitado, ela não é um
destino de nível superior, é uma continuação da jornada de Início.

## 10. Validação

**Decision**: `xcodebuild ... clean build` e roteiro manual em simulador/dispositivo iOS 17+, sem
testes automatizados.

**Rationale**: mesma decisão de `001`/`002`.

## Resolution status

Todas as decisões de Technical Context estão resolvidas; não restam pendências.
