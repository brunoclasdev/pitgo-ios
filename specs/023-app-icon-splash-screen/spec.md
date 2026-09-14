# Feature Specification: Ícone do app e tela de splash

**Feature Branch**: `023-app-icon-splash-screen`

**Created**: 2026-09-14

**Status**: Draft

**Input**: User description: "Implementação das imagens: caminho das imagens: /Users/brunocesar/Pictures
- Tela de spalsh usara a imagem pitgo-image1200.png
- O icone do aplicativo usara a imagem: pitgo-icon.png
- Antes de usar, redimensione para os padroes exigidos, não permite quebra na imagem, sempre deixe bem alinhado e mostrando as imagens inteiras"

## Clarifications

### Session 2026-09-14

- Q: O ícone (`pitgo-icon.png`) não é quadrado (1536×1024) mas o slot do App Icon exige quadrado perfeito. O conteúdo (círculo roxo + chave inglesa) já está centralizado, com fundo preto sobrando só nas laterais. Como resolver isso? → A: Cortar as bordas pretas sobrando — o círculo/chave inglesa continuam 100% visíveis, sem faixas, ícone preenche o quadrado de ponta a ponta.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Reconhecer o app pelo ícone (Priority: P1)

Uma pessoa instala ou procura o PitGo na tela inicial do iPhone/iPad e reconhece o app pelo ícone oficial da marca (o círculo roxo com a chave inglesa) — não pelo ícone genérico/placeholder do Xcode que aparece hoje.

**Why this priority**: É a primeira impressão do app e a forma como ele é encontrado entre outros apps; hoje o app não tem nenhum ícone próprio configurado.

**Independent Test**: Instalar o app num device/simulador e conferir que o ícone exibido na tela inicial, na busca do sistema e nas Configurações é o ícone oficial da marca, cheio (sem barras vazias), sem distorção e sem cortar o círculo ou a chave inglesa.

**Acceptance Scenarios**:

1. **Given** o app recém-instalado, **When** a pessoa olha a tela inicial do iOS, **Then** o ícone mostra o círculo roxo com a chave inglesa branca preenchendo o quadrado do ícone de ponta a ponta, sem faixas de cor vazias e sem esticar/achatar o desenho.
2. **Given** o dispositivo com o ícone tintado (modo escuro ou tema de ícone "tintado" do iOS), **When** a pessoa alterna a aparência, **Then** o ícone continua reconhecível e sem cortes no desenho principal.

---

### User Story 2 - Ver a marca ao abrir o app (Priority: P2)

Uma pessoa abre o PitGo e, no instante inicial antes da tela de login/home carregar, vê a logo completa do PitGo (círculo com chave inglesa + "PitGo") centralizada e alinhada, em vez de uma tela em branco.

**Why this priority**: Reforça a identidade da marca no momento de abertura; tem prioridade menor que o ícone porque a tela de splash é vista por menos tempo e o app já funciona sem ela.

**Independent Test**: Abrir o app do zero (cold start) em diferentes tamanhos de tela (iPhone pequeno, iPhone grande, iPad) e confirmar que a logo aparece inteira, centralizada, sem cortes e sem distorção, com transição suave para a tela seguinte.

**Acceptance Scenarios**:

1. **Given** o app fechado, **When** a pessoa toca no ícone para abrir, **Then** a tela de abertura mostra a logo completa do PitGo (círculo + chave inglesa + palavra "PitGo") centralizada, sem cortar nenhuma parte da imagem e sem esticar/achatar o desenho.
2. **Given** dispositivos com proporções de tela diferentes (iPhone e iPad, por exemplo), **When** a tela de abertura aparece, **Then** a logo permanece centralizada e com a mesma proporção original em qualquer tamanho de tela, com o espaço ao redor preenchido de forma que pareça parte do mesmo desenho (sem uma borda ou faixa visualmente destacada).

---

### Edge Cases

