# Porte iOS — vistoria ampliada e rota de transporte do Guincho

O Android 031 amplia o catálogo da vistoria para 17 pontos sem mudar os quatro obrigatórios, melhora a retomada de captura e acrescenta rota viária autenticada durante o transporte. A sincronização de fotos usa a persistência privada/idempotente já portada em 030; o destino permanece o snapshot contratado pelo backend.

## Etapas

1. Adicionar 13 categorias opcionais à UI de vistoria, preservando capturas, correções e versões já registradas.
2. Consumir a Edge Function `guincho-route` existente; não enviar coordenadas arbitrárias do app nem duplicar migrations já presentes no workspace Android.
3. Mostrar polilinha, origem, destino, atualidade/erro e Recentralizar somente após `IN_PROGRESS`; preservar mapa PitTec e comportamento do cliente.
4. Atualizar rota após desvio confirmado com fixes atuais e precisos; conflar chamadas, respeitar limites do backend e manter referência anterior ao falhar.
5. Validar builds Dev/Homol/Prod e registrar os cenários manuais que dependem de GPS, roteador e contas reais.
