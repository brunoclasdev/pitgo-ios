# Phase 0 Research: Pagamento de serviços (Pix e cartão) — iOS

## 0. Backend compartilhado com o Android

**Decision**: As tabelas `payments`/`saved_cards`, as cinco Edge Functions do Mercado Pago e a
guarda de pagamento adicionada aos RPCs de despacho são criadas **uma única vez** no projeto
Supabase compartilhado (`eetbrkznuqbdrnybnyhf`) e reaproveitadas integralmente pelo client iOS.
Nenhuma migration, Edge Function ou RPC nova é autorada neste repositório.

**Rationale**: Mesmo padrão já seguido por todas as specs 004–017 do port iOS — Android e iOS
consomem o mesmo backend. Se a migration/Edge Functions do Mercado Pago já foram publicadas pelo
trabalho Android, este documento apenas consome o contrato resultante; se ainda não foram
publicadas, `contracts/` e `data-model.md` aqui descrevem exatamente o que precisa existir, sem
duplicar autoria entre plataformas.

## 1. Tokenização de cartão no iOS

**Decision**: Usar o SDK oficial do Mercado Pago para iOS (`mercadopago/sdk-ios`, distribuído via
Swift Package Manager, módulo **CoreMethods**) apenas para o formulário de cartão e a geração do
`card_token`; nenhuma outra parte do checkout (resumo, confirmação) usa componentes prontos do SDK,
mantendo a UI 100% SwiftUI já do projeto — mesmo recorte já adotado pelo Android com seu SDK nativo
equivalente.

**Rationale**: É o único caminho suportado para tokenizar PAN/CVV sem colocar o app em escopo PCI
DSS SAQ D — o token é gerado no dispositivo com a Public Key e nunca inclui PAN/CVV em texto claro
no tráfego de rede do PitGo. O módulo CoreMethods do SDK iOS espelha a mesma arquitetura já
verificada no SDK Android (ver [[mercadopago-sdk-tokenization-verified]]): campos seguros
`CardNumberTextField`/`ExpirationDateTextField`/`SecurityCodeTextField` com um `PCIFieldState`, e
uma função de geração de token que devolve um `CardToken`.

**API real confirmada (nível de arquitetura, via `github.com/mercadopago/sdk-ios` e DeepWiki, SDK
0.2.x)**: distribuição SPM; requisito mínimo iOS 13/Swift 6.0 (compatível com o alvo iOS 17+ do
projeto); tokenização via `POST /v1/card_tokens` encapsulada pelo módulo CoreMethods; campos seguros
equivalentes aos do Android, cada um com seu próprio `PCIFieldState`.

**Ação obrigatória antes de codificar** (mesma disciplina de [[mercadopago-sdk-tokenization-verified]]):
como a documentação pública do SDK iOS também é escassa (mesmo padrão observado no Android — SDK
relativamente novo, versão `0.x`), a API exata (nomes de parâmetro, tipo de retorno,
`async`/`await` vs. closure) DEVE ser confirmada lendo o código-fonte do pacote resolvido pelo
Swift Package Manager (`~/Library/Developer/Xcode/DerivedData/.../SourcePackages/checkouts/sdk-ios/`
ou o cache do SPM em `~/Library/Caches/org.swift.swiftpm/`) antes de escrever a integração real, e
validada com um `xcodebuild ... build` limpo — nunca assumida apenas pela documentação online.

**Alternatives considered**:
- Formulário próprio + chamada direta à API de tokenização do Mercado Pago sem o SDK: rejeitado —
  reimplementaria validação de bandeira/BIN e tratamento de erro que o SDK já mantém atualizado, e
  colocaria o app em escopo PCI mais amplo.
- Checkout Pro (redirecionamento web/`SFSafariViewController`): rejeitado nesta rodada porque o
  usuário já decidiu por SDK nativo com tokenização no app (mesma decisão já tomada e documentada no
  research.md original do Android).

## 2. Cartão salvo: Customers + Customer Cards

