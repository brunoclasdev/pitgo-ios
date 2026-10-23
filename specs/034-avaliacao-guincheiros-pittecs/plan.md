# Plano iOS — avaliações de Guincho e PitTec

1. Usar os RPCs de avaliação já aplicados no Supabase compartilhado; a app não cria tabela, gravação direta nem migration duplicada.
2. Criar modelos/repositório para consulta privada, submissão idempotente, resumo público e comentários do prestador autenticado.
3. Criar formulário sem nota pré-selecionada, comentário opcional limitado a 500 pontos de código Unicode, retry recuperável e confirmação definitiva.
4. Oferecer avaliação após conclusão e pelo histórico comum de Guincho/PitTec, sem alterar o status do atendimento ao dispensar.
5. Mostrar somente média/quantidade em dados visíveis aos clientes; manter comentários restritos ao autor e prestador e adicionar leitura privada no perfil do guincheiro.
6. Validar builds e diffs; validar permissões e ciclos ambíguos de rede com as contas reais conforme o quickstart Android.

## Contratos existentes

- `get_service_rating(p_appointment_id)` e `submit_service_rating(p_appointment_id,p_rating,p_comment)`.
- `get_provider_rating_summary(p_provider_id)` retorna apenas contagem e média.
- `list_my_provider_ratings(p_before,p_before_id,p_limit)` resolve o guincheiro pela sessão e retorna sua página privada de comentários.
- `list_my_service_appointments` já inclui `rating_state` nos snapshots de histórico compartilhados de Guincho e PitTec.
