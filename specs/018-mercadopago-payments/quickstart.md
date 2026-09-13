# Quickstart: validar o pagamento (Pix e cartão) — iOS

## Pré-requisitos

1. Conta de desenvolvedor no Mercado Pago com uma aplicação criada; anote **Public Key** e
   **Access Token** de **teste** (sandbox), e crie dois usuários de teste (comprador e vendedor) no
   painel de integrações.
2. Segredos configurados no projeto Supabase compartilhado (ambiente de teste) — só precisa ser
   feito uma vez, reaproveitado por Android e iOS:
   ```sh
   supabase secrets set MP_ACCESS_TOKEN=TEST-xxxxx
   supabase secrets set MP_WEBHOOK_SECRET=xxxxx
   ```
3. Migração e Edge Functions publicadas (uma única vez, no mesmo projeto Supabase):
   ```sh
   supabase db push
   supabase functions deploy mp-create-payment mp-save-card mp-remove-card mp-webhook mp-refund-payment
   ```
4. `notification_url` do webhook configurada no painel do Mercado Pago apontando para a Edge
   Function `mp-webhook` publicada (URL pública do projeto Supabase — não precisa de túnel/ngrok).
5. Xcode estável mais recente, SDK iOS 17+; `MERCADO_PAGO_PUBLIC_KEY` de teste em
   `Config/Secrets.xcconfig` (gitignored, nunca o Access Token); dispositivo/simulador logado com
   uma conta cliente de teste do PitGo.
6. Cartões de teste do Mercado Pago (documentados no painel de desenvolvedores) para os cenários de
   aprovação e recusa.

## Build

```bash
xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'platform=iOS Simulator,name=iPhone 16' clean build
```

Esperado: build sucede com `mercadopago/sdk-ios` resolvido via Swift Package Manager.

## Cenário 1 — Pagar via Pix (US1)

1. Como cliente de teste, solicite um serviço MOBILE_SEQUENTIAL até "Solicitar este guincho" sobre
   uma proposta (`OPTION_FOUND`), ou toque "Chamar PitTec" — em ambos os casos, confirme que o app
   abre a etapa de pagamento antes de qualquer chamada de despacho, e escolha Pix.
2. Confirme que aparece um QR/código copia-e-cola sem exigir cadastro de cartão (FR-001).
3. No painel de sandbox do Mercado Pago, simule a aprovação do pagamento Pix gerado.
4. Confirme que o app recebe a confirmação (via Realtime ou fallback por RPC) e só então chama
   `request_mobile_dispatch_candidate`/`start_pittec_dispatch`, avançando para o despacho do
   prestador (FR-009, SC-001 — até 2 minutos do início ao ver a confirmação).
5. Repita gerando um Pix e deixando expirar (ou simulando expiração), e confirme a mensagem de
   prazo expirado com opção de gerar novo código (US1 cenário 3).

## Cenário 2 — Cadastrar cartão (US2)

1. Acesse Perfil → Formas de pagamento (área dedicada, FR-019) e cadastre um cartão de teste válido
   usando o formulário CoreMethods do SDK do Mercado Pago.
2. Confirme que a lista mostra só bandeira e últimos 4 dígitos (FR-006/SC-003).
3. Tente cadastrar um cartão de teste de recusa e confirme a mensagem compreensível de erro (US2
   cenário 2).
4. Sem cadastrar nenhum cartão, confirme que todo o app continua funcional e que Pix continua
   disponível (US2 cenário 3, SC-002).
5. Remova um cartão cadastrado e confirme que ele some da lista (FR-007).

## Cenário 3 — Pagar com cartão salvo (US3)

1. Com um cartão já cadastrado, chegue à etapa de pagamento (via "Solicitar este guincho" ou
   "Chamar PitTec") e escolha o cartão salvo.
2. Confirme aprovação e despacho subsequente, igual ao fluxo Pix.
3. Repita com um cartão de teste de recusa e confirme a mensagem de recusa com opção de tentar outro
   cartão ou Pix (US3 cenário 3).
4. Sem nenhum cartão salvo, confirme que a etapa de pagamento só oferece Pix, sem opção de cadastro
   inline (US3 cenário 4).

## Cenário 4 — Reembolso automático (US4)

1. Pague uma solicitação (MOBILE_SEQUENTIAL ou PitTec) e cancele antes da conclusão do atendimento;
   confirme estorno automático total (FR-015, SC-007).
2. Na chamada PitTec, pague e configure todos os PitTecs de teste para recusar; confirme que a busca
   termina em `NO_PROVIDER` e o valor é estornado automaticamente (FR-017).
3. Confirme que, após o prestador marcar o atendimento como concluído, um cancelamento posterior não
   aciona o estorno automático desta feature (FR-016).
4. (Opcional, exige simular falha na API de estorno) Force uma falha nas 3 tentativas de
   `mp-refund-payment` e confirme que o pagamento fica `REFUND_FAILED` com aviso ao cliente de que o
   reembolso está em andamento (FR-018).

## Cenário 5 — Escopo e ponto de gate (FR-014, research.md §9-10)

1. No fluxo MOBILE_SEQUENTIAL, confirme que buscar e tocar "Próximo" entre candidatos continua
   gratuito e não abre a etapa de pagamento — a etapa de pagamento só aparece ao tocar "Solicitar
   este guincho" sobre uma proposta específica, cobrando exatamente o preço exibido daquela
   proposta.
2. No fluxo PitTec, confirme que o pagamento é cobrado antes de qualquer candidato existir, usando a
   tarifa fixa de plataforma (não uma estimativa por distância).
3. Repita o Cenário 1 (Pix) e o Cenário 3 (cartão salvo) partindo da chamada PitTec sob demanda em
   vez do fluxo MOBILE_SEQUENTIAL, confirmando que o despacho PitTec também fica bloqueado até o
   pagamento aprovado (SC-008).

## Verificações técnicas complementares

- `supabase db lint` sem erros na migração compartilhada (se ainda não aplicada por outra
  plataforma).
- Build iOS (`xcodebuild ... clean build`) sem novos avisos introduzidos por esta feature.
- Conferir manualmente que nenhum log do app (`Logger` do `os`) ou da Edge Function imprime PAN,
  CVV ou Access Token.
- Conferir que uma segunda tentativa de cobrança para o mesmo `request_id` (ex.: reenviar a mesma
  requisição) não gera um segundo pagamento aprovado (FR-011/SC-006).
