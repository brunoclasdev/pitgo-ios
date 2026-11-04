# Validação iOS — 2026-11-03

Base funcional comparada: Android `2951ea6`, specs 035/036; iOS `04226d1`.

## Regressões automatizadas

Comando reproduzível:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/Tests/run-guincho-regressions.sh
```

Três regressões aprovadas:

1. Orçamento: datas ISO8601 com/sem frações, Decimal numérico/textual, rejeição de dados malformados e preservação de veículo/porte/versão de preço.
2. Reserva: criação e respostas idempotentes, ações de pagamento/acompanhamento, cancelamento e leitura fora da thread principal.
3. Retomada: preservação de veículo/retirada/destino; contexto incompleto ou geração inválida não abre busca; NONE/ACTIVE_DISPATCH não são tratados como recusa.

## Build e abertura

- `xcodebuild -project pitgo.xcodeproj -scheme pitgo-Homol -sdk iphonesimulator -configuration Debug-Homol CODE_SIGNING_ALLOWED=NO build`: aprovado para arm64 e x86_64, deployment target iOS 16.
- Instalação e abertura no simulador iPhone 17 Pro / iOS 26.5 aprovadas. Tela inicial renderizada e inspecionada; sem sessão autenticada.
- `git diff --check`: aprovado.
- Há avisos preexistentes de Sendable/ISO8601DateFormatter nos repositórios de pagamento e verificação de endereço; nenhum erro de compilação.

## Limites

Os testes não executam RPCs, alterações de preço, reembolso ou permissões em banco remoto. A implementação depende das migrations compartilhadas do Android descritas no plano. Não foi executada uma jornada com cliente/prestador autenticados nem validada a matriz comercial em Supabase.

A validação visual das novas telas autenticadas, acessibilidade, teclado e aparelho físico permanece pendente. Compilação e abertura do app não comprovam essas jornadas.

## Correção do Pix após aceite — 2026-11-03

A migration Android `20261103102000` recriou `reserve_order_payment` com comparação e cobrança de `customer_total_amount`, removendo o suporte a `payment_amount` instalado anteriormente. A cobrança Homol de R$ 1–2 era rejeitada como `PRICE_CHANGED` mesmo com o pedido aceito e dentro do prazo. O erro foi reproduzido em uma transação integralmente revertida.

A migration `20261104000000_restore_guincho_size_homol_amount.sql` restaura `coalesce(payment_amount,customer_total_amount)` na validação, reaproveitamento e criação da reserva. Mantém o orçamento comercial e os guards de posse, versão, preço por porte, status e prazo. Após aceite, o prazo válido para pagamento é o do atendimento; o prazo anterior da cotação de descoberta não deve encurtá-lo.

A correção foi aplicada ao backend compartilhado e a mesma migration foi adicionada aos repositórios iOS e Android. Nenhuma reinstalação do app é necessária.

Regressões SQL (`Scripts/Tests/GuinchoHomolPaymentRegression.sql`), sem chamar Edge Function/Mercado Pago e com ROLLBACK:

- Prazo realmente expirado continua rejeitado.
- Versão incorreta do orçamento continua rejeitada.
- Atendimento aceito respeita seu próprio prazo mesmo depois do vencimento da cotação inicial; Prod preserva o valor comercial.
- Reserva Pix Homol usa R$ 1,23 sem alterar o orçamento comercial.
- Retry preserva ID e valor da primeira tentativa, sem duplicar a reserva.

Os testes validam a reserva no banco. A geração e o pagamento real do QR Code continuam dependendo do reteste pelo cliente.
