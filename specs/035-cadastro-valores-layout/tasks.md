# Tarefas iOS — Spec 035

- [x] Selecionar PitTec, Guincho ou Loja antes do signup e manter a escolha até o cadastro autenticado.
- [x] Enviar `provider_kind`; cadastrar loja sem ofertas e Guincho com veículo validado e persistido atomicamente pela RPC compartilhada.
- [x] Remover preço e duração editáveis do formulário de cadastro e não exibir prova/localização em mapa para endereço empresarial.
- [x] Resolver preço e duração PitTec por `get_current_service_pricing`, sem fallback a preço definido pelo provider.
- [x] Decodificar duração e versão central nos snapshots PitTec/Guincho e apresentar duração quando disponível.
- [x] Remover seletor Fixo/Móvel da área empresarial e apresentar o tipo comercial.
- [x] Aplicar borda roxa e rolagem responsiva ao card flutuante do mapa Guincho.
- [x] Adicionar catálogo de lojas e CRUD owner-scoped de produtos; nome, descrição e preço são obrigatórios, imagem opcional, sem estoque.
- [ ] Validar manualmente onboarding dos três tipos, placa duplicada, permissão do proprietário, imagens e fonte ampliada/teclado em device.
- [ ] Confirmar no ambiente integrado a disponibilidade das RPCs/migrations 035 antes do aceite funcional.
