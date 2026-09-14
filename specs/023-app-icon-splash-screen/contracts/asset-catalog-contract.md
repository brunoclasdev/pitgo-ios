# Contract: Assets e configuração do sistema

Nenhuma RPC/API — o "contrato" aqui é com o próprio iOS: os arquivos e chaves exatos que o sistema
lê para exibir ícone e splash. Referência para a implementação, sem ambiguidade de formato.

## `AppIcon.appiconset/Contents.json` (já existe — só ganha `filename`)

```json
{
  "images" : [
    { "idiom" : "universal", "platform" : "ios", "size" : "1024x1024",
      "filename" : "AppIcon-1024.png" },
    { "appearances" : [{ "appearance" : "luminosity", "value" : "dark" }],
      "idiom" : "universal", "platform" : "ios", "size" : "1024x1024",
      "filename" : "AppIcon-1024-dark.png" },
    { "appearances" : [{ "appearance" : "luminosity", "value" : "tinted" }],
      "idiom" : "universal", "platform" : "ios", "size" : "1024x1024",
      "filename" : "AppIcon-1024-tinted.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

## `LaunchImage.imageset/Contents.json` (novo)

```json
{
  "images" : [
    { "idiom" : "universal", "filename" : "LaunchImage@1x.png", "scale" : "1x" },
    { "idiom" : "universal", "filename" : "LaunchImage@2x.png", "scale" : "2x" },
    { "idiom" : "universal", "filename" : "LaunchImage@3x.png", "scale" : "3x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

## `LaunchBackground.colorset/Contents.json` (novo)

```json
{
  "colors" : [
    { "idiom" : "universal",
      "color" : {
        "color-space" : "srgb",
        "components" : { "red" : "0.482", "green" : "0.165", "blue" : "0.910", "alpha" : "1.000" }
      } }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

Componentes RGB amostrados do fundo sólido de `pitgo-image1200.png` (roxo da marca) — o valor
exato é confirmado por amostragem de pixel durante a implementação, não por leitura visual.

## `AppInfo/Info.plist` — `UILaunchScreen`

Antes (atual, vazio):

```xml
<key>UILaunchScreen</key>
<dict/>
```

Depois:

```xml
<key>UILaunchScreen</key>
<dict>
    <key>UIImageName</key>
    <string>LaunchImage</string>
    <key>UIColorName</key>
    <string>LaunchBackground</string>
    <key>UIImageRespectsSafeAreaInsets</key>
    <false/>
</dict>
```

## Estados fora deste contrato (inalterados)

- `WelcomeView` (tela de "Boas-vindas" com texto/botões) — inalterada, ver Assumption do spec.md.
- Qualquer outro `ImageSet`/`ColorSet` já existente em `Assets.xcassets` — inalterado.
