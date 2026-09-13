# Quickstart: validar cadastro de empresa prestadora (iOS)

## 1. Pré-requisitos

- Xcode estável mais recente, SDK iOS 17+, simulador/dispositivo iOS 17+;
- Supabase CLI instalado apenas para **verificação** de schema (nenhuma migration é criada ou
  aplicada por esta feature);
- o mesmo projeto Supabase de desenvolvimento já usado para validar a feature Android equivalente,
  com `providers`/`addresses`/`service_categories`/`services`/`provider_services` e a RPC
  `create_provider_registration` já aplicados;
- `Config/Secrets.xcconfig` com `supabaseUrl`/publishable key, conforme `004`;
- provedor de e-mail habilitado, `enable_confirmations = false` (já definido no ambiente
  compartilhado);
- ao menos uma categoria e um serviço relacionado no catálogo de desenvolvimento para o cenário
  positivo (dados administrativos/fixtures, nunca dados de produção inventados).

Não executar `supabase db push` remoto como parte desta validação.

## 2. Verify the shared schema (no migration applied here)

```bash
supabase link
supabase db diff
```

Esperado: nenhuma diferença pendente relevante — `providers`, `addresses`,
`service_categories`, `services`, `provider_services` e a RPC já existem exatamente como
documentado em [contracts/supabase-provider-registration.md](contracts/supabase-provider-registration.md).
Qualquer divergência deve ser corrigida na migration do repositório Android.

## 3. Build the iOS app

```bash
xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'platform=iOS Simulator,name=iPhone 16' clean build

xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'generic/platform=iOS' clean build
```

Esperado: ambos sucedem, sem dependência nova e sem teste automatizado gerado.

## 4. Preparar catálogo de desenvolvimento

Pelo Supabase Studio, usando papel administrativo:

1. crie pelo menos duas categorias com nomes distintos;
2. crie dois serviços em uma categoria e um serviço na outra;
3. não crie catálogo pelo app.

Confirme que uma sessão autenticada consegue apenas consultar catálogo e não inserir/alterar
categoria ou serviço (a RLS garante isso independente de plataforma).

## 5. Fluxos de entrada

### Nova conta com intenção de provider

1. Na Welcome, toque "Cadastrar empresa".
2. Conclua o cadastro de conta (`005`).
3. Confirme que a sessão autenticada abre o cadastro de empresa diretamente, antes da `TabView`,
   sem pedir ou mostrar owner ID.
4. Volte sem editar: deve retornar de forma previsível.

### Conta existente

1. Entre normalmente (`006`).
2. Abra a aba Perfil e toque "Área da empresa".
3. Para uma conta sem provider, deve aparecer o formulário com e-mail comercial pré-preenchido a
   partir do e-mail Auth e editável.
4. Alterar o contato comercial não deve alterar o e-mail de login.

## 6. Cadastro positivo

Preencha empresa e endereço válidos, incluindo CNPJ vigente, CEP de oito dígitos e UF. Deixe
coordenadas vazias. Configure:

- uma oferta paga com preço de duas casas e duração válida;
- uma oferta diferente marcada "Serviço gratuito".

Confirme o cadastro.

Esperado:

- estado de envio desabilita campos, adicionar/remover e o botão principal;
- apenas uma confirmação é processada mesmo com toques repetidos;
- o resumo mostra empresa, endereço e duas ofertas, sem ID interno ou CNPJ completo;
- provider usa o mesmo UUID da conta;
- existe exatamente um endereço com owner derivado;
- a oferta gratuita persiste preço zero e a paga preserva centavos;
- provider, endereço e ofertas existem juntos.

Finalize e confirme que a aba Perfil permanece na área autenticada e reabre o mesmo resumo por
"Área da empresa", em vez de oferecer uma segunda criação.

## 7. Catálogo e múltiplas ofertas

1. Escolha a primeira categoria e confirme que só aparecem seus serviços.
2. Troque a categoria e confirme que o serviço anterior é limpo.
3. Adicione várias ofertas; remova itens intermediários e depois todas.
4. Tente enviar sem oferta: a View deve pedir ao menos uma e focar o primeiro erro.
5. Adicione novamente e tente selecionar serviço já usado: a UI impede/orienta e o submit também
   rejeita duplicidade.
