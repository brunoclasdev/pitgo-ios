# Quickstart: validar a experiência mockada de UI do PitTec (iOS)

## Pré-requisitos

- Xcode estável mais recente, SDK iOS 17+, dispositivo físico recomendado (localização real
  obrigatória para a Home do provider).
- Contas de teste: uma conta cliente e uma conta provider já cadastrada como PitTec (`009`/`016`).
- Autorização de localização concedida no dispositivo do provider.

Este protótipo não usa backend novo; nenhuma migration ou Edge Function é aplicada.

## 1. Build

```bash
xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'platform=iOS Simulator,name=iPhone 16' clean build
```

Esperado: build sucede sem dependência nova.

## 2. Receber e responder a uma chamada na Home PitTec (US1)

1. Entre como provider PitTec e abra sua Home: confirme que o mapa mostra a posição real do
   dispositivo e uma indicação textual de disponibilidade.
2. Recuse a permissão de localização ou desative os serviços de localização: confirme que o mapa
   fica bloqueado, sem posição simulada, com ações para conceder permissão/ativar localização.
3. Com localização concedida, aguarde/dispare a solicitação simulada: confirme três pulsos roxos em
   até 3s e um card roxo persistente com "Aceitar"/"Recusar".
4. Toque "Aceitar": confirme transição única para aceito e abertura do mapa de acompanhamento.
5. Repita e toque "Recusar": confirme fim do alerta, retorno a Disponível e nenhum atendimento
   iniciado.
6. Ative "Reduzir Movimento" (Ajustes > Acessibilidade) e repita: confirme que o card aparece
   estático, com a mesma informação e ações.

## 3. Conferir e confirmar a estimativa antes da busca (US2)

1. Como cliente, abra o card PitTec: confirme que a apresentação inicial é preservada.
2. Toque "Buscar PitTec": confirme estimativa com perímetro, R$ 50,00 fixo, adicional e total,
   conforme o cenário simulado atingir 5km (R$ 60,00) ou 10km (R$ 70,00).
3. Toque "Confirmar": confirme que a ação não pode ser repetida e um feedback informa que o app está
   buscando um PitTec.
4. Volte/cancele antes de confirmar: confirme que nenhuma busca simulada é iniciada.
5. Deixe um candidato recusar: confirme que o cliente é informado e a busca consulta
   automaticamente o próximo, ampliando o perímetro em 5km apenas quando necessário.

## 4. Acompanhar o encontro no mapa (US3)

1. Com uma solicitação aceita (cliente ou provider), confirme que o mapa enquadra os dois
   participantes inicialmente, com distância e valor total.
2. Aguarde 30s: confirme que a posição simulada do PitTec, o marcador e a distância são atualizados
   sem recarregar a tela.
3. Mova o mapa manualmente e aguarde uma atualização: confirme que a câmera não interrompe sua
   exploração e uma ação permite recentralizar.
4. Deixe uma atualização atrasar (mais de 35s): confirme aviso de posição desatualizada mantendo o
   último ponto conhecido.

## 5. Confirmar encontro e conclusão pelos dois participantes (US4)

1. Em qualquer perfil, no estado de deslocamento, toque "Já nos encontramos": confirme que o
   serviço não começa imediatamente e a UI informa que aguarda a outra confirmação.
2. Aguarde 3s: confirme a transição automática para "Serviço em andamento".
3. Toque "Finalizar serviço": confirme que o atendimento permanece aberto até a confirmação
   automática de 3s, então muda para "Concluído" e interrompe as atualizações.
4. Toque novamente em uma ação já confirmada: confirme que nenhuma confirmação duplicada é criada.

## 6. Navegar pelas áreas do PitTec (US5)

1. Como provider PitTec, confirme a `TabView` com "Mapa", "Dados da corrida", "Valores" e "Perfil".
2. Antes de qualquer aceite: confirme estado vazio explicativo em "Dados da corrida" e "Valores".
3. Após um aceite: confirme que "Dados da corrida" mostra participantes/perímetro/distância/estado
   e "Valores" mostra a composição (R$ 50,00 + R$ 10,00 × faixas) do mesmo atendimento.
4. Confirme que nenhuma lista de corridas, saldo ou extrato aparece.

## 7. Acessibilidade e ausência de efeitos reais

- Em iPhone compacto, landscape e Dynamic Type grande: confirme que todas as telas permanecem
  utilizáveis, com rolagem quando necessário.
- Com VoiceOver: confirme anúncios de mudança de estado sem depender de mapa/cor/movimento.
- Inspecione tráfego de rede (Proxyman/Charles): confirme ausência de chamadas às RPCs de
  descoberta/despacho PitTec, Realtime, publicação de localização, Edge Function de rota ou
  qualquer efeito de cobrança durante todo o roteiro acima.
