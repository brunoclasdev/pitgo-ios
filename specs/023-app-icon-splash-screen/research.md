# Research: Ícone do app e tela de splash

## 1. Formato do App Icon já esperado pelo projeto

**Decision**: preencher os 3 slots já declarados em `pitgo/Assets.xcassets/AppIcon.appiconset/
Contents.json` (idiom `universal`, 1024×1024, aparências nenhuma/`dark`/`tinted`) com a mesma
imagem recortada.

**Rationale**: o catálogo já está no formato "ícone único" moderno (introduzido para visionOS,
retroaplicado a iOS 17+) — um só arquivo 1024×1024 por aparência, sem o antigo conjunto de
dezenas de tamanhos (`20x20`, `29x29`, etc., que o Xcode gera automaticamente a partir do
universal). Só falta preencher os arquivos; nenhuma mudança de `Contents.json` é necessária além
de adicionar as três chaves `filename`.

**Alternatives considered**: gerar manualmente todos os tamanhos legados — desnecessário e
incompatível com o `Contents.json` já existente no projeto.

## 2. Recorte do ícone para quadrado

**Decision**: `sips -c 1024 1024 pitgo-icon.png --out <saída>` — `sips --cropToHeightWidth` recorta
a partir do centro. Como a imagem de origem (1536×1024) já tem a altura exata (1024) e só a
largura excede, o recorte remove exatamente 256px de cada lado, sem tocar verticalmente em nada.
Testado nesta sessão: produz 1024×1024 preservando o círculo/chave inglesa centralizados
(confirmado por inspeção visual do resultado).

**Rationale**: ferramenta já disponível no macOS, sem instalar nada; comportamento de recorte
central é exatamente o que a clarificação do spec.md pediu.

**Alternatives considered**: `ImageMagick`/`PIL` — nenhum dos dois está instalado nesta máquina
(verificado); instalar uma dependência externa só para um recorte que `sips` já resolve violaria
a constituição (simplicidade/YAGNI).

## 3. Canal alfa do ícone

**Decision**: achatar o alfa com um script Swift avulso e descartável usando **CoreGraphics/
ImageIO puro** (`CGContext` criado com `CGImageAlphaInfo.noneSkipLast`, a imagem de origem
desenhada dentro dele, exportada via `CGImageDestination`) — roda uma vez durante a implementação
desta feature (`swift <script>.swift entrada.png saida.png`), não faz parte do target do app nem
é commitado como código de produção.

**Rationale**: a App Store rejeita ícones com canal alfa; a imagem de origem tem
(`sips -g hasAlpha` confirma `yes`). Duas alternativas testadas nesta sessão falharam antes de
chegar nesta: `sips -s format bmp` seguido de volta pra PNG **não** removeu o canal alfa (o PNG
resultante continuou com `color type 6`/RGBA no `IHDR`, verificado byte a byte); e um primeiro
script usando `AppKit`/`NSGraphicsContext(bitmapImageRep:)` **produziu um PNG inteiramente preto**
(o `.current`/`.draw(in:)` do AppKit não funciona de forma confiável fora de um app com run
loop/window server, num script CLI avulso) — descoberto ao inspecionar visualmente o resultado, não
só o `hasAlpha`. A versão final (CoreGraphics/ImageIO puro, sem AppKit) foi testada e confirmada
visualmente: círculo/chave inglesa preservados, `hasAlpha: no`, `color type 2`/RGB no `IHDR`.

**Alternatives considered**: `sips -s format jpeg` seguido de volta pra PNG — remove o alfa mas
introduz artefatos de compressão com perdas visíveis no degradê radial do brilho roxo; rejeitado
por qualidade. Instalar ImageMagick/PIL só para isso — mesma objeção do item 2. `AppKit`/
`NSGraphicsContext` — testado e descartado por produzir saída incorreta (ver acima).

## 4. Logo do splash como `UILaunchScreen`

**Decision**: usar as chaves modernas de `UILaunchScreen` no `Info.plist` (já presente, hoje
vazio: `<dict/>`) — `UIImageName` apontando pra um novo `ImageSet` (`LaunchImage`) com a logo, e
`UIColorName` apontando pra um novo `ColorSet` (`LaunchBackground`) com o roxo já presente na
própria imagem `pitgo-image1200.png`. Esse mecanismo (suportado desde Xcode 14, sem storyboard)
centraliza a imagem sem esticar/achatar e preenche o resto da tela com a cor indicada.

**Rationale**: é exatamente o comportamento pedido (FR-006/FR-007) sem escrever nenhuma View ou
código Swift novo — a splash é renderizada pelo próprio SpringBoard antes do processo do app
iniciar (SC-004: nenhum atraso adicional, porque não há código de app envolvido nessa etapa).

**Alternatives considered**: uma `LaunchScreen.storyboard` — mecanismo legado, mais verboso pra
alcançar o mesmo resultado; o projeto já usa a abordagem por `Info.plist`, então introduzir um
storyboard só pra isso quebraria a consistência sem necessidade. Uma `SwiftUI View` própria como
"splash" — não é o que `UILaunchScreen` faz (essa tela nativa aparece *antes* de qualquer View
SwiftUI existir) e adicionaria complexidade/código para um efeito que o próprio sistema já resolve.

## 5. Escalas do `ImageSet` do splash

**Decision**: `pitgo-image1200.png` (1254×1254, quadrada) fornece a escala `@3x` sem nenhum
redimensionamento (evita upscaling, FR-008); `@2x` e `@1x` são versões reduzidas
(`sips -z 836 836` e `sips -z 418 418`) da mesma imagem, todas representando o mesmo tamanho em
pontos (418×418pt) em qualquer densidade de tela.

**Rationale**: um único arquivo usado como "escala única" ficaria grande demais em pontos em
telas de densidade menor (1254pt de lado é maior que a largura de qualquer iPhone); fornecer as
três escalas padrão mantém o tamanho em pontos consistente e a imagem sempre nítida, sem depender
de upscaling em nenhuma densidade.

**Alternatives considered**: usar só `@1x` (1254px seria a versão "1x", exibida como 1254pt) —
ocuparia a tela inteira e além em iPhones pequenos, não parece "bem alinhado" nem intencional.
