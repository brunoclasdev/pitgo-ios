# Quickstart: validar busca e despacho de prestadores móveis (iOS)

## Pré-requisitos

- Xcode estável mais recente, SDK iOS 17+, simulador/dispositivo iOS 17+; dispositivo físico
  recomendado para os cenários de localização em background.
- O mesmo projeto Supabase de desenvolvimento já usado para validar a feature Android equivalente,
  com o schema de despacho, as ~10 RPCs, o Supabase Cron de expiração e o Broadcast privado já
  aplicados.
- Um serviço de guincho confirmado com `dispatch_kind = MOBILE_SEQUENTIAL` no catálogo.
- Ao menos três contas provider `MOBILE` elegíveis (ativas, disponíveis, com oferta de guincho e
  posição publicável) e uma conta cliente.
- Dois dispositivos/simuladores para o cenário de conflito de aceite/expiração concorrente.

Não executar `supabase db push`/migration nova: esta feature não altera o backend.

## 1. Verificar o backend compartilhado (somente leitura)

```bash
supabase link
supabase db diff
```

Esperado: `service_searches`, `private.dispatch_candidates`, as colunas de despacho em
`appointments`, `provider_discovery_locations` e todas as RPCs de `contracts/mobile-dispatch-rpcs.md`
já existem. Confirme também que o job `private.expire_due_mobile_dispatch_requests` está agendado
via Supabase Cron.

## 2. Build

```bash
xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'platform=iOS Simulator,name=iPhone 16' clean build
```

Esperado: build sucede sem dependência nova.

## 3. Disponibilizar empresa móvel

1. Entre como provider móvel elegível; abra o Dashboard.
2. Ative "Disponível".
3. Confirme o indicador de sistema de uso de localização em background.
4. Desloque o dispositivo/simulador e confirme (via inspeção administrativa) que
   `provider_discovery_locations` atualiza aproximadamente a cada 10 segundos.
5. Desative "Disponível" e confirme que a linha de discovery é removida.

## 4. Buscar e comparar guinchos

1. Entre como cliente e toque no card de guincho na Home.
2. Confirme a rota `mobileDispatch(serviceID:)` e o estado "Buscando prestador".
3. Confirme que o primeiro candidato é o elegível mais próximo, com nome, preço, localidade e
   distância.
4. Toque "Próximo" repetidamente e confirme que candidatos não se repetem na mesma busca.
5. Esgote os candidatos até 10km e confirme a expansão automática para 25km, depois 50km.
6. Esgote todos os candidatos até 50km e confirme o estado vazio com "Buscar novamente".

## 5. Solicitar, aceitar, recusar, expirar

1. Solicite um guincho; confirme o estado "Aguardando prestador" e o preço marcado como garantido.
2. No dispositivo do provider, confirme a `ProviderIncomingRequestView` com deadline visível.
3. Aceite: confirme "Atendimento aceito" no cliente e acesso ao tracking (`009`/`010`).
4. Repita solicitando outro guincho e deixe o provider recusar: confirme que a busca retoma
   automaticamente pelo próximo candidato.
5. Repita e deixe a proposta expirar (60 segundos sem resposta): confirme a mensagem de expiração e
   o avanço automático da busca.
6. Confirme que, após aceitar, o provider fica reservado e não recebe novas solicitações até o
   término.

## 6. Cancelamento

1. Após aceite, cancele pelo cliente informando um motivo: confirme encerramento sem nova busca
   automática.
2. Repita e cancele pelo provider informando um motivo: confirme que o cliente retoma a busca
   automaticamente pelo próximo candidato elegível.
3. Confirme que ambos exigem motivo obrigatório e que o autor/motivo ficam registrados.

## 7. Retomada após reinício

1. Inicie uma busca, avance até "Opção encontrada" e finalize o app (encerrar via multitarefa).
2. Reabra com a mesma conta e confirme que o `DispatchResumeCoordinator` restaura exatamente aquele
   estado.
3. Repita para "Aguardando prestador" e "Atendimento aceito".
4. Troque de conta (logout/login) e confirme que nenhum dado da solicitação anterior permanece
   visível.

## 8. Concorrência e resposta perdida

1. Toque "Solicitar"/"Próximo"/"Aceitar" repetidamente e confirme uma única transição por decisão.
2. Simule perda de rede logo após uma mutation e confirme que o snapshot subsequente reflete o
   estado real sem duplicar solicitação.
3. Com dois dispositivos provider, force um conflito de publisher no tracking pós-aceite (mesmo
   racional de `009 quickstart.md §7.8`).

## 9. Segurança e privacidade

- Um cliente não vê CNPJ, contato ou coordenada de outra solicitação.
- Um provider não recebe solicitações concorrentes enquanto reservado.
- Logs não contêm token, `Error` bruto, coordenada de terceiros ou detalhe SQL.
- `provider_discovery_locations` não é acessível por SELECT direto de nenhuma conta.

## 10. Acessibilidade

Em iPhone compacto, landscape e Dynamic Type grande: proposta, status, countdown e ações
permanecem legíveis e acionáveis sem depender do mapa; VoiceOver anuncia mudanças de estado
relevantes sem repetir a cada atualização de posição; alvos de toque `>=44×44pt` e ação primária
`>=56pt`.
