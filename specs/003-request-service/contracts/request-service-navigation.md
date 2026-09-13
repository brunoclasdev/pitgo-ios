# UI and Navigation Contract: Home → RequestService (iOS)

## Purpose

Definir a fronteira verificável entre a Home, o destino de solicitação, seu estado local e as
ações que podem alterar a pilha. Não existe API, Universal Link público, persistência ou
atendimento real.

## Producer: Home

- **Output alterado**: `onServiceTap: (DemoServiceID) -> Void` solicita navegação para o serviço
  tocado.
- **Outputs preservados**: `onDiagnosticTap()` — feedback visual; permanece em Home.
- **Ownership**: `Features/Home`.

### Producer invariants

- Cada card emite exatamente seu próprio `DemoServiceID`.
- Nome, preço e ícone não são enviados como argumento de navegação.
- Toques repetidos durante a transição produzem no máximo um RequestService no topo.
- A `HomeView` recebe closures e não conhece o `NavigationPath`.

## Route contract

- **Rota**: `PitGoRoute.requestService(serviceID: DemoServiceID?)`.
- **Representação do argumento**: o próprio `enum DemoServiceID?` — não uma `String` a ser
  parseada; `nil` representa ID ausente e é tratado exatamente como um ID desconhecido seria no
  Android (ambos levam a `.invalidService`).
- **Builder input**: `DemoServiceID` não-opcional na origem (Home sempre emite um caso válido); o
  parâmetro da rota é opcional apenas para representar corretamente uma navegação profunda futura
  sem argumento.

| Raw input | Result |
|---|---|
| Um dos seis casos de `DemoServiceID` | `RequestServiceUiState.content` correspondente |
| `nil` | `RequestServiceUiState.invalidService` |

Diferente do Android (que precisa validar uma `String` bruta contra os nomes do enum), aqui um
valor "desconhecido" é irrepresentável — só existem os seis casos ou `nil`. Isso elimina a
categoria inteira de erro "ID com case diferente ou desconhecido" do contrato original.

## Consumer: RequestService

- **Ownership**: `Features/RequestService`.
- **State owner**: `RequestServiceViewModel` (`@Observable`), inicializado com o `DemoServiceID?`
  recebido na navegação.
- **Outputs**:
  - `onBack()` — solicita retorno seguro.
  - `onProblemDescriptionChanged(String)` — atualiza somente a descrição temporária.
  - `onPaymentMethodSelected(PaymentMethod)` — substitui a seleção atual.
  - `onSubmit()` — executa o callback mock uma vez quando o status é `.ready`.

### Content UI contract

- Uma única `ScrollView` rola entre a barra de navegação (título + botão voltar) e a `TabView`
  fixa.
- `.safeAreaPadding()` e observação do teclado (`.scrollDismissesKeyboard(.interactively)` ou
  equivalente) mantêm o conteúdo e o aviso alcançáveis com o teclado aberto.
- Serviço, veículo e local usam uma apresentação visual coerente com os cards da Home.
- A descrição usa `TextEditor` (multiline nativo), começa vazia e não bloqueia submit.
- Estimativas aparecem lado a lado em `HStack` quando há espaço e empilham em `VStack` quando não
  há (via `ViewThatFits` ou checagem de `horizontalSizeClass`).
- Pagamento é um grupo de seleção exclusiva (`Picker` com estilo segmentado, ou botões customizados
  com estado `selected`), iniciado em `.pix`.
- O CTA usa um `Button` com gradiente de fundo e fica desabilitado (`.disabled(true)`) após o
  primeiro callback aceito.
- A View recebe estado/closures e não conhece o `NavigationPath`.

### InvalidService UI contract

- Mantém título, ação de voltar e `TabView`.
- Exibe mensagem compreensível de serviço indisponível.
- Não mostra nome, ícone, preço, formulário, estimativas, pagamentos nem CTA de outro serviço.
- Oferece ação visível de retorno usando o mesmo closure `onBack()`.

## Back and stack rules

1. `PitGoRoute` centraliza Home (raiz) e `.requestService(serviceID:)`.
2. O host de navegação aceita a seleção apenas uma vez por toque válido (mesma proteção local de
   `001`/`002`).
3. O fluxo normal produz uma `NavigationPath` de um elemento sobre Home:
   `[Home, RequestService]` (Welcome já ficou para trás na pilha lógica do app inteiro).
4. Voltar (gesto de borda ou botão) revela a mesma Home.
5. Abas do `TabView` não criam rotas nesta feature.

## Accessibility and interaction contract

- A ação Voltar possui `.accessibilityLabel` localizado e alvo de pelo menos 44×44pt.
- Título e títulos de seção usam `.accessibilityAddTraits(.isHeader)` na ordem de leitura.
- Ícones repetidos por label/valor são `.accessibilityHidden(true)`; informação não duplicada
  recebe descrição.
- Cada opção de pagamento é um elemento de acessibilidade único, anunciando nome e estado
  selecionado (papel equivalente a rádio via `.accessibilityAddTraits(.isSelected)`).
- Textos quebram linha e controles crescem verticalmente; `.lineLimit(nil)` evita truncamento que
  remova informação essencial.
- Todo toque válido mostra feedback visual, inclusive abas demonstrativas do `TabView`.

## Invariants

- Um `DemoServiceID` válido resolve exatamente um serviço, e o preço exibido vem desse mesmo item.
- `nil` nunca seleciona Bateria ou reaproveita conteúdo anterior.
- Exatamente uma forma de pagamento permanece selecionada.
- Uma instância da View executa o callback mock no máximo uma vez.
- Nenhuma ação cria Booking/Order, consulta rede/localização ou inicia cobrança.
- RequestService e Home renderizam a mesma `TabView` compartilhada de `002`.
