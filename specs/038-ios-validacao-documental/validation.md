# Validação

- Compilação Debug para iOS Simulator, assinatura desabilitada: passou (`BUILD SUCCEEDED`).
- `Scripts/Tests/run-platform-parity-regressions.sh`: passou, incluindo pagamento, cancelamento, retomada Pix, tracking e atualização de despacho.
- Na validação inicial, nenhum teste novo foi gerado e nenhuma alteração remota foi executada.

Validação integrada pendente: criar cliente e prestador, retomar em outro acesso, preencher complementos, negar/permitir câmera, conferir quatro fotos e documentos veiculares, interromper upload e tentar novamente, submeter, solicitar correção/aprovar pelo dashboard, manter acesso CLIENT durante análise PROVIDER, confirmar conta legada e bloqueio operacional independente.

Recuperação: permitir `com.trustarx.pitgo.auth://auth/recovery` no Auth de cada ambiente; executar envio, retorno, alteração, link inválido/expirado/reutilizado e reinício durante recuperação. A allowlist remota não foi consultada nem alterada.

Dependência de backend encontrada na referência Android: `registration_pending_items`/submissão exigem ofertas para PROVIDER, inclusive quando a modalidade comercial é STORE. O fluxo de loja existente no iOS usa `create_store_registration`, enquanto o spec Android novo adapta `create_provider_registration`. Cadastro documental de lojas requer compatibilização e validação desses contratos no backend compartilhado. Não houve alteração dessa regra pelo cliente.

## Correção de telefone internacional — 06/11/2026

- Confirmado no servidor: o trigger de Auth rejeitava o DDI enviado pelo cadastro iOS.
- Migration `20261105121000_registration_international_phone.sql` aplicada e registrada no backend compartilhado de Homol/Prod, preservando telefones brasileiros legados.
- `Scripts/Tests/RegistrationPhoneRegression.sql`: passou antes da aplicação, em transação revertida, e novamente após a aplicação. Exercita o trigger real com clientes CPF/CNPJ, prestador CNPJ, telefones BR/EUA/Portugal, formato brasileiro legado e rejeição de telefone inválido.
- Todas as contas sintéticas dos testes são revertidas; nenhum e-mail é enviado. Não exige atualização do aplicativo instalado.
