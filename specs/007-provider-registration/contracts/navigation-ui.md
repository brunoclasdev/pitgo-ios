# Contract: navegação e estados de UI (iOS)

## Rotas centralizadas

### Sign Up com origem fechada

```swift
enum SignUpOrigin { case default_, provider }

extension UnauthenticatedRoute {
    // substitui o caso simples .signUp(de 005) por uma versão com origem
    case signUp(origin: SignUpOrigin)
}
```

- "Criar conta" na Welcome empurra `.signUp(origin: .default_)`;
- "Cadastrar empresa" na Welcome empurra `.signUp(origin: .provider)`;
- não existe caminho para um valor de origem "desconhecido" — `SignUpOrigin` é um `enum` Swift, o
  que elimina por construção a categoria "string de rota arbitrária" (mesma vantagem estrutural já
  registrada em `003 research.md §2` para `DemoServiceID`);
- a origem não altera campos nem força tipo PF/PJ; apenas escolhe o próximo destino depois que
  `SessionStore` confirmar a conta.

### Cadastro de empresa

```swift
// PitGoRoute (rota autenticada, empurrada dentro da NavigationStack da aba Perfil)
case providerRegistration
```

- sem argumentos;
- só é composta quando `SessionStore.state` é `.authenticated`;
- incluída na superfície de theming do app (cores de status bar etc.);
- `providerID`, owner, e-mail e CNPJ não são argumentos.

## Entradas

| Origem | Ação | Destino |
|---|---|---|
| Welcome | Criar conta | `.signUp(origin: .default_)` |
| Welcome | Cadastrar empresa | `.signUp(origin: .provider)` |
| SignUp com `.provider` | sessão autenticada | `ProviderRegistrationView` como raiz autenticada (antes da `TabView`) |
| Aba Perfil | Área da empresa | `providerRegistration` empurrada na `NavigationStack` da aba |

O fluxo `.provider` é avaliado pelo `PitGoRootView` antes da checagem de onboarding de veículo
(`006`) naquela transição — a intenção de "virar prestador" vive apenas em memória durante essa
transição única (não persistida em `UserDefaults`, diferente da pendência de veículo). A
preferência de onboarding de veículo existente não é apagada por esta feature.

## Saídas e back stack

- Voltar em formulário intacto retorna à origem (aba Perfil ou raiz autenticada, conforme como foi
  aberto).
- Voltar com rascunho alterado abre `.confirmationDialog("Descartar cadastro?")`; confirmar limpa o
  ViewModel antes de sair.
- Durante `.submitting`, a saída destrutiva fica bloqueada e a UI informa que o cadastro está em
  andamento.
- `.alreadyRegistered` e `.success` mostram o resumo dentro do mesmo destino (não navegam para
  outra View).
- "Concluir/Voltar ao perfil" remove `providerRegistration` do `NavigationPath` e volta à aba
  Perfil; se não houver Perfil anterior na pilha (origem SignUp), a `TabView` é montada com Perfil
  como aba selecionada.
- Voltar/gesto de sistema depois da conclusão não reabre o formulário ou o SignUp (a
  `NavigationStack` não autenticada já foi descartada na transição de `RootPhase`, mesma garantia
  de `005`/`006`).
- Expiração/troca de sessão limpa o rascunho e aciona o mesmo tratamento central de `SessionStore`;
  o gate raiz decide Welcome ou `SessionGateView`.

## Contrato de renderização

```swift
switch uiState {
case .loading: ...
case .startupFailure(let reason): ...
case .editing(let content): ...
case .alreadyRegistered(let summary): ...
case .success(let summary): ...
case .sessionExpired: ...
}
```

### `.editing`

- três `Section` em ordem: empresa, endereço e serviços;
- categorias e serviços usam `LoadState = .loading | .empty | .content | .failure`;
- o `Picker` de serviço fica desabilitado até uma categoria válida ser escolhida;
- ofertas usam `id` estável (`OfferDraft.id`), podem ser adicionadas/removidas sem teto do app e
  aparecem como linhas de uma única `List`, não como listas aninhadas;
- submit exige ao menos uma oferta válida;
- `.submitting` desabilita inputs, add/remove, `Picker`s e a ação principal;
- falha temporária preserva o rascunho em memória e mostra um banner com retry;
- erro de campo usa texto de apoio + `.accessibilityLabel` combinado e solicita foco (`@FocusState`)
  no primeiro erro visual.

### `.alreadyRegistered` / `.success`

- exibe nome, contato comercial, endereço e todas as ofertas;
- indica se o cadastro acabou de ser criado ou já existia;
- CNPJ é mascarado e IDs internos não aparecem;
- oferta gratuita é exibida a partir de `price == 0`;
- oferece uma ação clara de retorno à aba Perfil.

## Responsividade e acessibilidade

- `NavigationStack` com título nativo, sem `TabView` no formulário/resumo;
- uma única `List`, `.scrollDismissesKeyboard(.interactively)`, largura de leitura limitada em
  telas largas e conteúdo em uma coluna;
- sem altura fixa, truncamento ou rolagem horizontal em campos/cards;
- alvos de toque mínimos de 44×44pt e ação principal com altura mínima de 56pt;
- headings semânticos (`.accessibilityAddTraits(.isHeader)`), erros com `.accessibilityLabel`
  combinando rótulo + mensagem, banners/resultado com `.accessibilityAddTraits(.updatesFrequently)`
  e loading com texto (`ProgressView` com label);
- controles de gratuito, remover e retry possuem rótulo textual; nada depende apenas de cor;
- teclado com `.submitLabel(.next)` em campos single-line, `TextEditor` multiline em descrições,
  `Picker` sem teclado próprio;
- com Dynamic Type grande, landscape e teclado aberto, todos os campos/ações permanecem
  alcançáveis.
