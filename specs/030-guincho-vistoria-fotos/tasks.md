# Tarefas iOS — vistoria fotográfica do Guincho

- [X] Implementar modelos e DTOs compatíveis com `get_guincho_inspection` e snapshots versionados.
- [X] Implementar repository para leitura, reserva, confirmação, envio, correção, decisão, Storage privado e paginação histórica.
- [X] Capturar exclusivamente com câmera, identificar os quatro pontos obrigatórios e permitir refazer/substituir antes de enviar.
- [X] Persistir captura pendente em arquivos privados e retomar upload idempotente após interrupção; só confirmar depois da verificação do servidor.
- [X] Abrir vistoria ao guincheiro após “Cheguei”; manter o botão de transporte oculto até a aprovação autoritativa.
- [X] Exibir revisão pendente no acompanhamento do cliente, impedir aprovação até carregar todas as fotos e exigir motivo para correção.
- [X] Preservar versões/decisões e exibir consulta histórica somente leitura em fluxos encerrados.
- [X] Executar builds Dev/Homol/Prod e `git diff --check`.
- [ ] Executar cenários manuais com duas contas e câmera em aparelho real; registrar limites nesta pasta.
