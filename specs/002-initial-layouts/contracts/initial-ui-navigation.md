# UI and Navigation Contract: Welcome → Home (iOS)

## Purpose

Definir a fronteira verificável entre as duas telas da feature, seus estados locais e as ações que
podem ou não alterar o destino. Não existe API, persistência nem argumento de navegação.

## Welcome destination

- **Role**: destino inicial do aplicativo (raiz do `PitGoRootView`).
- **Input**: `WelcomeUiState` produzido por `WelcomeViewModel`.
- **Outputs**:
  - `onCreateAccount()` — feedback visual; permanece em Welcome.
  - `onEnter()` — solicita navegação única para Home.
  - `onRegisterCompany()` — feedback visual; permanece em Welcome.
- **Ownership**: `Features/Welcome`.

### UI contract

- O gradiente ocupa toda a janela (`.ignoresSafeArea()` no fundo) e não muda entre Light/Dark.
- O conteúdo usa `.safeAreaPadding()`, 24pt laterais e uma única `ScrollView` vertical.
- Wordmark textual, título, subtítulo "Encontre assistência para bateria, óleo, pneus e muito mais,
  onde você estiver.", três benefícios e três ações permanecem alcançáveis.
- A View recebe closures e não conhece o estado de navegação do host.
- Os três benefícios aparecem na ordem definida em `data-model.md`.

## Home destination

- **Input**: `HomeUiState` produzido por `HomeViewModel`.
- **Outputs**:
  - `onDiagnosticTap()` — feedback visual; permanece em Home.
  - `onServiceTap(DemoServiceID)` — feedback visual; permanece em Home.
- **Ownership**: `Features/Home`.

### UI contract

- `TabView` mantém a barra inferior fixa com as 5 abas; a aba "Início" hospeda o conteúdo desta
  feature.
- Uma única `ScrollView` + `LazyVGrid` de duas colunas fixas contém as seções full-width e os seis
  serviços.
- A ordem visual/semântica segue `data-model.md`.
- Nenhum card usa altura fixa ou truncamento como comportamento normal.
- O último serviço pode ser rolado integralmente acima da barra inferior (`TabView` já reserva o
  espaço automaticamente via safe area).
- A Home usa `@Environment(\.colorScheme)`/`PitGoTheme` para Light/Dark.
- A View recebe closures e não conhece o estado de navegação do host.

## Navigation rules

1. `PitGoRootView` mantém `@State private var showHome = false` (ou equivalente com
   `NavigationStack`); Welcome é o conteúdo raiz.
2. Ao receber `onEnter`, o host aceita somente a primeira ação válida enquanto `showHome` ainda for
   `false`; o valor volta a `false` quando o usuário retorna à Welcome (ver `research.md` §9).
3. Não há equivalente a `popUpTo`; a pilha lógica resultante é sempre `[Welcome, Home]`.
4. Voltar em Home (gesto de borda ou botão) revela a mesma Welcome; Back/gesto em Welcome aplica o
   comportamento padrão do iOS (suspender/sair do app).
5. Nenhuma outra ação cria destino, altera aba selecionada além de Início, ou inicia fluxo de
   autenticação, diagnóstico, serviço, garagem, atendimento ou perfil.
6. A barra de status usa texto claro sobre a Welcome (`.preferredColorScheme(.dark)` local ou
   `.toolbarColorScheme(.dark, for: .navigationBar)` conforme aplicável) e o contraste apropriado
   ao modo Light/Dark do sistema na Home.

## Accessibility and interaction contract

- Cada card/controle tocável forma um único elemento de acessibilidade de no mínimo 44×44pt.
- Rótulo, finalidade e ação são anunciados sem duplicar o nome por meio do ícone
  (`.accessibilityHidden(true)` nos SF Symbols/ícones decorativos).
- Headings usam `.accessibilityAddTraits(.isHeader)` e a ordem de foco segue a leitura visual.
- A aba selecionada ("Início") é anunciada pelo próprio `TabView` (comportamento nativo do
  VoiceOver), não apenas colorida.
- Todo toque válido mostra feedback visual mesmo quando permanece no destino.

## Invariants

- Uma sequência rápida de toques em Entrar produz no máximo uma Home.
- Welcome sempre antecede Home no histórico desta feature.
- "Início" é a única aba com conteúdo funcional nesta entrega.
- Nenhuma tela depende de internet, sessão, permissão, dado pessoal real ou fonte externa.
- Remover a rota antiga de prestadores (`001`) não exige migração: seu identificador era interno,
  não persistido e não exposto como deep link/Universal Link.
