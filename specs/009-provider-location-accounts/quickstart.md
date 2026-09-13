# Quickstart: validar contas, cadastro, mapa e localização (iOS)

Este é um roteiro de validação manual. Não contém suíte de testes automatizados nem corpo de
migration/Edge Function de produção — tudo isso já existe no backend compartilhado.

## Prerequisites

- Xcode estável mais recente, SDK iOS 17+, simulador/dispositivo iOS 17+;
- Supabase CLI apenas para **verificação** (leitura) do schema/Edge Functions já aplicados — nenhuma
  migration/Function nova é criada ou aplicada por esta feature;
- o mesmo projeto Supabase de desenvolvimento já usado para validar a feature Android equivalente,
  com `account_roles`, `providers.account_id`, geocodificação, discovery PostGIS, `appointments` e
  `provider_current_locations` já aplicados, e as Edge Functions `geocode-provider-address`/
  `refresh-provider-geocodes` já publicadas;
- `Config/Secrets.xcconfig` com `supabaseUrl`/publishable key (`004`);
- pelo menos uma categoria e um serviço ativos no catálogo;
- dois dispositivos/simuladores para cenários de conflito de publisher/Realtime; preferir ao menos
  um dispositivo físico para os cenários de localização em background.

Nenhuma chave de mapa é necessária no client iOS (ver `contracts/geocoding-edge-function.md`) —
diferente do Android, que precisa de `MAPS_API_KEY`.

## 1. Verify the shared backend (no migration/function applied here)

```bash
supabase link
supabase db diff
supabase functions list
```

Esperado: nenhuma diferença de schema pendente relevante; `account_roles`, o desacoplamento
`providers.id`/`account_id`, `provider_categories`, os campos geoespaciais de `addresses`,
`appointments`, `provider_current_locations` e todas as RPCs de `contracts/` já existem;
`geocode-provider-address`/`refresh-provider-geocodes` aparecem como Functions publicadas. Qualquer
divergência deve ser corrigida na migration/Function do repositório Android.

## 2. Build the iOS app

```bash
xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'platform=iOS Simulator,name=iPhone 16' clean build

xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'generic/platform=iOS' clean build
```

Esperado: ambos sucedem; o pacote `supabase-swift` resolve `Functions`/`Realtime` sem nova
dependência; MapLibre Native iOS resolve via SPM; nenhum arquivo de teste automatizado é adicionado.

## 3. Client versus provider account

1. Na Welcome, criar um cliente normal.
2. Confirmar `account_roles = CLIENT`, um Profile existe e nenhum Provider é criado.
3. Sair. Tocar "Sou uma empresa · Cadastrar".
4. Confirmar que a primeira tela é criação de conta de provider, não o SignUp de perfil/CPF.
5. Concluir o SignUp Auth e interromper antes do onboarding da empresa terminar.
6. Entrar novamente com as credenciais do provider. Confirmar que retoma Provider Registration e
   nunca abre a Home/onboarding de veículo do cliente.
7. Concluir o cadastro do provider e confirmar que abre o Provider Dashboard.
8. Tentar o e-mail do cliente para o signup de provider e vice-versa. Confirmar mensagem genérica de
   conta indisponível e nenhuma mutação de papel.
9. Corromper/remover o papel numa fixture local descartável. Confirmar que o app bloqueia em vez de
   adivinhar.

## 4. Provider registration and location verification

Exercitar tanto FIXED quanto MOBILE:

- carregamento de catálogo (categoria/serviço), estados vazio, offline e alterado durante o submit;
- múltiplas categorias e serviços, remover/adicionar, prevenção de categoria/serviço duplicado;
- validação de empresa/normalização de CNPJ/telefone;
- fluxo de permissão: rationale antes do prompt, negação, aproximado apenas, negação
  permanente/settings e serviços de localização desligados;
- fix impreciso/antigo e timeout de aquisição de 15 segundos;
- endereço sem correspondência/parcial/região errada/upstream indisponível;
- distâncias medidas de 499m e 501m: a primeira prossegue, a segunda exige confirmação explícita;
- editar um campo do endereço depois de verificado: prova/confirmação devem ser invalidadas;
- toque duplo, submit concorrente e resposta perdida: exatamente um Provider, Address e conjunto de
  linhas `ProviderCategory`/`ProviderService`;
- inspecionar Address: a coordenada persistida é a do endereço geocodificado; nenhuma coordenada de
  dispositivo/histórico existe.

Verificar que um provider FIXED não consegue iniciar tracking móvel. Mudar MOBILE para FIXED e
disponibilidade para off no Provider Dashboard; qualquer linha corrente deve ser removida.

## 5. Legacy assisted migration

Criar uma fixture legada descartável equivalente ao modelo pré-009 (papel CLIENT/perfil possuindo um
Provider com endereço/serviços).

1. Entrar como o cliente e confirmar que o app oferece migração mas não abre a área privada de
   provider.
2. Iniciar a migração, sair intencionalmente e criar/entrar numa conta PROVIDER de e-mail diferente.
3. Concluir qualquer verificação de modalidade/endereço solicitada e reivindicar a transferência.
4. Confirmar que só `providers.account_id`/auditoria de transferência mudaram; Provider ID, Address,
   ProviderCategories e ProviderServices permanecem; Profile permanece CLIENT.
