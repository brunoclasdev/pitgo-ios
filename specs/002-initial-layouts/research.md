# Research: Layouts iniciais do PitGo (iOS)

## 1. Base técnica e dependências

**Decision**: manter a configuração de `001-home-service-catalog`: Swift 6, iOS 17+, sem nenhum
Swift Package externo. Nenhuma dependência será adicionada nesta feature.

**Rationale**: SwiftUI, Foundation e SF Symbols cobrem gradiente, rolagem, grade, estado e
navegação. `supabase-swift`, SwiftData, Nuke ou qualquer biblioteca de ícones não resolvem
requisito atual.

**Alternatives considered**: adiantar `supabase-swift` "para já deixar pronto" — rejeitado por
YAGNI, mesma razão de `001`.

## 2. Relação com a feature anterior

**Decision**: a feature 002 substitui o contrato visual e comportamental da Home de `001`. O
grafo ativo conterá somente `WelcomeView` e `HomeView`; `PitGoRoute.providerSearch`, o modelo
`ServiceCategory` e `ProviderSearchEntryView` de `001` serão removidos quando não tiverem outro
consumidor. A documentação de `001` permanece como histórico.

**Rationale**: idêntico ao raciocínio do app Android — a nova Home exige seis serviços com preços
e feedback sem navegação; manter as duas implementações criaria fontes de verdade incompatíveis.

**Alternatives considered**: criar `HomeV2View`; mesclar os dois catálogos; preservar a rota de
prestadores "para o futuro". Todas violam YAGNI.

## 3. MVVM e estado local

**Decision**: `WelcomeViewModel` (`@Observable`) expõe `WelcomeUiState` com três benefícios;
`HomeViewModel` (`@Observable`) expõe um único `HomeUiState` com perfil, veículo, diagnóstico,
seis serviços, cinco itens inferiores e `.home` como seleção. Estados preenchidos imediatamente no
`init`; sem Loading/Error/Empty, sem Repository ou Use Case.

**Rationale**: mesmo racional do Android — cada ViewModel representa o conteúdo local da própria
feature, sem inventar fonte de dados.

**Alternatives considered**: Welcome sem ViewModel (por ser estática) — rejeitado, quebraria o
padrão MVVM-por-feature adotado desde `001`. ViewModel compartilhado entre as duas telas —
rejeitado, acopla features sem necessidade.

## 4. Layout responsivo da Welcome

**Decision**: `ZStack` com `LinearGradient(colors: [Color(hex: "#7C32E8"), Color(hex: "#5520A8")],
startPoint: .top, endPoint: .bottom)` cobrindo toda a tela, independente do `colorScheme`.
Wordmark, título, subtítulo, benefícios e ações ficam em uma única `ScrollView` vertical com
`.safeAreaPadding()` mais 24pt laterais. Sem alturas fixas nem `Spacer()` forçando distribuição
dentro do conteúdo rolável.

**Rationale**: um `LinearGradient` nativo dispensa asset de imagem; `ScrollView` mantém todos os
botões alcançáveis em telas baixas, paisagem e Dynamic Type grande — mesmo racional do
`verticalScroll` do Android.

**Alternatives considered**: imagem de fundo; layout sem scroll; bloco de ações fixo no rodapé.
Todos prejudicam adaptação, mesma conclusão do plano Android.

## 5. Home com conteúdo único e barra fixa

**Decision**: `TabView` (barra inferior nativa) com a aba Início hospedando um `ScrollView` +
`LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())])` de duas colunas fixas.
Cabeçalho, veículo, endereço, diagnóstico e título ocupam a largura toda (`.gridCellColumns(2)`);
os seis serviços ocupam uma célula cada.

**Rationale**: `TabView` é o componente nativo de barra inferior fixa do iOS (equivalente direto
ao `Scaffold(bottomBar = NavigationBar)`), com os 5 destinos como `.tabItem`. Duas colunas fixas
são requisito explícito; `LazyVGrid` com `GridItem(.flexible())` × 2 garante exatamente isso, sem
a adaptação usada em `001` (lá o número de colunas *deveria* variar; aqui a spec pede duas fixas).

