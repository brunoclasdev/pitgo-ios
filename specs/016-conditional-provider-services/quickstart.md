# Quickstart: validar a seleção de serviços condicionada à modalidade (iOS)

## Pré-requisitos

- Xcode estável mais recente, SDK iOS 17+, simulador/dispositivo iOS 17+.
- O mesmo projeto Supabase de desenvolvimento já usado para `007`/`009`/`013`/`015`, com os serviços
  "Guincho" (`dispatch_kind = MOBILE_SEQUENTIAL`) e "PitTec" (`dispatch_kind =
  PITTEC_AUTO_SEQUENTIAL`) já ativos e únicos no catálogo, mais ao menos uma categoria/serviço
  `BROWSE` para testar Fixo.

## 1. Build

```bash
xcodebuild -project pitgo.xcodeproj -scheme pitgo \
  -destination 'platform=iOS Simulator,name=iPhone 16' clean build
```

Esperado: build sucede sem dependência nova.

## 2. Prestador Fixo escolhe seus serviços (US1)

1. Inicie o cadastro de empresa e selecione a modalidade Fixo.
2. Tente enviar sem escolher nenhum serviço: confirme bloqueio com a mensagem já existente de "pelo
   menos um serviço obrigatório".
3. Escolha uma categoria, um serviço e informe preço/duração válidos: confirme que o cadastro é
   aceito com esse serviço associado.
4. Adicione mais de um serviço: confirme que todos são salvos como ofertas do prestador.

## 3. Prestador Guincho não escolhe serviço (US2)

1. Selecione a modalidade Móvel.
2. Confirme que nenhuma seleção de categoria/serviço é exibida na etapa onde antes existia.
3. Preencha empresa, endereço e verificação de localização (`009`) e informe preço/duração para o
   Guincho.
4. Envie o cadastro: confirme que é aceito sem nenhuma ação relacionada a serviços além de preço/
   duração.
5. Como cliente, abra a Home: confirme que o novo prestador é contabilizado no card de Guincho.

## 4. Prestador PitTec não escolhe serviço nem preço (US3)

1. Selecione a modalidade PitTec.
2. Confirme que nenhuma tela de seleção de serviço, preço ou duração é exibida.
3. Preencha empresa, endereço e verificação de localização e envie o cadastro: confirme aceitação
   sem nenhuma etapa relacionada a serviço/preço/duração.
4. Como cliente, abra o card PitTec: confirme que o prestador recém-cadastrado é elegível para
   aparecer no mapa de descoberta (`015`), sem preço algum definido por ele.

## 5. Troca de modalidade durante o preenchimento

1. Com Fixo selecionado, escolha um ou mais serviços; troque para Móvel: confirme que as escolhas
   anteriores são descartadas e a oferta implícita do Guincho é montada automaticamente.
2. Volte para Fixo: confirme que a etapa de escolha de serviço reaparece e volta a ser obrigatória
   antes do envio.

## 6. Catálogo inconsistente

1. Simule (via fixture administrativa) a ausência do serviço "Guincho"/"PitTec" ativo e único no
   catálogo.
2. Tente cadastrar um prestador Móvel/PitTec: confirme falha compreensível ("catálogo alterado"),
   sem criar um prestador sem serviço associado.

## 7. Escopo

Confirme que a troca de modalidade feita depois do cadastro, no Dashboard do prestador (`009`/
`013`/`015`), não é afetada por esta feature — permanece fora de escopo aqui.
