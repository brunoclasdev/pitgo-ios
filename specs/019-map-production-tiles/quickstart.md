# Quickstart: Validar o mapa iOS em produção

Guia de validação manual — sem testes automatizados, conforme a governança do projeto.

## Pré-requisitos

- Xcode com o projeto `pitgo.xcodeproj` aberto, target `pitgo`.
- Os quatro valores de produção do mapa (mesmos usados pelo Android — ver
  `local.properties` do projeto Android): `mapStyleUrl`, `mapStyleProviderName`,
  `mapStyleAttribution`, `mapStyleAttributionUrl`.
- `Config/Secrets.xcconfig` deve já existir com `supabaseUrl`/`supabaseKey` (de `004`) — este
  quickstart só adiciona as quatro linhas do mapa.

## Passo 1 — Configurar os valores de produção

1. Abrir `Config/Secrets.xcconfig` (arquivo local, não rastreado).
2. Adicionar/atualizar as quatro linhas do mapa com os valores reais (mesmo formato de
   `Config/Shared.xcconfig`, escapando `//` como `/$()/`):
   ```text
   mapStyleUrl = https:/$()/<mesmo-host-do-android>/...
   mapStyleProviderName = <mesmo-nome-do-android>
   mapStyleAttribution = <mesmo-texto-do-android>
   mapStyleAttributionUrl = https:/$()/<mesmo-link-do-android>
   ```
3. **Atenção de encoding**: digitar `©`/`·` (e outros acentos) diretamente como UTF-8 no editor do
   Xcode — não colar bytes copiados de um terminal/visualizador que possa ter interpretado o
   `local.properties` Android como Latin-1 (ver `research.md` §2). Conferir visualmente que os
   caracteres aparecem corretos no próprio Xcode antes de salvar.

## Passo 2 — Build deve suceder com a configuração real

```sh
xcodebuild -project pitgo.xcodeproj -scheme pitgo -destination 'generic/platform=iOS' build
```

**Esperado**: build sucede; nenhuma falha do Run Script de validação.

## Passo 3 — Confirmar visualmente no app

1. Rodar o app num simulador ou dispositivo.
2. Abrir uma tela com mapa (ex.: mapa de serviço, acompanhamento de atendimento).
3. **Esperado**: o estilo carregado é o de produção (mesmas ruas/cores/rótulos do app Android na
   mesma região) — não o estilo de demonstração do MapLibre.
4. Verificar o controle de atribuição do mapa: nome/link do provedor devem corresponder ao
   configurado, com acentuação/símbolos corretos (sem caracteres corrompidos).
5. Comparar lado a lado com a mesma tela no app Android — o estilo base deve ser visualmente
   equivalente (SC-004).

## Passo 4 — Build deve falhar sem configuração de produção (regressão do gate)

1. Comentar ou remover temporariamente as quatro linhas do mapa em `Config/Secrets.xcconfig` (sem
   apagar as do Supabase).
2. Rodar o mesmo comando de build do Passo 2.
3. **Esperado**: build falha, citando explicitamente qual campo do mapa está ausente/aponta para
   host de demonstração — nunca um build bem-sucedido usando o default de `Config/Shared.xcconfig`
   silenciosamente.
4. Restaurar as quatro linhas antes de continuar trabalhando.

## Passo 5 — Build deve falhar para um host demo explícito

1. Definir temporariamente `mapStyleUrl = https:/$()/demotiles.maplibre.org/style.json` em
   `Config/Secrets.xcconfig`.
2. Rodar o build.
3. **Esperado**: falha citando `mapStyleUrl` e o motivo (host de demonstração conhecido).
4. Restaurar o valor de produção.

## Limpeza

Nenhuma — `Config/Secrets.xcconfig` nunca é commitado (`.gitignore`); os valores reais permanecem
apenas na máquina local/CI.
