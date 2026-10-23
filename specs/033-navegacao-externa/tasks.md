# Tarefas iOS — spec 033

- [X] Criar adaptador para Waze e Google Maps com validação de coordenadas, checagem de instalação e abertura explícita sem fallback.
- [X] Declarar `waze` e `comgooglemaps` em `LSApplicationQueriesSchemes`.
- [X] Oferecer seletor acessível no Guincho antes da chegada e durante transporte, com revalidação do atendimento e do destino.
- [X] Oferecer seletor acessível ao PitTec somente antes da chegada, relendo estado e posição atual do cliente.
- [X] Preservar atendimento e apresentar indisponibilidade/revalidação falha sem acionar transições operacionais.
- [X] Remover o símbolo de relógio do aviso de posição desatualizada; manter texto acessível e marcadores padrão nos mapas.
- [ ] Validar manualmente Waze/Google Maps nos seis casos de destino e confirmar fluxo de retorno com atendimento e localização em andamento.
- [ ] Validar indisponibilidade de cada app, ausência de ambos, destino inválido e mudança de etapa durante o seletor em aparelho real.
- [X] Executar builds Dev/Homol/Prod após a implementação.
- [X] Executar `git diff --check`, `plutil -lint` e conferir os formatos de URL gerados.
