# Quickstart Validation: Catálogo de Serviços na Homepage (iOS)

## Prerequisites

- Xcode estável mais recente instalado, com o SDK de iOS 17+ baixado (Settings → Platforms).
- Simulador iOS 17+ (ex.: iPhone 16) ou dispositivo físico com iOS 17+ para validação manual.
- Implementação concluída conforme [plan.md](plan.md), [data-model.md](data-model.md) e
  [home-navigation.md](contracts/home-navigation.md).

## Build and static validation

Na raiz do projeto iOS:

```bash
xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'platform=iOS Simulator,name=iPhone 16' clean build
```

Resultado esperado:

- `** BUILD SUCCEEDED **`.
- Nenhum warning de concorrência estrita do Swift 6 bloqueando o build.
- Nenhuma referência remanescente ao `ContentView` padrão do template ("Hello, world").

## Install and launch (simulador)

```bash
xcrun simctl boot "iPhone 16" 2>/dev/null
xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath build install
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/pitgo.app
xcrun simctl launch booted com.trustarx.pitgo
open -a Simulator
```

## Manual scenarios

### 1. Offline catalog

1. No simulador, ative o modo avião (ou desligue a rede do Mac, se testando em dispositivo físico).
2. Abra o PitGo.
3. Confirme conteúdo útil em até 2 segundos.
4. Confirme, nesta ordem: Borracharia, Eletricista veicular, Bateria, Troca de pneu e Mecânico.

### 2. Responsive layout

1. Valide em iPhone compacto (ex.: iPhone SE) e iPhone grande (ex.: iPhone 16 Pro Max), portrait e
   landscape.
2. Valide em iPad, em tela cheia e em Split View/Slide Over.
3. Confirme que a quantidade de colunas do `LazyVGrid` se adapta sem cortes, sobreposição ou espaço
   inacessível.
4. Role até o último item quando necessário.

### 3. Dynamic Type and themes

1. Valide com o tamanho de fonte padrão e com o maior tamanho de Dynamic Type (Ajustes →
   Acessibilidade → Texto Maior → Tamanhos de Texto Maiores, no máximo).
2. Confirme nomes completos, inclusive "Eletricista veicular", sem sobreposição.
3. Valide Aparência Clara e Escura seguindo primeiro a configuração do sistema.
4. Confirme contraste e identificação dos cards sem depender apenas de cor.

### 4. Accessibility

1. Ative o VoiceOver (Ajustes → Acessibilidade → VoiceOver, ou tripla-toque no botão lateral se
   configurado).
2. Confirme um único foco de VoiceOver por card.
3. Confirme que cada foco anuncia categoria, finalidade de buscar prestadores e ação disponível.
4. Confirme alvo de toque confortável (mínimo 44×44pt) e acionamento por VoiceOver (toque duplo).

### 5. Selection and duplicate protection

1. Toque uma vez em cada categoria, voltando à Home entre tentativas.
2. Confirme que o destino "Busca de prestadores" mostra a categoria correta.
3. Toque rapidamente várias vezes no mesmo card.
4. Confirme apenas uma entrada na `NavigationPath` e apenas uma ação de voltar (botão ou gesto de
   borda) para retornar.

### 6. Back behavior and state restoration

1. Role a grade antes de selecionar uma categoria.
2. Entre no destino da categoria.
3. Use o botão de voltar do `NavigationStack` ou o gesto de borda (swipe back).
4. Confirme retorno à Home sem segunda instância e com posição de rolagem preservada.

### 7. Invalid internal argument

1. `ServiceCategoryID` é um `enum` — um valor fora da tabela do contrato é irrepresentável em
   tempo de compilação, então não há caminho de execução real para testar manualmente aqui (isso
   substitui, com mais garantia, o teste equivalente do Android que validava uma string inválida).
2. Confirme, por revisão de código, que `PitGoRoute.providerSearch(categoryID:)` só aceita
   `ServiceCategoryID`, nunca uma `String` bruta.

## Scope confirmation

A validação termina quando a categoria correta chega ao destino de entrada e o retorno funciona.
Não são esperados prestadores reais, rede, localização, autenticação, solicitação ou pagamento.
Nenhum teste unitário, de UI ou integração é criado por esta feature sem pedido explícito.
