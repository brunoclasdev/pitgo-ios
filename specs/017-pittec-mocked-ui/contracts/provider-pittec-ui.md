# UI Contract: Home e navegação mockadas do prestador PitTec (iOS)

## Route selection and isolation

- `.authenticatedProviderReady` com `locationMode == .pittec` abre o shell mockado
  `PitTecProviderMockView`.
- FIXED e MOBILE continuam usando o Dashboard real atual (`009`/`013`) sem mudança funcional.
- A rota PitTec mockada não instancia `ProviderDashboardViewModel` real, não restaura dispatch e
  não inicia tracking/notificações reais.
- Ao detectar sessão PITTEC, o app remove `.pittec` do `ProviderLocationTracker` real e envia uma
  parada puramente local para eventual tracking legado; essa parada cancela coleta/notificação
  local sem RPC nem alteração de disponibilidade remota.

## Location gate

O mapa é composto somente em `ProviderLocationGate.ready`.

| Estado | Conteúdo obrigatório | Ação |
|---|---|---|
| `.checkingPermission` | feedback de verificação | nenhuma |
| `.permissionRequired` | localização precisa necessária | solicitar `.authorizedWhenInUse` |
| `.approximateOnly` | precisão aproximada não atende à Home | solicitar precisão total/abrir Ajustes |
| `.servicesDisabled` | localização do sistema desativada | abrir Ajustes de localização |
| `.locating` | obtendo posição real | aguardar com progresso textual |
| `.unavailable` | não foi possível obter fix no timeout | tentar novamente |
| `.ready` | mapa, marcador real do PitTec e estado Disponível | permitir evento mock |

Ao retornar dos Ajustes ou o app voltar a `.active`, a View revalida permissões e serviços. Nenhuma
coordenada mock é mostrada enquanto o gate estiver bloqueado. A posição real é lida em primeiro
plano, mantida apenas em memória e nunca publicada.

## Incoming request

- A fixture gera uma solicitação uma vez quando a Home está pronta; os estados disponível/concluído
  também oferecem "Simular nova solicitação" para repetir a demonstração explicitamente.
- O ViewModel cria `MockServiceRequest` com revisão nova e `pulseConsumed = false`.
- Se animações estiverem habilitadas (`!UIAccessibility.isReduceMotionEnabled`) e o efeito ainda não
  tiver sido consumido, a View faz exatamente três pulsos roxos em até 3s e marca o efeito
  consumido no início.
- Com redução de movimento ativa, o pulso é omitido. Em todos os casos, um card roxo persistente
  contém cliente, perímetro/distância, total, "Aceitar" e "Recusar".
- O card usa texto/estrutura/semântica além da cor e permanece acionável após o efeito.
- `onAccept()` e `onDecline()` competem pela mesma revisão: a primeira ação válida vence, desabilita
  imediatamente ambas e qualquer repetição vira no-op.
- Recusar remove o alerta e volta a Disponível. Aceitar cria um atendimento local e abre o mapa de
  acompanhamento em até 2s.

## Bottom navigation

O mesmo componente visual `PitGoBottomTabs`/`TabView` (`002`) recebe uma variante
`PitTecProviderTabs` nesta ordem:

1. Mapa
2. Dados da corrida
3. Valores
4. Perfil

Ícone (SF Symbol) e rótulo aparecem conforme o componente atual. A seleção usa indicador, ícone e
texto, nunca somente cor. As quatro áreas são abas dentro da mesma `View` e compartilham o mesmo
estado.

### Mapa

- Renderiza localização real em Disponível/Incoming e ambos os participantes após aceite.
- Contém estado textual e ações correspondentes.

### Dados da corrida

- Antes do primeiro aceite: estado vazio explicativo.
- Depois: cliente, PitTec, perímetro, distância mais recente, estado, solicitação/aceite/início e
  conclusão quando existentes.
- Mostra apenas `currentOrLastAppointment`; não lista histórico.

### Valores

- Antes do primeiro aceite: estado vazio explicativo.
- Depois: R$ 50,00 fixos, R$ 10,00 × faixas, adicional e total do mesmo atendimento mostrado em
  Dados da corrida.
- Não mostra saldo, extrato, ganhos ou ação financeira.

### Perfil

- Mostra dados básicos já presentes no `AccountSnapshot`/`ProviderSnapshot` e a ação de logout
  existente.
- Não reutiliza campos de veículo/endereço exclusivos do perfil cliente e não grava dados.

## Appointment actions

- No deslocamento, "Já nos encontramos" registra a confirmação local uma vez; o card informa que
  aguarda o cliente e avança após resposta automática de 3s.
- Em andamento, "Finalizar serviço" registra uma vez; o card informa que aguarda o cliente e conclui
  após resposta automática de 3s.
- Após conclusão, o movimento para, `currentOrLastAppointment` permanece disponível nas abas e
  "Voltar ao mapa" retorna ao estado Disponível sem apagar o último atendimento.

## Accessibility and layout

- Solicitação nova é anunciada semanticamente; mudanças comuns de estado usam Live Region educada.
- Botões respeitam os alvos de toque existentes (44×44pt); conteúdo das abas é rolável com Dynamic
  Type grande.
- Falha do mapa não remove informações ou ações textuais.
- Light/dark usam os tokens de cor já existentes do design system (`Core/DesignSystem/Colors`, de
  `001`), preservando contraste e o roxo do design system sem cor hardcoded na View.
