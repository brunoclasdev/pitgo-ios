# Validação iOS — spec 034

## Contrato e implementação

- Backend conferido nas migrations Android `20261022100000_service_ratings.sql` e `20261022103000_provider_rating_comments.sql`; ambas as modalidades compartilham `appointments.provider_id` e os mesmos RPCs. Nenhuma migration foi copiada para o app iOS.
- A listagem de histórico permanece baseada em `list_my_service_appointments`; o campo privado `rating_state` controla oferta/estado sem incluir comentários.
- A submissão só confirma estado salvo quando recebe contexto válido; em falha ambígua, uma leitura privada precede nova tentativa, preservando nota e texto.
- Média/quantidade usam o RPC de resumo; comentários do perfil usam RPC que vincula a consulta ao prestador da sessão.

## Build e diff

- Builds `pitgo`, `pitgo-Homol` e `pitgo-Prod` passaram para simulator. Restam avisos existentes de `ISO8601DateFormatter`, um aviso Sendable no binding do `TextEditor` e o aviso Xcode de build number vazio.
- `git diff --check` passou. O app não altera nenhuma migration ou Edge Function do backend compartilhado.

## Validação manual pendente

- Cobrir Guincho e PitTec, nota com/sem comentário, 500 Unicode scalars, dispensar e retomar pelo histórico, sucesso ambíguo/retry, atendimento inelegível e bloqueio de segunda avaliação.
- Confirmar que outros clientes recebem apenas agregados; cliente autor e prestador leem comentário pelo acesso privado apropriado.
- Conferir comentários recebidos e paginação na conta do guincheiro em aparelho real.