5. Repetir a reivindicação após resposta simulada perdida: receber `ALREADY_MIGRATED`, sem cópias.
6. Validar token expirado, destino errado, mesmo e-mail, destino com Provider existente e
   reivindicações concorrentes. Cada caso deve deixar a propriedade inalterada e não expor detalhes
   de conta.

## 6. Service map discovery

1. Semear Providers ativo/inativo, disponível/indisponível, FIXED/MOBILE em serviços/categorias e
   distâncias de endereço variadas. Manter todas as linhas de localização móvel corrente ausentes ou
   deliberadamente diferentes.
2. Entrar como CLIENT e tocar um card de serviço da Home.
3. Confirmar que a rota carrega o UUID real do serviço e retorna somente correspondências exatas de
   serviço+categoria.
4. Confirmar que ambos os modos de provider plotam o endereço empresarial, nunca o ponto móvel
   corrente.
5. Fazer pan/zoom e usar "Buscar nesta área"; trocar rapidamente de serviço/viewport e confirmar que
   respostas antigas não substituem os resultados atuais.
6. Negar localização do cliente: o mapa ainda abre numa região selecionada/manual e o resto do app
   funciona.
7. Validar loading, vazio, offline, retry, clustering e marcadores sobrepostos (MapLibre Style Spec).
8. Alternar Mapa/Lista, usar VoiceOver e Dynamic Type grande; todo resultado/ação deve permanecer
   disponível sem depender da cor do marcador ou de janelas de informação.
9. Inspecionar resposta/UI: nenhum CNPJ, contato, UUID de conta do owner, coordenada de cliente ou
   coordenada móvel.

Meta: primeiros resultados ou estado vazio compreensível em até 3 segundos com conectividade normal.

## 7. Mobile tracking and private Realtime

Como o despacho de atendimento está fora do escopo, inserir uma fixture autoritativa descartável de
`Appointment` via SQL administrativo/local, nunca via payload do app. Associar um CLIENT, um
Provider MOBILE e um serviço exatamente ofertado; definir `ACCEPTED`.

1. Iniciar tracking a partir da tela visível de atendimento do provider, com autorização
   `.authorizedAlways` concedida no momento da ação.
2. Confirmar o indicador de sistema de uso de localização (barra/pílula azul) e publicações a cada
   ~10 segundos.
3. Minimizar o app: com `.authorizedAlways`, as atualizações continuam; sem ela (só
   `.authorizedWhenInUse`), o produto explica e limita o tracking ao modo de tela visível.
4. O CLIENT participante assina e vê o marcador se mover sem reabrir a tela. Um terceiro CLIENT e a
   descoberta pública devem falhar ao entrar/ler.
5. Eventos de parada: COMPLETED, CANCELLED, logout, troca/expiração de sessão, revogação de
   permissão, serviços de localização desligados, provider FIXED/inativo/indisponível. Cada um deve
   parar a publicação e limpar a linha corrente.
6. Encerrar o processo do app (matar). Não deve reiniciar sozinho; a UI do participante muda para
   stale após 30 segundos.
7. Desconectar a rede: só o fix válido mais recente permanece em memória; reconectar publica o fix
   atual, não um trajeto.
8. Iniciar tracking num segundo dispositivo provider: recebe conflito de publisher enquanto o
   primeiro publish está fresco e só pode assumir depois de >30 segundos. Sequência/timestamp antigos
   nunca devem regredir marcador/versão.
9. Desconectar/reconectar o Realtime do participante. Deve rebuscar o snapshot e descartar versões de
   Broadcast duplicadas/antigas.

Meta: nova posição válida refletida em até 10 segundos com conectividade normal; nenhum marcador
rotulado como ao vivo depois de 30 segundos sem uma publicação válida do servidor.

## 8. Geocode retention and privacy audit

- Avançar um `geocoded_at` descartável para o dia 25 e rodar o refresh (Edge Function já existente);
  confirmar que a validade é renovada.
- Simular falha de refresh além de 30 dias; o Provider é excluído da descoberta sem apagar dados.
- Simular uma mudança material do ponto upstream; marcar para reverificação em vez de mover
  silenciosamente.
- Buscar em logs/crash output e arquivos rastreados por tokens de Auth, chaves de API, CNPJ, tokens
  de transferência, pontos de dispositivo e payloads brutos de exceção Supabase/Google; nenhum deve
  estar presente.
- Confirmar que as tabelas contêm no máximo uma localização corrente e nenhuma coleção histórica de
  rota/fix.

## 9. iOS version/device matrix

- iOS 17/18: fluxo de permissão `.authorizedWhenInUse`/`.authorizedAlways` e degradação para
  "aproximada" (`CLAccuracyAuthorization.reducedAccuracy`).
- comportamento do indicador de sistema de uso de localização (não há permissão de notificação
  equivalente ao Android a testar).
- portrait, landscape, larguras compactas/expandidas e Dynamic Type grande.
- dispositivo físico com serviços de localização desligados e o app finalizado pelo sistema em
  background, quando possível.