**Decision**: Ao cadastrar o primeiro cartão, `mp-save-card` cria um "Customer" do Mercado Pago
vinculado ao `client_id` do PitGo (armazenando o `mp_customer_id` na própria tabela `saved_cards`) e
salva o `card_token` gerado no app como "Customer Card" desse Customer, recebendo de volta um
`mp_card_id` reutilizável, junto com bandeira e últimos 4 dígitos — dados que o Mercado Pago já
devolve na resposta, sem o PitGo precisar derivá-los do PAN. Idêntico ao Android, pois é a própria
Edge Function compartilhada que implementa essa regra.

**Rationale**: É o mecanismo do próprio Mercado Pago para cobranças futuras sem redigitar dados; o
`mp_card_id` é estável e pode ser referenciado em `POST /v1/payments` como `token` de pagamentos
futuros, independentemente de qual app (Android ou iOS) o originou.

**Alternatives considered**:
- Guardar o `card_token` original para reuso: rejeitado — tokens de cartão do Mercado Pago são de
  uso único/curta duração (minutos).
- Split de pagamento com repasse automático a prestadores (Marketplace/Application Fee): fora de
  escopo — decisão de produto separada, não solicitada.

## 3. Pix via API de Pagamentos

**Decision**: A Edge Function `mp-create-payment` gera a cobrança Pix chamando
`POST /v1/payments` com `payment_method_id: "pix"`; a resposta traz
`point_of_interaction.transaction_data.qr_code` (copia e cola) e `qr_code_base64` (imagem pronta em
Base64). O client iOS decodifica o Base64 com `Data(base64Encoded:)` e exibe via `UIImage`/`Image`
nativo — **nenhum pacote de geração de QR é necessário**, mesma conclusão do Android.

**Rationale**: Usar o Base64 devolvido pela própria API evita depender de mais uma dependência
(YAGNI) e garante que o QR exibido é exatamente o que o Mercado Pago valida.

## 4. Expiração do código Pix

**Decision**: `date_of_expiration` da cobrança Pix é definida para 30 minutos a partir da criação
(mesmo valor do Android, decisão de backend compartilhado). Ao expirar, o webhook recebe o status
`expired`; o app SwiftUI mostra uma contagem regressiva (`Text(timerInterval:)`/`Task.sleep`) e
oferece gerar um novo código (novo `request_id` de cobrança, mesmo `request_id` de solicitação) ou
trocar de forma de pagamento.

**Rationale**: 30 minutos equilibra tempo suficiente para o cliente pagar sem manter uma solicitação
"presa" por muito tempo sem despachar prestador.

## 5. Verificação do webhook

**Decision**: `mp-webhook` valida o cabeçalho `x-signature`/`x-request-id` do Mercado Pago com o
segredo de assinatura de webhook (`MP_WEBHOOK_SECRET` em Supabase Secrets), HMAC-SHA256.
Notificações com assinatura inválida são descartadas com `401` sem tocar no banco. Mesmo com
assinatura válida, o handler sempre busca o pagamento por `id` via `GET /v1/payments/{id}` antes de
gravar qualquer status — a notificação em si só é usada como gatilho, nunca como fonte de verdade do
valor/status. Comportamento idêntico independentemente de qual plataforma originou o pagamento.

**Rationale**: Evita que notificações forjadas alterem `payments` e mitiga o caso de payloads de
webhook desatualizados ou incompletos.

## 6. Idempotência de cobrança

**Decision**: `mp-create-payment` envia `X-Idempotency-Key` com o valor do `request_id` da
solicitação (mais um sufixo de tentativa, ex.: `request_id:attempt`, ao gerar um novo código Pix
após expiração). Antes de chamar a API, a função verifica via RPC se já existe um `payments`
`pending`/`approved` para aquele `request_id` e, se houver, devolve o existente em vez de criar
outro.

**Rationale**: Cobre tanto rede instável (retry do app reenviando a mesma requisição) quanto
múltiplos toques do usuário, satisfazendo FR-011/SC-006 sem estado adicional no app.

