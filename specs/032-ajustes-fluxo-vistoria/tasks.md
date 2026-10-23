# Tarefas iOS — spec 032

- [X] Reaproveitar captura local privada e permitir repetição do upload com a mesma captura/IDs; manter captura em memória e oferecer nova persistência quando a gravação inicial falhar.
- [X] Criar consulta paginada autenticada de avisos, limitada ao ambiente da compilação e à conta da sessão.
- [X] Consultar ao abrir/retomar o app e a cada cinco segundos em primeiro plano, com uma consulta ativa, sem push/notificação do sistema e sem tratar falha de leitura como aprovação.
- [X] Exibir diálogo global sem deslocar o conteúdo, com “Revisar vistoria”/“Agora não”, dedupe por versão e revalidação de participação/estado antes de navegar.
- [X] Evitar duplicar o aviso enquanto a vistoria correspondente já estiver aberta; atualizar a vistoria aberta por leitura periódica.
- [X] Persistir operação e versão da intenção de envio; replay usa a mesma identidade, confirma apenas `APPLIED`/`EXISTING` e não navega em conflito/falha.
- [X] Após confirmação própria, fechar a captura inline e voltar ao mapa do atendimento; aprovação não inicia o transporte automaticamente.
- [X] Validar journal por SHA-256 e tamanho; reconstruir miniatura apenas se os bytes regenerados coincidirem com a captura reservada; caso o original falte/divirja, permitir descartar a reserva remota com operação idempotente e liberar recaptura explícita.
- [X] Executar builds Dev/Homol/Prod e `git diff --check` depois da implementação final.
- [ ] Validar fluxos com duas contas, conexão intermitente, rotação/reabertura, 20 envios e aparelho real.
