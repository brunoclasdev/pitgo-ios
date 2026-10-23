# Plano iOS — navegação externa e indicação de localização

1. Reutilizar os estados atuais de Guincho/PitTec para limitar a ação às etapas de deslocamento autorizadas.
2. Consultar novamente o atendimento e o destino ao preparar e ao confirmar a escolha do navegador.
3. Abrir somente Waze (`waze://`) ou Google Maps (`comgooglemaps://`) com coordenadas do destino; identificar disponibilidade com `canOpenURL` e declarar apenas esses esquemas.
4. Manter uma ação acessível no atendimento, sem registrar chegada, início, aprovação ou conclusão, e apresentar falhas localmente.
5. Revisar os mapas de acompanhamento para manter marcador padrão, posição válida e mensagem textual de frescor/indisponibilidade sem relógio.
6. Validar os três esquemas de build, plist e diff; registrar validações manuais que dependem de navegadores instalados e contas reais.

## Contrato por etapa

| Fluxo | Elegibilidade | Destino consultado novamente |
|---|---|---|
| Guincho | `GUINCHO_DIRECT`, tracking autorizado, `ACCEPTED` sem chegada ou `IN_PROGRESS` | Retirada antes de iniciar transporte; destino contratado durante o transporte |
| PitTec | `ACCEPTED` e sem chegada | Localização vigente do cliente obtida em `get_pittec_route_context` |

O seletor informa opções indisponíveis, não usa fallback web/loja/outro navegador e permanece no acompanhamento em falhas. O navegador recebe só a coordenada final e parâmetros constantes de rota.
