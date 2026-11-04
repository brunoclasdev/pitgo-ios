# Porte iOS — catálogo de transporte, retomada e cadastros

Referências: specs 035/036 e commits Android `a6f33cf` e `2951ea6`.
Base iOS: `04226d1` (já inclui guincho, vistorias, avaliações, loja e preços administrativos).

## Implementação

- Catálogo autenticado `get_guincho_transport_catalog` compartilhado pelo formulário de veículos, cadastro do guincheiro e frota.
- Categoria opcional no cadastro geral de veículo; obrigatória para solicitar transporte. Regularização disponível na Garagem sem presumir categoria pelo nome/modelo.
- Porte obrigatório no cadastro de guincho; editor da frota com placa, marca, modelo, cor, porte e seleção do veículo de atendimento. RPCs validam posse, revisão e compatibilidade.
- Descoberta/cotação/reserva usam as regras e preços do servidor. Snapshots preservam veículo, porte e versão do preço; dinheiro permanece Decimal.
- Retomada autenticada de contexto persistido, preservando o endereço integral, o veículo e as coordenadas. Exclusões e geração são controladas pelo backend. ACTIVE_DISPATCH precede qualquer busca retomável.
- Reconciliação em primeiro plano a cada 2 segundos somente nas rotas de início/atendimento corrente. A navegação é substituída, removendo a espera anterior. Histórico não inicia retomada.
- Saída explícita da busca fecha o contexto com `cancel_my_guincho_search`; falhas preservam o estado para nova tentativa.
- Edição de cadastro para cliente, PitTec, loja e guincho. Endereço de prestador passa pela prova de geocodificação; atualizações usam timestamps esperados. E-mail e documento permanecem somente leitura.
- Seleção de marca equivalente ao Android; destino no topo, status antes do mapa e bordas roxas nos cards da home do guincho.

## Dependências

As migrations e a Edge Function do commit Android são a implementação compartilhada do backend. Este porte não reaplica migrations nem modifica bancos remotos. O ambiente de execução precisa das migrations `20261103090000` até `20261103125000` e dos pré-requisitos comerciais do mesmo commit. Cadastro de catálogo/matriz/preços e administração ficam no dashboard externo.

Não declarar paridade operacional validada apenas pela compilação: testar cliente e prestador autenticados, backend atualizado, recusa paga/não paga, retorno ao app, micro-ônibus e concorrência.
