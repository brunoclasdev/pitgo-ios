# Validação iOS — spec 033

## Implementado

- Guincho usa retirada em `ACCEPTED` antes da chegada e destino contratado em `IN_PROGRESS`; o contexto ativo é relido ao iniciar e confirmar a abertura.
- PitTec só oferece a ação em `ACCEPTED` antes de `arrivedAt`; atendimento ativo e contexto autenticado do cliente são relidos antes de abrir.
- Waze e Google Maps usam seus esquemas nativos; opções indisponíveis aparecem desabilitadas e uma falha de abertura mantém o usuário no PitGo.
- A abertura envia apenas coordenada de destino e parâmetros constantes da rota. Nenhuma ação de atendimento é invocada pelo componente de navegação.
- Mapas preservam as posições e mensagens textuais de localização indisponível/desatualizada. O relógio do mapa inicial do prestador foi removido; o ícone de localização no status de acompanhamento não representa relógio.

## Pendente

- Validar em aparelho real, com Waze e Google Maps instalados/configurados, os seis cenários de destino e o retorno aos dois fluxos.
- Validar apps ausentes/desativados, destino indisponível e mudança de etapa enquanto o diálogo está aberto.
- Confirmar continuidade do compartilhamento de localização pelo cliente em ambos os perfis de prestador durante troca para app externo.

## Build e diff

- Builds `pitgo`, `pitgo-Homol` e `pitgo-Prod` passaram em `generic/platform=iOS Simulator` (`xcodebuild -quiet`). Restaram avisos preexistentes de `ISO8601DateFormatter` não `Sendable` e avisos do runtime Xcode sobre build number vazio.
- `plutil -lint AppInfo/Info.plist` e `git diff --check` passaram. URLs conferidas: `waze://?ll=lat,long&navigate=yes` e `comgooglemaps://?daddr=lat,long&directionsmode=driving`.
- A validação em simulator compila o adaptador e as telas, mas não confirma a abertura de apps instalados, comportamento do URL handler nem continuidade real do serviço de localização em background.
