# Comparação iOS × Android — 2026-11-03

Referência local: `../../android/pitgo/app/src/main/java/com/trustarx/pitgo`, com contratos confirmados nas migrations e Edge Functions de `../../android/pitgo/supabase`. A comparação usa o checkout local Android, sem presumir que ele corresponda à versão publicada ou que todas as migrations estejam implantadas.

A varredura comparou o inventário de chamadas RPC e aprofundou os fluxos com diferenças concretas em pagamentos, acompanhamento e loja. Alterações de cadastro, garagem, frota e busca de guincho já estavam presentes no workspace antes desta revisão e foram preservadas. As correções desta revisão estão descritas abaixo; este documento não certifica equivalência de todas as telas.

| Área | Diferença encontrada no iOS | Correção |
| --- | --- | --- |
| Cancelar pagamento | Apenas fechava o sheet, deixando a cobrança ativa | Consulta o estado e solicita `mp-cancel-payment`; fechamento depende da confirmação do servidor |
| Guincho sem cobrança | Fechamento podia manter a reserva não paga | `cancel_unpaid_guincho_request` precisa confirmar `CANCELLED` |
| Retomar Pix | Snapshot descartava o QR Code; tela passava a esperar confirmação de cartão | DTO preserva Pix e restaura código/QR na tela |
| Cancelamento em andamento | Snapshot `APPROVED` com `cancel_requested` podia disparar despacho | Flag de cancelamento impede aprovação no checkout |
| Reconciliação | `sync_state` era ignorado | Aguarda estado `CURRENT` antes de liberar uma aprovação |
| Recuperação Mobile | Nova instância gerava outro request ID para um pagamento pendente | Ao reabrir o mesmo serviço, consulta `get_recoverable_payment` e reutiliza o request ID |
| Histórico de pagamentos | Não havia entrada nem consulta | Perfil oferece histórico paginado com `get_payment_history`, cursor composto por data/ID e estados de estorno |
| Cartão salvo | Dispensar o sheet de CVV podia deixar a tela no estado de confirmação | Retorna à seleção de método quando o sheet é dispensado |
| Simulação | Retry reutilizava também tentativas expiradas/recusadas | Somente pagamentos pendentes/aprovados são reutilizados |
| Localização do prestador | Esperava `fresh` e payloads antigos `UPSERT/CLEARED` | Lê `LIVE/STALE/EMPTY/ENDED`; broadcasts apenas disparam leitura autoritativa |
| Falha no tempo real | Acompanhamento não tinha consulta periódica | Polling a cada 5 segundos e filtragem de callbacks após desconexão |
| Encerramento | Snapshot terminal sem coordenadas não encerrava o mapa | `ENDED` encerra e para polling/publicação; posições atrasadas não reabrem o atendimento |
| Localização do cliente | Mobile/PitTec não publicavam durante acompanhamento | Publicação em primeiro plano com permissão, fix válido/recente e repetição após falha; guincho mantém retirada fixa |
| GPS | Timeout antigo podia finalizar outra requisição; cancelamento abandonava continuation | Timeout identificado por requisição e continuation retomada no cancelamento |
| Produtos | Aceitava casas decimais/valores fora do limite do Android | Validação de preço positivo, até duas casas e abaixo de 10 bilhões |
| Operações da loja | Edição/exclusão/navegação concorrentes; falta de recarga | Bloqueio durante operações e atualização manual das listas |
| Fotos de produtos | Retry após upload bem-sucedido podia reenviar a mesma foto | Reaproveita upload na nova tentativa de salvar |

A recuperação de pagamento implementada ocorre ao reabrir o serviço; o aviso global de recuperação da Home Android não foi reproduzido. O histórico permite consulta, sem reproduzir toda a tela Android de detalhes e ações de um pagamento. O acompanhamento continua com as telas e mapas nativos existentes no iOS; não foi feita comparação visual pixel a pixel nem portabilidade integral da tela compartilhada Android de acompanhamento.

Validação automatizada:

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Scripts/Tests/run-platform-parity-regressions.sh`: contratos de localização, transições e proteção contra callbacks atrasados, preços, histórico, cancelamento, reconciliação, retomada Pix e recuperação Mobile, sem cobrança real.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Scripts/Tests/run-guincho-regressions.sh`: orçamento, reserva e retomada de busca.
- Compilação Debug para iOS Simulator com assinatura desabilitada.

Ainda depende de validação integrada em dispositivos: GPS/permissões, dois participantes no mapa, reconexão em rede real, cancelamento/estorno Mercado Pago e paginação usando dados do ambiente. Os testes de contrato e a compilação não substituem esses cenários. Nenhuma alteração de backend foi implantada nesta revisão.
