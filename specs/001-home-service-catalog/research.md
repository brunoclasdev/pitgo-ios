# Phase 0 Research: Catálogo de Serviços na Homepage (iOS)

## 1. Toolchain e alvo mínimo de iOS

**Decision**: Xcode estável mais recente disponível, Swift 6 (modo de linguagem `Swift 6`),
**iOS Deployment Target 17.0**, projeto de app único (sem workspace multi-target nesta feature).

**Rationale**: iOS 17 traz `NavigationStack` maduro, `@Observable` (macro de observação sem
boilerplate de `@Published`) e `ScrollView`/`List` com preservação de estado adequada — a base que
a constituição do app iOS assume como padrão. Não há motivo de compatibilidade para mirar um iOS
mais antigo nesta feature puramente local.

**Alternatives considered**:
- iOS 16 mínimo (só `NavigationStack`, sem `@Observable`): rejeitado — obrigaria usar
  `ObservableObject`/`@Published` em todo o app só para manter compatibilidade com 2 versões a
  menos de iOS, sem requisito de produto pedindo isso.
- iOS 15 ou anterior (`NavigationView`): rejeitado — `NavigationView` é a API antiga, já substituída
  pela constituição por `NavigationStack`.

## 2. Modo de concorrência do Swift

**Decision**: Habilitar o modo de concorrência estrita do Swift 6 (`SWIFT_STRICT_CONCURRENCY =
complete`) desde o primeiro commit do projeto.

**Rationale**: Adotar concorrência estrita desde o início evita uma migração dolorosa depois que o
app já tiver dezenas de Views/ViewModels. Esta feature não tem I/O nem estado compartilhado entre
threads, então o custo de habilitar agora é próximo de zero.

**Alternatives considered**: Modo mínimo/desabilitado por enquanto — rejeitado; adiar a decisão só
acumula dívida técnica sem benefício para uma feature já 100% síncrona/local.

## 3. Dependências (Swift Packages)

**Decision**: Nenhum Swift Package externo nesta feature. Somente SwiftUI, Foundation e SF Symbols
do próprio SDK da Apple.

**Rationale**: O catálogo é local, em memória, sem rede, banco ou terceiros. Adicionar
`supabase-swift` ou qualquer outro pacote aqui seria dependência sem uso atual, na contramão do
Princípio I.

**Alternatives considered**: Adiantar a configuração do `supabase-swift` "para já deixar pronto" —
rejeitado por YAGNI; entra na feature que efetivamente precisar de rede/autenticação (equivalente
iOS de `004-configure-supabase`).

## 4. Fonte local e estado MVVM

**Decision**: `HomeViewModel` (`@Observable`, `@MainActor`) expõe um `HomeUiState` imutável com
exatamente cinco categorias locais e ordenadas, preenchido no `init`. Sem Repository, Use Case nem
estados de Loading/Error/Empty.

**Rationale**: Idêntico ao raciocínio do app Android — não há I/O nem operação assíncrona; um
Repository que só devolve constantes seria uma camada cerimonial. A View observa o `@Observable`
diretamente.

**Alternatives considered**: Repository local — rejeitado, mesma razão do plano Android. Lista
criada direto na View — rejeitado; a constituição atribui estado de tela ao ViewModel.

## 5. Layout responsivo e acessível

**Decision**: `NavigationStack` + `ScrollView` com `LazyVGrid(columns: [GridItem(.adaptive(minimum:
160))])`, `id` estável por categoria. Cada card é um único elemento de acessibilidade
(`.accessibilityElement(children: .combine)`) com rótulo "{nome}, buscar prestadores", texto sem
truncamento (`.fixedSize(horizontal: false, vertical: true)` ou `lineLimit(nil)`) e área de toque
mínima de 44×44pt (HIG).

**Rationale**: `LazyVGrid` com coluna adaptável responde à largura real do dispositivo (iPhone
compacto, iPhone grande, iPad, Slide Over/Split View) sem layouts duplicados por `size class`,
equivalente direto ao `GridCells.Adaptive` usado no Android. Um único elemento de acessibilidade
evita foco duplicado entre ícone e texto — mesmo racional do Android com `mergeDescendants`.

