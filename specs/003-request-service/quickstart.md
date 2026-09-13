# Quickstart Validation: Solicitar Atendimento (iOS)

## Prerequisites

- Xcode estável mais recente, SDK iOS 17+ instalado.
- Simulador ou dispositivo iOS 17+ para validação manual.
- Implementação concluída conforme [plan.md](plan.md), [data-model.md](data-model.md) e
  [request-service-navigation.md](contracts/request-service-navigation.md).

## Build and static validation

```bash
xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'platform=iOS Simulator,name=iPhone 16' clean build
```

Resultado esperado: `** BUILD SUCCEEDED **`, nenhum Swift Package ou arquivo de teste novo. O
catálogo compartilhado contém seis casos únicos e os preços definidos em `data-model.md`.

## Install and launch

```bash
xcrun simctl boot "iPhone 16" 2>/dev/null
xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath build install
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/pitgo.app
xcrun simctl launch booted com.trustarx.pitgo
open -a Simulator
```

Entre pela Welcome para alcançar a Home.

## Manual scenarios

### 1. Home → RequestService para os seis serviços

Para cada linha, volte à Home, toque o card e confira título, nome, ícone e estimativa:

| Home card | Expected estimate |
|---|---:|
| Bateria | R$ 320 |
| Troca de óleo | R$ 220 |
| Pneus | R$ 180 |
| Luz no painel | R$ 150 |
| Pequenos reparos | R$ 260 |
| Carro não liga | R$ 280 |

Confirme que nenhum nome/preço de uma seleção anterior permanece na tela e que toques rápidos no
mesmo card criam somente um destino no topo.

### 2. Conteúdo inicial

1. Abra Bateria.
2. Confirme o título "Solicitar atendimento" e a ação Voltar.
3. Confirme Serviço/Bateria, veículo `BMW 320i M Sport · 2020`, endereço
   `Av. Paulista, 1500 · São Paulo`, chegada `20-40 min` e estimativa `R$ 320`.
4. Confirme o campo opcional, PIX selecionado, CTA "SOLICITAR PITTECH" e o aviso completo.
5. Confirme fundo, superfícies, bordas, roxo, tipografia e espaçamento coerentes com a Home.

### 3. Descrição e teclado

1. Foque o campo e confirme label "Descreva o problema (opcional)" e placeholder solicitado.
2. Digite quatro ou mais linhas, use Enter e edite o início/fim do texto.
3. Confirme que o conteúdo permanece visível/editável e que o campo cresce ou rola sem corte.
4. Abra e feche o teclado; role até pagamentos, CTA e aviso.
5. Apague todo o texto e confirme que o CTA continua habilitado enquanto o status é `.ready`.

### 4. Pagamento exclusivo

1. Confirme PIX como única opção inicial.
2. Selecione Crédito, Débito e PIX sucessivamente, inclusive com toques rápidos.
3. Após cada toque, confirme exatamente uma opção selecionada.
4. Confirme borda/fundo/texto roxos e check na selecionada; as demais permanecem neutras.
5. Com VoiceOver, confirme grupo de seleção, nome de cada opção e anúncio do estado selecionado.

### 5. Ação simulada e proteção contra repetição

1. Com qualquer descrição e pagamento, toque "SOLICITAR PITTECH" várias vezes rapidamente.
2. Confirme feedback no primeiro toque, uma única execução do callback mock e CTA desabilitado.
3. Confirme ausência de tela de confirmação, atendimento real, busca de PitTech, cobrança,
   solicitação de localização, rede ou notificação.
4. Volte à Home, reabra o serviço e confirme uma nova instância em estado `.ready` com PIX inicial.

### 6. Back stack e serviço inválido

1. Abra um serviço e use o botão Voltar; confirme retorno à mesma Home.
2. Abra novamente e use o gesto de borda; confirme o mesmo resultado.
3. Por revisão de código, confirme que `PitGoRoute.requestService(serviceID: nil)` resolve para
   `.invalidService` (não há caminho de execução manual para "ID desconhecido" — ver
   `contracts/request-service-navigation.md`).
4. Confirme `.invalidService`: mensagem compreensível, ação Voltar, nenhum serviço/preço/formulário
   e retorno seguro à Home.

### 7. Barra de abas fixa

1. Role do topo até o aviso final; a `TabView` permanece fixa e nenhum conteúdo fica atrás dela.
2. Confirme Início, Serviços, Garagem, Atendimentos e Perfil, com Início selecionado.
3. Toque cada aba: confirme que a navegação para RequestService fica preservada ao voltar para
   Início, igual ao comportamento atual da Home.

### 8. Responsividade, tema e safe areas

1. Valide iPhone compacto e iPad, portrait e landscape.
2. Repita com Dynamic Type nos tamanhos maiores.
3. Confirme textos completos, cards sem sobreposição e estimativas lado a lado quando couberem ou
   empilhadas quando necessário (`ViewThatFits`).
4. Confirme as três opções de pagamento alcançáveis e o CTA/aviso acima da `TabView`.
5. Valide modo claro e escuro; confirme papéis semânticos do tema e contraste apropriado.

### 9. Acessibilidade

1. Ative o VoiceOver e percorra barra de navegação, cards, descrição, estimativas, pagamento, CTA,
   aviso e barra de abas na ordem visual.
2. Confirme headings, rótulos completos, ação Voltar, serviço/preço e pagamento selecionado.
3. Confirme um único foco por controle/card quando o ícone for decorativo.
4. Confirme alvos de pelo menos 44×44pt e que nenhuma informação depende somente de cor.

### 10. Offline e escopo

1. Ative o modo avião.
2. Percorra Welcome → Home → RequestService, edite o formulário e acione o CTA.
3. Confirme que conteúdo e interações continuam disponíveis e nenhuma permissão é solicitada.
4. Confirme ausência de backend, Supabase, pagamento real, localização, distância, chegada real,
   persistência, cobrança, push ou atualização em tempo real.

## Scope confirmation

A validação termina no callback local mock. Não são esperados atendimento persistido, confirmação,
prestador, pagamento, geolocalização, rede, destinos de abas funcionais ou testes automatizados.