6. Se uma categoria não tiver serviços, confirme estado vazio e `Picker` de serviço desabilitado.
7. Remova/indisponibilize um serviço no catálogo administrativo depois de selecioná-lo e antes do
   submit: nenhum registro parcial deve ser criado; a UI pede nova seleção após recarregar.

Não há teto definido pelo app. Uma lista extensa deve continuar rolando de forma lazy (`List`
nativa) e manter cada oferta associada ao seu `id` estável.

## 8. Validação local

Verifique, uma tentativa por caso: nome/e-mail/telefone/CNPJ vazio; e-mail inválido e contato com
máscara/espaços; CNPJ numérico inválido e CNPJ alfanumérico oficial válido; CEP com quantidade
incorreta e UF fora das 27 opções; número `s/n`, bloco ou lote aceito; somente latitude, somente
longitude e valores fora de -90/90 ou -180/180; preço vazio, zero sem gratuito, negativo, separador
inválido e mais de duas casas; duração vazia, fracionada, zero e acima de 10.080.

Esperado: nenhuma chamada de criação em formulário inválido, todos os erros específicos visíveis e
foco/scroll no primeiro erro em ordem visual.

## 9. Atomicidade, concorrência e resposta perdida

### Falha antes do commit

Provoque uma violação definitiva no catálogo entre seleção e submit. Depois da falha, confira que
não foi criado provider, endereço nem oferta para aquela conta.

### Duas confirmações concorrentes

Dispare toques rápidos ou duas chamadas autenticadas equivalentes. Esperado: lock por usuário
(garantido pela RPC compartilhada), exatamente um agregado e resposta `ALREADY_REGISTERED` para a
chamada posterior.

### Resposta perdida após commit

Interrompa a conexão imediatamente após confirmar e tente novamente quando voltar. Esperado: a RPC
reconhece o agregado completo, não sobrescreve dados, não duplica endereço/ofertas e a UI abre o
resumo como sucesso reconhecido.

## 10. Conflitos e falhas de rede

- Use e-mail comercial já usado: mensagem neutra no e-mail, sem revelar empresa.
- Use CNPJ já usado: mensagem neutra no CNPJ, sem revelar documento/empresa.
- Fique offline antes de carregar catálogo: estado de falha com retry.
- Fique offline durante submit: rascunho não sensível permanece em memória e o CTA permite retry.
- Simule timeout/5xx: mensagem compreensível, sem SQLSTATE, constraint, URL ou payload.

Revise o console/crash reporter: não deve conter CNPJ completo, IDs de owner, token, header de
autorização, payload JSON, mensagem/`details` do `Error` ou stack trace com a request.

## 11. Sessão e RLS

Com duas contas A e B:

1. A cria provider e ofertas.
2. B não consegue selecionar provider/endereço/ofertas de A e não consegue executar DML direto.
3. B não consegue passar o ID de A porque a RPC não possui argumento de owner.
4. Expire/logout durante o formulário de B: campos, CNPJ, catálogo e ofertas somem antes da Welcome
   ou do `SessionGateView`.
5. Uma resposta tardia iniciada por B não pode atualizar a tela após entrar como A.

Confirme também que `anon` não possui SELECT/DML e que `authenticated` possui somente SELECT nas
tabelas + EXECUTE na RPC.

## 12. Acessibilidade e configuração

Validar em iPhone compacto, landscape e Dynamic Type grande, com teclado aberto:

- todos os campos, `Picker`s, ofertas, retry e CTA alcançáveis;
- nenhum rótulo truncado nem rolagem horizontal;
- VoiceOver anuncia headings, erros, seleção, gratuito, remover, loading e resultado;
- alvos têm pelo menos 44×44pt e a ação principal 56pt;
- Voltar com rascunho mostra confirmação; Voltar durante envio não abandona operação incerta;
- rotação mantém o rascunho na mesma instância de ViewModel; encerramento do processo não restaura
  CNPJ/endereço, conforme a decisão de privacidade.

## 13. Fora desta validação

Não validar como parte da feature: criação/edição de catálogo, aprovação de provider, publicação,
agenda, imagens, cobrança, geocodificação, busca de CEP, localização, múltiplos endereços ou edição
posterior.
