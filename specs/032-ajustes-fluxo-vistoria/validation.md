# Validação iOS — spec 032

## Implementado

- Aviso interno só para a conta cliente autenticada, por RPC privado e identificado por ambiente/atendimento/versão.
- Poll ao iniciar/retomar e a cada 5 s em primeiro plano; dispensar uma versão não a reapresenta por polling. Abrir revalida o estado e encaminha para a revisão atual ou acompanhamento do atendimento já resolvido.
- A tela da vistoria aberta atualiza o estado sem empilhar outra cópia. Falha de rede preserva o último conteúdo e não aprova a vistoria.
- Captura que falha no upload pode ser repetida com a mesma imagem e IDs; falha ao gravar no disco mantém imagem em memória e oferece nova tentativa de persistência.
- O journal grava SHA-256 e tamanho do original/miniatura. Na retomada, verifica ambos antes de reutilizar arquivos; reconstrói uma miniatura ausente somente quando ela gera o mesmo hash e tamanho reservados. Se o original faltar ou o derivado reconstruído divergir, a UI exige descarte explícito; a reserva remota correspondente é abandonada com uma operação persistida e idempotente antes de liberar uma nova captura.
- Envio persiste operação/versão antes da chamada; confirmação `APPLIED`/`EXISTING` fecha a vistoria inline e apresenta o mapa do atendimento aguardando a decisão. O transporte depende do botão explícito já existente.

## Validação pendente

Os cenários com dois usuários, conexão intermitente, falha real de armazenamento, rotação/reabertura e aparelho físico continuam pendentes. A validação estática do journal não substitui esses cenários integrados.

## Verificações

- [x] Dev
- [x] Homol
- [x] Prod
- [x] `git diff --check`
- [ ] Testar com dois usuários reais, queda/reconexão, retorno do background, dismiss/reabertura, timeout com replay, rotação e navegação Voltar.
