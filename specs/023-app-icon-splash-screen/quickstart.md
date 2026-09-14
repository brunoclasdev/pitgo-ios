# Quickstart: Ícone do app e tela de splash

## Pré-requisitos

- `pitgo-icon.png` e `pitgo-image1200.png` em `/Users/brunocesar/Pictures/`.
- `sips` (já disponível no macOS) e `swift` (via Xcode Command Line Tools) — nenhuma instalação
  adicional.
- Build local (`xcodebuild -scheme pitgo build` ou Xcode).

## Cenário 1 — Ícone na tela inicial (US1)

1. Instalar o app num device/simulador.
2. Olhar o ícone na tela inicial do iOS: deve mostrar o círculo roxo com a chave inglesa branca
   preenchendo o quadrado inteiro, sem faixas pretas/vazias nas bordas.
3. Abrir a busca do sistema (Spotlight) e digitar "PitGo" — o mesmo ícone deve aparecer.
4. Abrir Ajustes > (rolar até o PitGo na lista de apps) — o mesmo ícone deve aparecer.
5. Se o device suportar o tema de ícone "tintado" (Ajustes > Tela e Brilho > Ícones do App,
   iOS 18+), alternar para tintado e confirmar que o desenho continua reconhecível, sem cortes.

**Resultado esperado**: ícone da marca em todo lugar, sem placeholder, sem faixas, sem distorção
— SC-001/SC-003 do spec.md satisfeitos.

## Cenário 2 — Splash ao abrir o app (US2)

1. Forçar o encerramento do app (remover do app switcher) para garantir um cold start.
2. Tocar no ícone do PitGo.
3. Observar a fração de segundo antes da tela de Boas-vindas/login aparecer: a logo completa
   (círculo + chave inglesa + "PitGo") deve aparecer centralizada, com o roxo do fundo da imagem
   preenchendo o resto da tela sem uma borda perceptível.
4. Repetir em um iPhone pequeno, um iPhone grande e (se disponível) um iPad/simulador de iPad —
   a logo deve permanecer centralizada e proporcional em todos.

**Resultado esperado**: logo inteira, sem cortes, sem esticar, sem atraso perceptível adicional —
SC-002/SC-003/SC-004 do spec.md satisfeitos.

## Cenário 3 — Sem regressão nas imagens de origem

1. Comparar visualmente o ícone e a splash instalados com os arquivos originais em
   `~/Pictures/` — o círculo, a chave inglesa e a palavra "PitGo" devem ser reconhecíveis, sem
   pixelização/borrão perceptível (FR-008).
