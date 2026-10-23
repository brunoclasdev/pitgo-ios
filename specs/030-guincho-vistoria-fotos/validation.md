# Validação iOS — spec 030

## Builds

- Dev, iOS Simulator: aprovado em 22/10/2026 usando `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet -scheme pitgo -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/pitgo-derived build`.
- Homol (`pitgo-Homol`) e Prod (`pitgo-Prod`), iOS Simulator: **BUILD SUCCEEDED**.
- `git diff --check`: aprovado.
- Avisos do build: os já existentes de `ISO8601DateFormatter` não ser `Sendable` e do número de build de dispositivo do Xcode. Não apareceram erros Swift.

## Não executado nesta sessão

- Câmera em aparelho físico, permissões negadas/reconcedidas e interrupção do app durante upload.
- Fluxo integrado com duas contas (Cheguei → fotos → correção → aprovação → Iniciar transporte → conclusão bilateral).
- Recuperação real do manifesto/arquivos após encerramento forçado e autorização RLS do bucket privado.
- Histórico em atendimentos antigos, cancelados e com múltiplas versões.

Os cenários manuais permanecem pendentes; o build confirma apenas a compilação do cliente iOS.
