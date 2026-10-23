# Validation: 026-service-catalog-map-card (iOS)

## Build

- `xcodebuild -scheme pitgo -destination 'generic/platform=iOS Simulator' -configuration Debug build`
  → `** BUILD SUCCEEDED **` (2026-10-22).
- `xcodebuild -scheme pitgo -destination 'id=6f84571fbaf2eebf08b385f887e84eab0c3fddb3' -configuration
  Debug -allowProvisioningUpdates build` (iPhone X, iOS 16.7.11, device físico) →
  `** BUILD SUCCEEDED **` (2026-10-22). Assinado com `Apple Development: brunoclas@gmail.com
  (8AY7H3F6QD)` / `iOS Team Provisioning Profile: com.trustarx.pitgo`.
- Instalado via `pymobiledevice3 apps install` e lançado via `pymobiledevice3 developer dvt launch`
  no device físico — app abriu sem crash, renderizou a Home do PitTec (modalidade do prestador já
  logado) e o mapa MapLibre normalmente.

## Funcional (manual)

- T007 (US1 — cadastro Fixo com categoria única/confirmação de troca) e T011 (US3 — mapa PitTec
  compacto/pan-zoom preservado) ficaram para validação manual do usuário no device físico — a conta
  logada na sessão de teste já era um prestador PitTec existente, sem acesso direto ao fluxo de
  cadastro Fixo nem ao lado cliente do acompanhamento PitTec a partir dela. Sem ferramenta de
  automação de toque instalada (WebDriverAgent não configurado) para dirigir a UI de forma
  autônoma.
- Pendente: resultado do usuário para os passos descritos na conversa (troca de categoria com/sem
  confirmação, resumo compacto/expandido, preservação de pan/zoom).
