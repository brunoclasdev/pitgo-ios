# Validação do porte iOS — 029

- Build `pitgo` para `generic/platform=iOS Simulator`: **BUILD SUCCEEDED** com Xcode 17F42.
- Build Homol `pitgo-Homol` e Prod `pitgo-Prod` para simulador: **BUILD SUCCEEDED**.
- O build Dev também passou após adicionar histórico paginado, estados de localização e retorno automático da view de Guincho.
- O stream de publicação existente desperta a consulta enquanto localização em background está ativa; tocar na notificação leva à reconsulta autenticada do despacho.
- Revisão manual ainda pendente. Precisa de duas contas reais para validar oferta paga, resposta, rota de tracking, permissão/GPS, card sobre outras telas e notificação em aparelho real.
- A Home preserva perfil/conta e disponibilidade e agora oferece histórico paginado pela RPC compartilhada.
- Sem testes automatizados novos, conforme instrução da spec Android de origem.
