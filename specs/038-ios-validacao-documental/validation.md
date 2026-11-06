# Validação

- Compilação Debug para iOS Simulator, assinatura desabilitada: passou (`BUILD SUCCEEDED`).
- `Scripts/Tests/run-platform-parity-regressions.sh`: passou, incluindo pagamento, cancelamento, retomada Pix, tracking e atualização de despacho.
- Nenhum teste novo gerado e nenhuma alteração remota executada.

Validação integrada pendente: criar cliente e prestador, retomar em outro acesso, preencher complementos, negar/permitir câmera, conferir quatro fotos e documentos veiculares, interromper upload e tentar novamente, submeter, solicitar correção/aprovar pelo dashboard, manter acesso CLIENT durante análise PROVIDER, confirmar conta legada e bloqueio operacional independente.

Recuperação: permitir `com.trustarx.pitgo.auth://auth/recovery` no Auth de cada ambiente; executar envio, retorno, alteração, link inválido/expirado/reutilizado e reinício durante recuperação. A allowlist remota não foi consultada nem alterada.

Dependência de backend encontrada na referência Android: `registration_pending_items`/submissão exigem ofertas para PROVIDER, inclusive quando a modalidade comercial é STORE. O fluxo de loja existente no iOS usa `create_store_registration`, enquanto o spec Android novo adapta `create_provider_registration`. Cadastro documental de lojas requer compatibilização e validação desses contratos no backend compartilhado. Não houve alteração dessa regra pelo cliente.
