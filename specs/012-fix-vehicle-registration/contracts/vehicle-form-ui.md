# Contract: Vehicle Form UI (iOS)

## Campos e ordem (inalterados desde `006`)

1. Marca — obrigatória
2. Modelo — obrigatório
3. Versão — opcional
4. Ano de fabricação — opcional
5. Ano do modelo — opcional
6. Placa — opcional
7. Renavam — opcional
8. Chassi — opcional
9. Cor — opcional
10. Combustível — opcional
11. Câmbio — opcional
12. Motor — opcional
13. Quilometragem — opcional

A opção "Tornar veículo principal" (`Toggle`) aparece somente quando já existe veículo ativo. O
primeiro veículo será principal independentemente da opção, por regra do banco.

## Mensagens por campo

| Campo/condição | Mensagem |
|---|---|
| Marca vazia | `Informe a marca do veículo.` |
| Modelo vazio | `Informe o modelo do veículo.` |
| Placa inválida | `Informe uma placa válida.` |
| Renavam inválido | `O Renavam deve conter 11 dígitos.` |
| Chassi inválido | `Informe um chassi válido com 17 caracteres.` |
| Ano de fabricação/modelo inválido | `Informe um ano entre 1900 e {ano máximo}.` |
| Quilometragem negativa | `A quilometragem não pode ser negativa.` |
| Quilometragem não inteira | `Informe a quilometragem usando um número inteiro.` |
| Placa/Renavam/Chassi duplicado | `Este identificador já está cadastrado.` |

- Campo inválido usa indicação visual de erro, texto de apoio e `.accessibilityLabel` combinando
  rótulo e erro.
- Todos os erros conhecidos permanecem no estado simultaneamente.
- Editar um campo não apaga erro de outro campo.
- Um erro existente só desaparece quando o novo valor daquele campo é válido.
- Após submit inválido/remoto específico, rolar (`ScrollViewReader`) até o primeiro campo inválido
  e então solicitar foco (`@FocusState`).

## Falhas gerais

Falhas de sessão, conexão, timeout, RPC ausente/incompatível, indisponibilidade e erro inesperado
aparecem em banner acessível e não marcam campo. Para RPC ausente/incompatível, o texto é exatamente:

`O cadastro de veículos está temporariamente indisponível. Tente novamente mais tarde.`

O rascunho permanece em falhas recuperáveis. Sessão expirada delega ao gate central (`SessionStore`,
`006`) e limpa dados do destino quando ele deixa de ser autenticado.

## Submissão

- CTA desabilitado em `.loading` e `.submitting`.
- `.submitting` mostra `ProgressView` e texto de salvamento.
- Eventos de campo, `Toggle` e submit repetido são ignorados durante processamento (guarda síncrona).
- Não há retry remoto automático.

## Navegação

| Origem | Sucesso | Voltar antes do sucesso |
|---|---|---|
| Onboarding | Resolver pendência, atualizar sessão e trocar `RootPhase` para `.home` | Confirmar descarte quando houver rascunho; não concluir onboarding só por abrir o formulário |
| Garagem | Remover o formulário do `NavigationPath` e retornar à Garagem, que recarrega em `.onAppear` | Retornar à Garagem; confirmar descarte quando houver rascunho |

O formulário em `.success` é terminal e não pode ser reaberto pelo gesto/botão de Voltar.
