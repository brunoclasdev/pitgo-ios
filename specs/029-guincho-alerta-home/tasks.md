# Tarefas: alerta e Home do guincheiro (porte iOS)

## User Story 1 — oferta e resposta

- [X] Separar GUINCHO_DIRECT/PENDING do redirecionamento automático e expor o snapshot elegível para a interface global.
- [X] Criar card global com cliente, veículo, retirada, destino, remuneração, prazo e ações autorizadas pelo backend.
- [X] Responder com appointment/revision vigentes, bloquear toque repetido e revalidar o resultado antes de abrir tracking.
- [X] Reusar o estado do dashboard acima da `NavigationStack` e apresentar card único sem trocar a rota.
- [X] Notificar em background com conteúdo genérico e deduplicação por conta/pedido; ao tocar, o app recupera o snapshot autenticado vigente.
- [X] Revalidar resposta, expiração e remover notificação ao aceitar/recusar/encerrar ou trocar de sessão.

## User Story 2 — Home e mapa

- [X] Exibir o mapa de guincheiro móvel em `ProviderDashboardView`, mantendo Fixo e PitTec nas raízes existentes.
- [X] Exibir localização negada, Serviços de Localização desligados e fix antigo; esconder do mapa fix com mais de 35 segundos.
- [X] Atualizar marcador com o stream já usado para publicação e oferecer Recentralizar sem desfazer pan manual.
- [X] Preservar perfil e disponibilidade na Home e adicionar histórico paginado para o prestador móvel.

## User Story 3 — retomada

- [X] Recuperar PENDING com deadline original e abrir os estados aceitos/em execução/aguardando confirmação na view de Guincho vigente.
- [X] Retornar automaticamente à Home quando o snapshot confirmar encerramento do fluxo de Guincho.

## Verificação

- [X] Builds Dev (`pitgo`), Homol (`pitgo-Homol`) e Prod (`pitgo-Prod`) para o simulador.
- [ ] Revisão manual dos cenários FR-001–FR-016 com duas contas.
- [ ] Validação manual com duas contas e notificação em aparelho real pendente.
