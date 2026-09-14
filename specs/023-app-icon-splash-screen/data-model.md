# Data Model: Ícone do app e tela de splash

Nenhum dado de domínio, tabela ou modelo Swift — esta feature só produz/organiza arquivos de
imagem dentro do bundle do app. As "entidades" abaixo são artefatos de build, documentados pelo
caminho exato onde cada um vive.

## Ícone do app

| Arquivo | Origem | Dimensão | Canal alfa | Destino |
|---|---|---|---|---|
| `AppIcon-1024.png` | `pitgo-icon.png` recortado (`sips -c 1024 1024`) + achatado (script CoreGraphics) | 1024×1024 | Não | `Assets.xcassets/AppIcon.appiconset/`, aparência padrão |
| `AppIcon-1024-dark.png` | mesmo arquivo que o padrão (nenhuma arte alternativa fornecida — Assumption do spec.md) | 1024×1024 | Não | `Assets.xcassets/AppIcon.appiconset/`, aparência `dark` |
| `AppIcon-1024-tinted.png` | mesmo arquivo que o padrão | 1024×1024 | Não | `Assets.xcassets/AppIcon.appiconset/`, aparência `tinted` |

`Contents.json` do `AppIcon.appiconset` (já existente) ganha a chave `filename` em cada uma das 3
entradas já declaradas — nenhuma outra mudança de estrutura.

## Logo do splash

| Arquivo | Origem | Dimensão (pixels) | Escala | Destino |
|---|---|---|---|---|
| `LaunchImage.png` | `pitgo-image1200.png`, sem redimensionar (evita upscaling) | 1254×1254 | `@3x` | `Assets.xcassets/LaunchImage.imageset/` |
| `LaunchImage@2x.png` | `pitgo-image1200.png` reduzida (`sips -z 836 836`) | 836×836 | `@2x` | `Assets.xcassets/LaunchImage.imageset/` |
| `LaunchImage@1x.png` | `pitgo-image1200.png` reduzida (`sips -z 418 418`) | 418×418 | `@1x` | `Assets.xcassets/LaunchImage.imageset/` |

Todas as três escalas representam o mesmo tamanho em pontos (418×418pt), só variando a densidade
de pixels — nenhuma delas ultrapassa a resolução da imagem de origem (FR-008).

## Cor de fundo do splash

| Recurso | Valor | Destino |
|---|---|---|
| `LaunchBackground` (Color Set) | Roxo sólido amostrado do fundo de `pitgo-image1200.png` | `Assets.xcassets/LaunchBackground.colorset/` |

## Configuração (`AppInfo/Info.plist`)

| Chave | Valor novo |
|---|---|
| `UILaunchScreen.UIImageName` | `LaunchImage` |
| `UILaunchScreen.UIColorName` | `LaunchBackground` |
| `UILaunchScreen.UIImageRespectsSafeAreaInsets` | `false` (a logo deve ficar centralizada na tela inteira, não só na área segura — mesmo comportamento de um splash tradicional) |
