# Validação iOS — Spec 035

## Feito

- `xcodebuild` para os esquemas `pitgo`, `pitgo-Homol` e `pitgo-Prod`, destino `generic/platform=iOS Simulator`, `CODE_SIGNING_ALLOWED=NO` — os três passaram após as últimas alterações.
- `git diff --check` — passou.
- `plutil -lint AppInfo/Info.plist` — passou.
- O catálogo usa as RPCs de leitura/escrita da spec Android e o bucket privado `store-product-images`; identidade da loja é derivada no servidor e o cliente não envia owner ID.
- O formulário valida placa Mercosul, marca, modelo e cor; tarifa ausente não recebe valor default no app.

## Pendente

- Fluxo ponta a ponta requer as migrations 035 presentes no ambiente e contas de teste separadas de loja/cliente; não foi feita alteração remota de backend nem instalação em device nesta etapa.
- A inspeção visual em telas compactas, fonte ampliada, rotação suportada e teclado aberto continua pendente.
