# Contract: UI do cadastro empresarial com busca de CEP (iOS)

## Entrada e navegação

A feature permanece no destino existente `PitGoRoute.providerRegistration` (`007`/`009`). Não cria
argumento, rota ou View nova. `ProviderRegistrationView` recebe o mesmo `ProviderRegistrationViewModel`,
cujo `init` passa a receber também o `ViaCepAddressLookupRepository`.

## Controle de CEP

O item atual de CEP passa a conter:

- `TextField` com label "CEP", `.keyboardType(.numberPad)` e a máscara visual existente (formatação
  "ao editar", `005 §9`);
- `Button` textual "Buscar CEP";
- progresso textual "Buscando CEP…" durante a chamada;
- status/erro persistente e ação de "Tentar novamente" quando aplicável.

O botão é habilitado somente quando: CEP normalizado tem oito dígitos; a consulta não está
`.loading`; o cadastro não está `.submitting`.

Em largura confortável e Dynamic Type abaixo de tamanhos grandes, campo e botão podem ficar lado a
lado (`HStack`/`ViewThatFits`, mesmo padrão de `003 §7`). Em largura compacta, landscape estreito ou
Dynamic Type grande, ficam empilhados (`VStack`) e o botão ocupa a largura total. Nenhum controle
possui altura rígida; alvos têm pelo menos 44×44pt.

`.submitLabel(.search)` no `TextField` é uma ação explícita equivalente ao botão e só dispara a
busca quando o CEP é válido. Não há chamada causada apenas pelo oitavo dígito digitado.

## Eventos do ViewModel

```swift
func onFieldChanged(_ field: ProviderField.PostalCode, value: String)
func lookupPostalCode()
func retryPostalCodeLookup()
func onFieldChanged(_ field: AddressField, value: String)
func submit()
```

Regras: colagem mascarada é normalizada para no máximo oito dígitos; toque duplicado durante loading
é no-op (guarda síncrona); editar o CEP cancela/invalida a consulta ativa; durante loading, os cinco
campos que podem ser sobrescritos ficam temporariamente desabilitados; número e demais dados do
formulário continuam editáveis; submit fica desabilitado/guardado até a consulta sair de loading;
consulta fica desabilitada durante submit.

## Renderização dos estados

| Estado | CEP | Botão | Campos derivados | Mensagem |
|---|---|---|---|---|
| idle | editável | Buscar CEP | editáveis | nenhuma |
| loading | editável | desabilitado + progresso | desabilitados | Buscando CEP… |
| found completo | editável | Buscar CEP | preenchidos/editáveis | Endereço preenchido. Informe o número. |
| found incompleto | editável | Buscar CEP | presentes preenchidos, ausentes editáveis | Endereço preenchido. Complete os campos restantes. |
| notFound | erro no CEP | Tentar novamente | preservados | CEP não encontrado. |
| failure | válido/editável | Tentar novamente | preservados/editáveis | mensagem de rede/timeout/serviço/resposta |

Uma falha temporária não bloqueia preenchimento manual nem conclusão válida. `notFound` bloqueia
enquanto o mesmo CEP permanecer, pois é um erro conhecido do valor.

## Aplicação e edição

- sucesso atualiza todos os campos aceitos numa única mudança de estado `@Observable`;
- valores vazios do ViaCEP não apagam entrada manual;
- número nunca é preenchido, limpo ou desabilitado pelo lookup;
- campos preenchidos continuam editáveis;
- mudar o CEP depois de sucesso limpa os campos registrados na proveniência e preserva número;
- sucesso invalida a geocodificação/verificação anterior (`009`), sem iniciá-la automaticamente;
- resposta tardia ou pertencente a outro CEP não altera a View.

Depois de sucesso, foco/scroll vai para o primeiro campo obrigatório ainda vazio; se nenhum estiver
vazio, vai para Número.

## Validação completa do cadastro

Ao tocar "Cadastrar empresa": (1) validar todos os campos e seletores conhecidos; (2) apresentar
todos os erros na mesma tentativa; (3) rolar até o primeiro inválido na ordem visual
(`ScrollViewReader`); (4) focar o controle quando focável (`@FocusState`) ou anunciar o grupo
semântico; (5) não chamar o cadastro enquanto houver erro.

Cada `TextField` usa indicação visual de erro + texto de apoio + `.accessibilityLabel` combinando
rótulo e motivo. Modalidade, ofertas e seletores também mostram sua mensagem junto ao grupo.
Mensagens distinguem obrigatório, formato, tamanho, seleção, CEP inexistente e conflito remoto.
Limites máximos são informados numericamente.

Após essa tentativa, editar um campo revalida apenas aquele campo. Seu erro só desaparece quando o
valor se torna válido; valores e erros dos outros campos permanecem.

## Acessibilidade e lifecycle

- status da consulta e falhas usam `.accessibilityAddTraits(.updatesFrequently)` (Live Region);
- loading contém indicador (`ProgressView`) e texto, não somente animação;
- estado nunca depende apenas de cor;
- ordem de VoiceOver segue CEP, busca, status e demais campos;
- `List`/`ScrollView`, `.scrollDismissesKeyboard` e largura máxima existentes (`007`) permanecem;
- recriação de View (ex.: rotação de dispositivo) conserva rascunho e consulta no ViewModel sem
  reiniciar a chamada;
- sair, trocar sessão ou submeter cancela/invalida a consulta;
- nenhuma mensagem técnica, URL ou resposta bruta é exibida.