## 7. Retry e fallback do estorno automático

**Decision**: `mp-refund-payment` tenta a chamada de estorno (`POST /v1/payments/{id}/refunds`) até
3 vezes com backoff curto (2s, 8s, 20s); se as 3 tentativas falharem, o pagamento é marcado
`REFUND_FAILED` em vez de `REFUNDED`; o app mostra "reembolso em andamento" ao cliente e o caso fica
listado para o suporte consultar.

**Rationale**: Atende a decisão do usuário (retry automático + fallback para suporte) com a menor
infraestrutura possível — sem fila externa, reaproveitando o próprio Postgres como registro dos
casos pendentes.

## 8. CPF do pagador

**Decision**: Reaproveitar `AccountSnapshot.profile.cpf` (`String?`, já coletado no cadastro do
cliente, ver `specs/006-auth-vehicle-registration/data-model.md`) como `payer.identification.number`
nas chamadas ao Mercado Pago (Pix exige CPF do pagador). Nenhuma tela nova de coleta de CPF é
necessária.

**Rationale**: Elimina uma etapa de UX e um requisito de dado que o app já possui; consistente com
KISS/YAGNI.

## 9. Ponto de gate do pagamento no fluxo MOBILE_SEQUENTIAL — divergência justificada do Android

**Decision**: No client iOS, o pagamento **não** bloqueia `start_mobile_dispatch` (início da busca);
ele bloqueia `request_mobile_dispatch_candidate` (a ação "Solicitar este guincho" sobre uma proposta
já apresentada). Buscar e folhear candidatos (`OPTION_FOUND`/"Próximo") permanece gratuito e não
aciona nenhum prestador; o pagamento passa a ser exigido exatamente no instante em que o cliente
reserva um prestador específico pelo preço exibido daquela proposta
(`CandidateProposal.displayedPrice`, já implementado e congelado em `price_snapshot` desde a spec
`013`).

