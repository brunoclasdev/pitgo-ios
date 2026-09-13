# Quickstart Validation: Layouts iniciais do PitGo (iOS)

## Prerequisites

- Xcode estável mais recente, SDK iOS 17+ instalado.
- Simulador ou dispositivo iOS 17+ para validação manual.
- Implementação concluída conforme [plan.md](plan.md), [data-model.md](data-model.md) e
  [initial-ui-navigation.md](contracts/initial-ui-navigation.md).

## Build and static validation

```bash
xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'platform=iOS Simulator,name=iPhone 16' clean build
```

Resultado esperado: `** BUILD SUCCEEDED **`, sem warnings bloqueantes, nenhum arquivo de teste
novo.

## Install and launch

```bash
xcrun simctl boot "iPhone 16" 2>/dev/null
xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath build install
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/pitgo.app
xcrun simctl launch booted com.trustarx.pitgo
open -a Simulator
```

## Manual scenarios

### 1. Welcome content and fixed brand treatment

1. Abra o aplicativo em modo claro.
2. Confirme que Welcome é o primeiro destino.
3. Confirme gradiente roxo, wordmark textual PitGo, título em duas linhas e subtítulo "Encontre
   assistência para bateria, óleo, pneus e muito mais, onde você estiver.".
4. Confirme os três benefícios, textos e ordem definidos em `data-model.md`.
5. Confirme as ações Criar conta, Entrar e Sou uma empresa · Cadastrar.
6. Troque o sistema para modo escuro e reabra; o gradiente da Welcome deve permanecer igual.

### 2. Welcome responsiveness

1. Valide iPhone compacto e iPad, portrait e landscape.
2. Repita com Dynamic Type nos tamanhos maiores (Ajustes → Acessibilidade → Texto Maior).
3. Role do wordmark até o último botão.
4. Confirme ausência de corte, sobreposição, altura fixa problemática e controles atrás das safe
   areas.

### 3. Welcome actions and navigation

1. Toque Criar conta e Cadastrar empresa; confirme feedback visual e permanência na Welcome.
2. Toque Entrar rapidamente várias vezes.
3. Confirme uma única Home apresentada.
4. Use o gesto de voltar/borda uma vez; confirme retorno à mesma Welcome.
5. Toque Entrar novamente; confirme que uma nova entrada válida continua funcionando.

### 4. Home demonstrative content

1. Entre na Home e confirme "Olá,", "Rafael 👋" e avatar R.
2. Confirme BMW 320i M Sport, `2020 · PGO-2A20`, ícone de veículo e endereço exato.
3. Confirme o título principal e o card "Não sei o que aconteceu".
4. Confirme os seis serviços, ordem e valores exatos definidos em `data-model.md`.

### 5. Grid and fixed bottom tab bar

1. Confirme exatamente duas colunas em iPhone portrait e landscape.
2. Role até Carro não liga; o card inteiro deve ficar acima da `TabView`.
3. Confirme Início, Serviços, Garagem, Atendimentos e Perfil na barra, com Início selecionado.
4. Toque cada item inferior; confirme que trocar de aba não quebra o app (mesmo sem conteúdo
   funcional nas demais nesta feature) e que voltar a Início preserva o estado.

### 6. Home interactions

1. Toque o card de diagnóstico e cada serviço.
2. Confirme feedback visual em todos.
3. Confirme que nenhum toque muda o conteúdo ou o destino.

### 7. Home Light/Dark and scalable content

1. Em modo claro, confirme fundo `#FAF9FD`, textos e contraste conforme o design system.
2. Em modo escuro, confirme fundo/superfícies próximos ao preto e roxo de destaque.
3. Verifique avatar, veículo, diagnóstico, serviços e barra inferior nos dois modos.
4. Repita a grade em Dynamic Type grande; nomes e preços podem quebrar linha, mas não truncar,
   sobrepor ou reduzir dinamicamente.
5. Verifique especialmente "Atendimentos" em larguras compactas e texto ampliado.

### 8. Accessibility

1. Ative o VoiceOver.
2. Confirme ordem de foco: cabeçalho, contexto, diagnóstico, serviços e barra inferior.
3. Confirme um único foco por card, nome/finalidade completos e ação disponível.
4. Confirme que "Início" é anunciado como aba selecionada.
5. Confirme alvos confortáveis (44×44pt) e acionamento por toque duplo do VoiceOver.
6. Confirme que ícones decorativos não repetem anúncios e que informação não depende apenas de cor.

### 9. Offline and scope

1. Ative o modo avião.
2. Reabra e percorra Welcome → Home.
3. Confirme que todo conteúdo e todas as interações continuam disponíveis.
4. Confirme ausência de solicitação de login, localização ou dados pessoais.
5. Confirme ausência de destinos funcionais de cadastro, prestadores, diagnóstico, serviços,
   garagem, atendimentos ou perfil.

## Scope confirmation

A validação termina na Home demonstrativa. Não são esperados autenticação, cadastro, prestadores,
diagnóstico funcional, contratação, localização, rede, persistência ou navegação inferior
funcional além de Início. Nenhum teste unitário, de UI ou integração é criado por esta feature.
