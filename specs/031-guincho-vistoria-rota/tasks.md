# Tarefas iOS — vistoria ampliada e rota do Guincho

- [X] Mostrar os 17 pontos da vistoria, com quatro obrigatórios e 13 opcionais identificados individualmente.
- [X] Preservar fotos opcionais, categorias, descrição, autoria e versão no fluxo de captura/correção/histórico.
- [X] Integrar o contrato autenticado `guincho-route` e validar resposta/GeoJSON/destino antes de renderizar.
- [X] Abrir a rota do pickup atual até o destino contratado após o início confirmado do transporte.
- [X] Recalcular após desvio confirmado por três fixes distintos cobrindo ao menos quatro segundos e precisão até 35 m; respeitar lease, cooldown e backoff do servidor.
- [X] Preservar mapa/rota anterior, destino e estado de falha recuperável em erros; ocultar rota ativa em encerramento/cancelamento.
- [X] Validar builds Dev/Homol/Prod e `git diff --check`.
- [ ] Validar em aparelho real com GPS/duas contas, roteador, desvio, lease/backoff e encerramento.
