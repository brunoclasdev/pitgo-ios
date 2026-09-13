# Quickstart: validar PitTec sob demanda (iOS)

## Pré-requisitos

- Xcode estável mais recente, SDK iOS 17+, dispositivo físico recomendado (notificações locais e
  localização em background funcionam de forma limitada em simulador).
- O mesmo projeto Supabase de desenvolvimento já usado para validar a feature Android equivalente,
  com o `dispatch_kind`/modalidade PitTec, todas as RPCs e a Edge Function `pittec-route` já
  aplicados/publicados.
- Ao menos três contas provider elegíveis para PitTec (ativas, disponíveis, oferta PitTec, posição
  publicável) e uma conta cliente.
- Autorização de notificação e de localização concedidas nos dispositivos de teste do provider.

Não executar `supabase db push`/deploy de função: esta feature não altera o backend.

## 1. Verificar o backend compartilhado (somente leitura)

```bash
supabase link
supabase db diff
supabase functions list
```

Esperado: `dispatch_kind = PITTEC_AUTO_SEQUENTIAL`, `location_mode = PITTEC`,
`appointment_route_snapshots` e todas as RPCs de `contracts/pittec-rpcs.md` já existem;
`pittec-route` aparece publicada.

## 2. Build

```bash
xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'platform=iOS Simulator,name=iPhone 16' clean build
```

Esperado: build sucede sem dependência nova.

## 3. Cadastrar empresa como PitTec (US5)

1. No cadastro empresarial (`007`/`009`), confirme as três modalidades mutuamente exclusivas: Fixa,
   Móvel, PitTec, cada uma com descrição compreensível.
2. Cadastre uma empresa como PitTec com oferta ativa do serviço PitTec.
3. Ative disponibilidade: confirme que exige autorização de localização e de notificação.
4. Altere a modalidade para Fixa/Móvel durante um atendimento aceito: confirme que a mudança fica
   pendente e só se aplica após o encerramento.

## 4. Encontrar PitTecs próximos no mapa (US1)

1. Como cliente, toque no card PitTec na Home.
2. Confirme o mapa centrado na posição do cliente com marcadores aproximados e distintos dos
   PitTecs elegíveis.
3. Confirme que empresas fixas/móveis não aparecem nesse mapa.
4. Sem PitTec elegível na área: confirme mensagem clara e ação de tentar novamente.
5. Com localização recusada/desativada: confirme explicação e ação de conceder acesso.

## 5. Chamar automaticamente o PitTec mais próximo (US2)

Configure três PitTecs elegíveis: o primeiro para recusar, o segundo para não responder, o terceiro
para aceitar.

1. Toque "Chamar PitTec" uma vez: confirme card inferior de busca e oferta genérica ao mais próximo.
2. Confirme que o primeiro recusa e o cliente é informado antes do avanço automático.
3. Confirme que o segundo expira em 60s sem resposta e o avanço é automático.
4. Confirme que o terceiro aceita: a busca para imediatamente e o cliente entra no acompanhamento.
5. Repita esgotando todos os candidatos até 50km: confirme estado vazio com "Tentar novamente".
6. Toque "Chamar PitTec" repetidamente durante o processamento: confirme uma única busca ativa.

## 6. Acompanhar a chegada do PitTec (US3)

1. Com a chamada aceita, confirme mapa enquadrando cliente e PitTec com marcadores distintos.
2. Com rota disponível: confirme linha sólida e distância restante em km.
3. Force indisponibilidade do roteador: confirme linha tracejada identificada como estimativa.
4. Movimente o dispositivo do provider: confirme marcador, distância e rota atualizados sem reabrir
   a tela.
5. Deixe a posição do provider ficar sem atualização por 30s: confirme aviso de desatualização sem
   apresentar como tempo real.
6. Confirme "Cheguei" e depois "Concluir atendimento": cada confirmação reflete no cliente e o
   acompanhamento só termina após a conclusão ou cancelamento válido.

## 7. Receber e responder a uma chamada PitTec (US4)

1. Envie uma oportunidade a uma conta PitTec disponível: confirme distância aproximada, prazo e
   ações Aceitar/Recusar.
2. Aceite dentro do prazo: confirme reserva exclusiva e acesso ao mapa do atendimento.
3. Recuse: confirme que a participação termina e o despacho segue sem criar dois atendimentos.
4. Deixe expirar (60s): tente aceitar depois — confirme rejeição com explicação compreensível.
5. Com o app em segundo plano e a tela bloqueada, envie uma nova oferta: confirme alerta visível e
   sonoro (notificação local) que abre a chamada com o prazo restante ao ser tocado.

## 8. Cancelamento

1. Após aceite, cancele pelo cliente informando um motivo: confirme encerramento sem nova busca.
2. Cancele pelo provider informando um motivo: confirme retomada automática da busca do cliente.

## 9. Retomada e segurança

1. Feche e reabra o app durante uma busca/atendimento ativo: confirme retomada sem duplicar a
   solicitação.
2. Troque de conta: confirme que nenhum dado da chamada anterior permanece visível.
3. Confirme que uma conta não participante não acessa a posição exata do cliente nem detalhes do
   atendimento aceito.

## 10. Acessibilidade

Em iPhone compacto, landscape e Dynamic Type grande: mapa, card e ações permanecem legíveis e
acionáveis sem depender de cor/ícone/movimento; VoiceOver anuncia estados relevantes; alvos de
toque `>=44×44pt`.
