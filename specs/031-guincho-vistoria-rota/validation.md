# Validação iOS — spec 031

- Catálogo de vistoria: quatro pontos obrigatórios e 13 opcionais nomeados. As fotos continuam vinculadas à versão, autor, descrição e fluxo de correção existente.
- Rota: leitura autorizada do snapshot e chamada autenticada da Edge Function existente. O cliente valida atendimento, destino congelado, versão, LineString, limites geográficos e distância antes de mostrar o caminho.
- O mapa do prestador só ativa a rota em `IN_PROGRESS`; mantém o destino em falhas sem inventar caminho direto, mantém percurso anterior durante atualização e identifica a última origem quando o GPS já não está atual.
- Recalculo por desvio: três fixes distintos, cobrindo ao menos quatro segundos, com idade máxima de dez segundos e precisão máxima de 35 m. Distância à linha é calculada fora da Main Thread; lease e cooldown continuam autoritativos no servidor.
- Renderização: GeoJSON da rota é atualizado por `route_version`; atualizações do marcador e gestos de mapa não reescrevem a linha nem reenquadram a câmera.

## Builds

- [x] Dev — `xcodebuild -scheme pitgo -destination 'generic/platform=iOS Simulator' build`.
- [x] Homol — `xcodebuild -scheme pitgo-Homol -destination 'generic/platform=iOS Simulator' build`.
- [x] Prod — `xcodebuild -scheme pitgo-Prod -destination 'generic/platform=iOS Simulator' build`.
- [x] `git diff --check`.

## Manual

- [ ] Confirmar chegada, vistoria obrigatória, aprovação, início de transporte, rota do pickup atual ao destino contratado e marcador seguindo o GPS.
- [ ] Reabrir atendimento em andamento; validar snapshot/RESUME e atualização para posição atual.
- [ ] Simular GPS antigo/indisponível, espera 202/429, erro de roteador, retomada após falha e fechamento/cancelamento.
- [ ] Validar com dois usuários e aparelho real; esta execução não está disponível no build de simulador.