**Alternatives considered**: Grade de colunas fixas — rejeitada, mesma razão do Android (adaptação
ruim em janelas grandes/estreitas). `Grid`/`GridRow` (grade não-lazy): rejeitada para uma lista que
pode crescer; `LazyVGrid` é a análoga direta e recomendada pela Apple para este caso.

## 6. Navegação e limite da busca de prestadores

**Decision**: `HomeView` não conhece `NavigationPath`; expõe um closure `onCategorySelected:
(ServiceCategoryID) -> Void`. Um `PitGoRoutes: Hashable` (`enum`) centraliza os destinos, incluindo
`.providerSearch(categoryID: ServiceCategoryID)`. O host de navegação (`PitGoRootView`) mantém o
`@State private var path = NavigationPath()`, empilha a rota via `.navigationDestination(for:
PitGoRoute.self)` e renderiza uma tela mínima de entrada da busca (nome da categoria + voltar).

**Rationale**: Mesmo contrato do Android — só o identificador estável atravessa a fronteira, nunca
o objeto completo. Um `enum Hashable` é o equivalente direto e type-safe do route pattern
`provider-search/{categoryId}` usado no Compose, sem precisar de strings nem de bibliotecas de
serialização.

**Alternatives considered**: Passar o `ServiceCategory` completo pela `NavigationPath` — rejeitado,
mesmo motivo do Android (acoplamento, restauração frágil). String bruta como rota — rejeitada; o
`enum Hashable` já dá tipagem sem custo extra em SwiftUI moderno.

## 7. Toques repetidos, retorno e estado efêmero

**Decision**: A seleção só é aceita quando nenhuma navegação para o mesmo destino já está em
andamento — controlado com uma flag local simples (`@State private var isNavigating`) resetada
quando a `NavigationPath` volta ao tamanho anterior, mais a checagem natural do SwiftUI de que
`navigationDestination` não duplica a mesma view value já no topo da pilha. A posição de rolagem é
preservada automaticamente pelo SwiftUI: como a `HomeView` não é destruída ao empilhar um destino
(fica apenas fora de tela), seu `ScrollView`/`LazyVGrid` mantém o estado sem código adicional —
diferença notável do Compose, que exige `rememberLazyGridState` explícito para o mesmo efeito.

**Rationale**: SwiftUI não tem um equivalente direto a `dropUnlessResumed`, mas o problema que ele
resolve (toque duplo empilhando duas vezes) é resolvido de forma mais simples aqui, porque a View
de origem continua viva na pilha de navegação em vez de ser recriada.

**Alternatives considered**: Debounce por tempo — rejeitado, mesmo motivo do Android (pode bloquear
uma ação legítima). Evento one-shot armazenado no ViewModel — rejeitado; SwiftUI já resolve isso
via identidade de View, adicionar estado seria complexidade sem benefício.

## 8. Migração do template padrão do Xcode

**Decision**: Substituir o `ContentView.swift` gerado pelo template ("Hello, world") pelo
`PitGoRootView` (host de navegação) chamando `HomeView`. Manter `pitgoApp.swift` como ponto de
entrada (`@main`), `Assets.xcassets` (AppIcon/AccentColor) reaproveitados pelo design system.

**Rationale**: O projeto ainda é o template padrão do Xcode, sem comportamento de produto a
preservar — mesma situação do scaffold Android baseado em XML/JNI que a spec 001 original migrou.

**Alternatives considered**: Manter `ContentView.swift` como wrapper e só injetar `HomeView` dentro
dele sem renomear — aceitável como detalhe de implementação, mas o plano usa nomes que já refletem
a real responsabilidade (`PitGoRootView`) para não herdar o nome genérico do template
indefinidamente.

## Resolution Status

Todas as decisões técnicas estão resolvidas e não restam pendências para o design.