**Rationale**: O contrato de `013` (compartilhado com o Android, ver
`specs/013-mobile-provider-dispatch/contracts/mobile-dispatch-rpcs.md` e o próprio `spec.md` da
feature: *"O preço apresentado não inclui negociação, pagamento ou cobrança nesta feature"*) deixa
explícito que o preço do serviço MOBILE_SEQUENTIAL **não existe em nível de catálogo** — cada
provider define seu próprio preço (`spec 016`, FR "o preço do serviço Guincho continua sendo
definido individualmente por cada prestador Móvel"), e só é conhecido pelo cliente quando uma
proposta específica é apresentada (`OPTION_FOUND`). Gatear o pagamento em `start_mobile_dispatch`
(antes de qualquer proposta existir) obrigaria a cobrar por uma **estimativa de catálogo** que pode
não existir e que, mesmo existindo, divergiria do preço real do prestador eventualmente escolhido —
exatamente a ressalva que o próprio Android já registra ("mesma estimativa já exibida hoje, com a
mesma ressalva de que o valor final pode variar"). Gatear em `request_mobile_dispatch_candidate` em
vez disso:
- cobra o valor **exato** e já congelado da proposta aceita, sem qualquer estimativa;
- preserva a experiência gratuita de "folhear" candidatos antes de decidir, já especificada em
  `013` e inalterada por esta feature;
- ainda satisfaz integralmente FR-009/FR-014 ("o despacho do prestador só ocorre após pagamento
  aprovado"), pois é exatamente na chamada de `request_mobile_dispatch_candidate` que um provider
  específico passa a ser notificado (`AWAITING_PROVIDER`/`PENDING`) — o "despacho" de fato.

Este é o mesmo tipo de refinamento já aplicado a specs anteriores deste port (`010`, `014`): a
especificação de negócio (spec.md) é preservada integralmente; apenas o ponto técnico exato de
aplicação, ausente do nível de spec e definido em `plan.md`/`contracts/`, é ajustado para caber no
contrato real e compartilhado do backend, sem introduzir nenhuma tabela, RPC ou Edge Function nova.

**Alternatives considered**:
- Gatear em `start_mobile_dispatch` com um valor de catálogo estimado (réplica literal do desenho
  Android): rejeitado — exigiria inventar um campo de preço de catálogo (`HomeService.minimumPrice`
  equivalente) que não existe no modelo real MOBILE_SEQUENTIAL do backend compartilhado (o preço é
  definido por provider, não por catálogo, conforme `016`), e cobraria por um valor que quase sempre
  divergiria do preço final.
- Gatear em `respond_to_mobile_dispatch` (resposta do provider) em vez de
  `request_mobile_dispatch_candidate` (ação do cliente): rejeitado — nesse ponto o provider já teria
  sido notificado de uma solicitação `PENDING` sem pagamento confirmado, violando FR-009 de forma
  mais grave (o prestador já foi "acionado" antes da cobrança).

## 10. Ponto de gate do pagamento no fluxo PitTec — preço fixo de plataforma

**Decision**: `start_pittec_dispatch` exige pagamento aprovado, assim como no desenho Android
(idêntico — PitTec já inicia oferecendo imediatamente ao provider mais próximo, sem uma etapa
"OPTION_FOUND" intermediária em que o cliente decida por um preço específico, ver
`specs/015-pittec-on-demand/contracts/pittec-rpcs.md`). O valor cobrado é uma **tarifa fixa única de
plataforma** (não uma estimativa por distância): a spec `016` já estabelece que, para PitTec, "o
valor fixo é único e definido pela plataforma, não pelo prestador" — e o snapshot real de despacho
PitTec (`PitTecDispatchSnapshot`, `015`) não expõe nenhuma distância ao cliente antes do aceite
(`approximateDistance` só existe do lado do provider ofertado), então uma fórmula por distância como
a do protótipo mockado (`017`, cliente vê perímetro/faixas de 5km) não é reproduzível com dados reais
disponíveis ao cliente antes de pagar.

**Rationale**: É a única leitura consistente com `016` e com os dados reais que o client iOS tem
disponíveis no momento em que o pagamento precisa ocorrer (antes de `start_pittec_dispatch`, logo
antes de qualquer candidato existir). O valor da tarifa fixa é um parâmetro de produto (constante),
não calculado a partir de coordenadas — evitando qualquer inferência de localização não autorizada
antes do fluxo de descoberta anonimizada de `015`.

**Alternatives considered**:
- Reaproveitar a fórmula do protótipo mockado (`017`, R$ 50 + R$ 10 por faixa de 5km): rejeitado —
  aquele documento é explicitamente um protótipo de UI sem dados reais (`017`'s "Ported from" já
  registra que o Android evoluiu esse mock para dados reais logo em seguida); a fórmula por
  perímetro nunca foi parte do contrato real de despacho PitTec (`015`), que não expõe distância ao
  cliente antes do aceite.
- Calcular a tarifa no servidor a partir da posição aproximada do cliente antes do despacho:
  rejeitado por escopo — exigiria uma nova RPC/coluna fora do que esta feature pretende adicionar
  (KISS/YAGNI); pode ser revisitado numa spec de precificação dinâmica futura, sem impacto no
  contrato de `payments` definido aqui.

## 11. SDK e chaves — nenhuma diferença de política em relação ao Android

**Decision**: A Public Key do Mercado Pago (não sensível) chega ao app via `Config/Secrets.xcconfig`
(gitignored) + Build Setting + `Info.plist`, mesmo padrão de `004`/`010`. O Access Token e o segredo
de webhook nunca chegam ao bundle iOS — ficam exclusivamente em Supabase Secrets, consumidos pelas
Edge Functions.

**Rationale**: Consistente com a constituição iOS (`Segredos de build... nunca hardcoded; chaves
privadas/Access Tokens NUNCA pertencem ao app`) e com o próprio texto da constituição, que já
antecipa nomeadamente o Mercado Pago nesse trecho.
