# Phase 0 Research: Mapa iOS em paridade de produção com o Android

## 0. Achado que corrige uma premissa da spec: a validação de build do mapa não existe ainda

**Decision**: tratar a extensão do Run Script Build Phase (`Scripts/validate-supabase-config.sh`)
para validar os quatro campos do mapa como trabalho real desta feature — não como "nenhuma mudança
de comportamento", como a spec assumia em FR-003/Assumptions antes desta pesquisa.

**Rationale**: `specs/010-osm-realtime-map/contracts/maplibre-style-runtime.md` já **prometia** essa
validação ("Run Script Build Phase de validação, estendido do de `004`"), mas
`pitgo/Core/Map/Config/ManagedMapStyleConfiguration.swift` documenta explicitamente que ela **não
foi implementada**: sem uma credencial real de provedor gerenciado disponível naquela sessão,
endurecer o gate teria quebrado o único build existente (mesma nota em
`specs/010-osm-realtime-map/tasks.md` T002). Hoje `Scripts/validate-supabase-config.sh` valida
somente `supabaseUrl`/`supabaseKey` — nenhuma linha menciona os campos do mapa. O runtime Swift
(`ManagedMapStyleConfiguration.current`) cai silenciosamente para o estilo de demonstração quando os
valores do `Info.plist` estão ausentes/inválidos — exatamente o comportamento que a User Story 3 da
spec quer impedir em builds de produção. A pré-condição que bloqueava o hardening (falta de
credencial real) deixa de existir nesta feature, então o gate prometido em `010` finalmente pode ser
implementado.

**Impacto na spec**: FR-003 e a terceira Assumption foram reescritas (ver spec.md) para descrever
"adicionar a validação que falta", não "manter uma validação existente inalterada" — o resultado
observável para o usuário/desenvolvedor é o mesmo que a spec original pretendia, só a descrição do
estado inicial foi corrigida.

**Alternatives considered**: criar um segundo Run Script Build Phase dedicado ao mapa — rejeitado
por duplicar a infraestrutura (parse de Build Settings, função `fail`, convenção de mensagens) que
`validate-supabase-config.sh` já resolve; o precedente do Android (`app/build.gradle.kts`) também
mantém `validateSupabaseConfiguration` e `validateMapStyleConfiguration` como duas funções no mesmo
arquivo de build, não dois mecanismos — replicar essa estrutura (duas seções/funções, um script) é
mais simples e mantém paridade com o Android.

## 1. O renderizador de mapa já é funcional — não há trabalho de rendering nesta feature

**Decision**: não tocar em `pitgo/Core/UI/PitGoMapView.swift`, `ManagedMapStyleConfiguration.swift`
(além do comentário desatualizado) nem nas Views que os consomem (`ServiceMapView`,
`AppointmentTrackingView`, etc.).

**Rationale**: `specs/010-osm-realtime-map/tasks.md` tem várias tarefas `[ ]` (não concluídas) que
descreviam um design mais elaborado (`MapLibreMapHost` dedicado + `Coordinator` por feature com
`MLNShapeSource` clusterizada em GeoJSON). Na prática, o time entregou uma solução mais simples e já
funcional: `PitGoMapView` (`UIViewRepresentable` único sobre `MLNMapView`, com
`MLNPointAnnotation`, ícones customizados por SF Symbol e linha de rota), reaproveitado por todas as
telas com mapa, já lendo `ManagedMapStyleConfiguration.current.styleURL`. As tarefas `[ ]` de `010`
refletem que o *desenho original do plano* não foi seguido à risca — não que o mapa esteja
quebrado ou incompleto para o usuário final. Confirmado por leitura do arquivo: ele já trata
anotações, seleção, callback de região e linha de rota. Isso está alinhado com a constitution
(Princípio I — KISS/YAGNI: preferir a solução mais simples que atende ao requisito).

**Consequência para o escopo**: esta feature é puramente configuração + validação de build, como a
spec já delimitava (FR-006). Nenhum novo arquivo Swift de UI/ViewModel/Repository é necessário.

