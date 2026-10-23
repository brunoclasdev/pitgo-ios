# Plano iOS — Cadastro, valores e layout

Portar o comportamento da spec Android 035 sobre os contratos Supabase compartilhados. O histórico Android até `3873f60` cobre as specs anteriores; a implementação 035 está no working tree Android e seus contratos/migrations foram lidos diretamente. As migrations e o dashboard administrativo permanecem no projeto Android/backend.

## Sequência

1. Apresentar seleção de modalidade antes do cadastro de credenciais e carregar o tipo escolhido até a RPC de cadastro.
2. Enviar endereço digitado pelo fluxo atual de geocoding textual e exigir os quatro dados do veículo em cadastros Guincho.
3. Usar a tarifa PitTec central e versionada na área Valores; aceitar duração/versionamento nos snapshots de atendimento.
4. Remover seletores operacionais da área empresarial e manter card de endereço flutuante no mapa Guincho.
5. Criar catálogo público de lojas e gerenciamento de produtos com foto opcional, sem estoque.

## Limites

- O backend Android já define RPCs, ownership, regras de tarifas e políticas de storage. O app iOS só chama esses contratos e não executa migrations.
- O cadastro ainda usa a verificação automática de endereço existente para obter coordenadas de descoberta; não oferece mapa nem seleção manual de ponto.
- A tarifa PitTec ausente aparece como indisponível. O preço reservado do guincheiro não é usado pelo cliente; a cotação de Guincho continua vindo do servidor.