- O ícone de origem não é quadrado (1536×1024) — resolvido pela clarificação acima: recorte simétrico do fundo vazio nas laterais, mantendo o desenho principal inteiro.
- A imagem de splash já é quadrada (1254×1254); em telas retangulares (todo iPhone/iPad), sobra espaço acima/abaixo ou nas laterais ao redor da logo — esse espaço deve ser preenchido com a mesma cor de fundo já presente na própria imagem, para não criar uma borda perceptível.
- Nenhuma das duas imagens deve aparecer pixelizada/borrada por upscaling além da resolução de origem.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O aplicativo MUST usar `pitgo-icon.png` como base do ícone oficial do app, exibido na tela inicial do sistema, na busca e nas Configurações, substituindo o ícone padrão/placeholder atual.
- **FR-002**: O ícone MUST preencher todo o espaço quadrado exigido pelo sistema, sem faixas de cor vazias nas bordas e sem distorcer (esticar/achatar) o desenho original.
- **FR-003**: O recorte necessário para tornar `pitgo-icon.png` quadrado MUST remover somente a área de fundo vazio nas laterais, preservando o círculo roxo e a chave inglesa completos e centralizados.
- **FR-004**: O aplicativo MUST fornecer as variações de aparência exigidas pelo sistema (padrão, escura e "tintada") a partir da mesma imagem de origem, mantendo o mesmo enquadramento em todas.
- **FR-005**: O aplicativo MUST usar `pitgo-image1200.png` como a logo exibida na tela de abertura (splash/launch), mostrada assim que o app é aberto e antes de qualquer outra tela carregar.
- **FR-006**: A logo na tela de abertura MUST aparecer completa (círculo, chave inglesa e a palavra "PitGo"), centralizada, sem cortar nenhuma parte e sem esticar/achatar o desenho, em qualquer tamanho de tela suportado (iPhone e iPad).
- **FR-007**: O espaço ao redor da logo na tela de abertura (quando a proporção da tela não for igual à da imagem) MUST ser preenchido com a mesma cor de fundo já presente na imagem de origem, para que a transição pareça contínua, sem uma borda perceptível.
- **FR-008**: Nenhuma das duas imagens MUST ser ampliada além da sua resolução original a ponto de ficar visivelmente pixelizada/borrada.

### Key Entities *(include if feature involves data)*

- **Ícone do app**: arquivo de imagem único (derivado de `pitgo-icon.png`) que representa o app em todo o sistema operacional (tela inicial, busca, Configurações, App Store futuramente).
- **Imagem da tela de abertura**: arquivo de imagem único (derivado de `pitgo-image1200.png`) mostrado como primeira tela visível ao abrir o app.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% das telas do sistema que exibem o ícone do app (tela inicial, busca, Configurações) mostram o ícone oficial da marca, não o placeholder.
- **SC-002**: A tela de abertura exibe a logo completa (sem cortes) em 100% dos tamanhos de tela suportados pelo app.
- **SC-003**: Nenhuma parte do círculo, da chave inglesa ou da palavra "PitGo" fica cortada, esticada ou achatada em nenhuma das duas imagens, em nenhum tamanho de tela testado.
- **SC-004**: A troca da tela de abertura para a próxima tela do app acontece sem atraso perceptível adicional em relação ao tempo de abertura atual do app.

## Assumptions

- "Tela de splash" se refere à tela nativa de abertura do iOS (`UILaunchScreen`), exibida por uma fração de segundo entre o toque no ícone e a primeira tela real do app — não à tela de "Boas-vindas" com texto/botões que já existe hoje no app (essa permanece inalterada).
- A cor de fundo usada para preencher o espaço ao redor da logo na tela de abertura é o roxo já presente na própria imagem `pitgo-image1200.png` (sem introduzir uma cor nova não presente no material fornecido).
- As variações "escura" e "tintada" do ícone (exigidas pelo formato atual do catálogo de ícones do app) reaproveitam a mesma imagem recortada — nenhuma arte alternativa foi fornecida para essas variações.
- Nenhuma das duas imagens tem texto ou elementos que dependam de tradução/localização — o mesmo arquivo serve para todos os idiomas suportados pelo app.