**Alternatives considered**: retomar o plano original de `010` (host dedicado + GeoJSON
clusterizado) como parte desta feature — rejeitado; está fora do pedido do usuário ("deixar
funcionando igual ao Android" refere-se ao estilo visual do provedor de tiles, não a uma
refatoração da camada de renderização já funcional) e violaria YAGNI/escopo mínimo.

## 2. Origem e formato do valor de produção (mesmo provedor do Android)

**Decision**: os quatro valores de produção (`mapStyleUrl`, `mapStyleProviderName`,
`mapStyleAttribution`, `mapStyleAttributionUrl`) já existem, configurados localmente no projeto
Android (`local.properties`, não rastreado), apontando para um provedor de tiles gerenciado
compatível com MapLibre. Serão copiados para `Config/Secrets.xcconfig` do iOS (também não
rastreado) sem modificar o mecanismo de leitura já existente.

**Rationale**: atende literalmente ao pedido do usuário ("pegar as chaves/URL necessárias no
arquivo de configuração local do projeto Android") e à Assumption já registrada na spec de que o
mesmo provedor é reaproveitado, não um novo provisionamento.

**Cuidado de codificação encontrado**: o valor de `mapStyleAttribution` no `local.properties` do
Android contém caracteres acentuados/símbolos (`©`, `·`) gravados em Latin-1/CP1252 (bytes `0xA9`/
`0xB7` avulsos), não em UTF-8 (`0xC2 0xA9`/`0xC2 0xB7`). Um `.xcconfig` do Xcode é lido como UTF-8;
copiar os bytes brutos produziria texto corrompido na atribuição exibida no app. **Decision**: ao
transcrever o valor para `Config/Secrets.xcconfig`, digitar/normalizar os caracteres como UTF-8
(`©`, `·`) em vez de copiar os bytes originais — mesmo texto visível, codificação corrigida.

**Alternatives considered**: copiar o arquivo `local.properties` byte a byte — rejeitado, quebraria
a exibição da atribuição no app iOS (texto é uma obrigação funcional da FR-002/SC-002, não pode
sair corrompido).

## 3. Regras de validação a implementar (grammar já definida em `010`, não revisitada aqui)

**Decision**: implementar exatamente a tabela e as regras já documentadas em
`specs/010-osm-realtime-map/contracts/maplibre-style-runtime.md` ("Build boundary" e "Falhas
obrigatórias") — HTTPS absoluta sem user-info/fragment/placeholder para `mapStyleUrl`/
`mapStyleAttributionUrl`; texto público não vazio para `mapStyleProviderName`/`mapStyleAttribution`;
e rejeição de hosts demo/públicos conhecidos (`demotiles.maplibre.org`, `tile.openstreetmap.org` e
subdomínios) para `mapStyleUrl`. Nenhuma regra nova é criada; esta feature apenas implementa o que
já estava especificado.

**Rationale**: reabrir a grammar de validação seria retrabalho sem valor — `010` já fez esse design
e ele nunca foi contestado, só não foi implementado.

**Alternatives considered**: nenhuma — decisão de design já tomada em `010`.

## 4. Verificação de credencial pública, não administrativa

**Decision**: confirmar que o valor de `mapStyleUrl` de produção carrega uma chave de tipo
"cliente/pública" do provedor (equivalente ao token restrito por domínio/app que provedores de
tiles emitem para uso em app móvel), nunca uma chave de conta/administrativa. O script de validação
não pode inspecionar isso automaticamente (o formato da chave é específico de cada provedor, ao
contrário do JWT do Supabase) — é uma verificação manual documentada em `quickstart.md`, mesma
natureza da revisão manual já pedida no contrato de `010` ("CI/pre-release deve inspecionar
manualmente o estilo escolhido").

**Rationale**: consistente com a constitution (segredos de build DEVEM ser chave pública, nunca
administrativa) e com o próprio contrato de `010`, que já não exigia validação automática de tipo
de chave por provedor — só de forma de URL.

**Alternatives considered**: hardcodar uma lista de prefixos de chave conhecidos por provedor —
rejeitado, acopla o script a um provedor específico sem necessidade (a spec é agnóstica de
provedor; hoje é MapTiler, amanhã pode não ser).