**Alternatives considered**: barra customizada fora do `TabView` — rejeitada, componente nativo já
cobre acessibilidade e estado selecionado sem código extra. `GridItem(.adaptive(minimum:))` —
rejeitado aqui porque contradiz o requisito explícito de duas colunas (diferente de `001`, que
pedia adaptação).

## 6. Design system e temas

**Decision**: estender `Core/DesignSystem/Colors.swift` com a identidade solicitada e papéis
semânticos Light/Dark. `WelcomeView` desenha seu gradiente fixo (não usa `PitGoTheme`'s cores de
fundo); `HomeView` usa somente `PitGoTheme`/`@Environment(\.colorScheme)`. Nenhuma cor é
hardcoded fora do design system.

**Rationale**: a clarificação exige Welcome estável e Home seguindo o sistema — dois tratamentos
de cor coexistindo no mesmo design system, sem duplicar tokens.

**Alternatives considered**: segundo `Theme` completo só para Welcome — rejeitado, aumenta
duplicação sem necessidade (é só um gradiente fixo, não uma paleta inteira).

## 7. Ícones e recursos

**Decision**: usar SF Symbols nativos onde há um símbolo semanticamente coerente (bateria, carro,
localização, check/verificado); criar assets vetoriais locais só para os que não têm SF Symbol
equivalente satisfatório. Wordmark é `Text("PitGo")` estilizado, não imagem. Todo texto visível e
acessível fica no Strings Catalog.

**Rationale**: SF Symbols escalam com Dynamic Type automaticamente, já respeitam
Light/Dark/contraste e dispensam qualquer asset — vantagem que o Android não tem (lá, tudo é vetor
local desenhado à mão). Isso reduz a superfície de manutenção em relação ao plano Android.

**Alternatives considered**: todos os ícones como assets locais (paridade 1:1 com o Android) —
rejeitado; usar SF Symbols quando disponíveis é a prática nativa recomendada pela Apple e reduz
trabalho sem perder consistência visual.

## 8. Interação e acessibilidade

**Decision**: cards usam `Button` com `.buttonStyle(.plain)` + um efeito de destaque ao toque
(`.opacity`/`.scaleEffect` condicional a `isPressed`, ou o feedback padrão do próprio `Button`).
Diagnóstico e serviços emitem closures e permanecem na Home; itens inferiores inativos do `TabView`
não existem como conceito (o próprio `TabView` só permite ter uma aba selecionada por vez — ver
`data-model.md`). Cada card é um único elemento de acessibilidade
(`.accessibilityElement(children: .combine)`), ícones redundantes marcados
`.accessibilityHidden(true)`, headings com `.accessibilityAddTraits(.isHeader)`, alvos mínimos de
44×44pt.

**Rationale**: cumpre a clarificação de feedback sem criar destino, mesmo racional do Android.

**Alternatives considered**: cards sem `Button` (só `.onTapGesture`) — rejeitado; `Button` já
integra VoiceOver, alvo de toque e feedback visual "de graça".

## 9. Navegação e proteção contra duplicação

**Decision**: `PitGoRootView` mantém `@State private var showHome = false` (ou usa
`NavigationStack` com uma `path` de um único elemento). "Entrar" seta `showHome = true` apenas se
ainda não estiver `true`; ao voltar da Home, o SwiftUI já reverte o estado via
`.navigationDestination`/dismissal nativo, então uma nova seleção de "Entrar" funciona
normalmente. Sem `popUpTo` equivalente necessário — a pilha é sempre `[Welcome, Home]`.

**Rationale**: mesmo resultado do `dropUnlessResumed` + `launchSingleTop` do Android, com menos
mecanismo: uma flag booleana simples basta porque o SwiftUI não tem o problema de múltiplos
eventos de clique disparando corrotinas concorrentes do jeito que o Android tem.

**Alternatives considered**: debounce temporal, evento one-shot no ViewModel — rejeitados, mesma
razão do Android (desnecessário para duas rotas sem argumento).

## 10. Validação

**Decision**: executar `xcodebuild ... clean build` e o roteiro manual em simulador/dispositivo
iOS 17+, sem criar testes automatizados.

**Rationale**: a constituição e o usuário proíbem geração de testes nesta feature.

**Alternatives considered**: testes unitários de constantes e testes de UI com `XCUIApplication`.
Não autorizados nesta entrega.
