# Contract: Navigation and role-aware session (iOS)

## Central routes

| Route | Access | Entry/exit |
|---|---|---|
| `UnauthenticatedRoute.providerSignUp` | público, sem sessão | CTA de empresa na Welcome; sucesso atualiza a sessão |
| `PitGoRoute.providerRegistration` (raiz autenticada) | PROVIDER Onboarding | retomado após signup/login; sucesso substitui pelo dashboard |
| `PitGoRoute.providerDashboard` (raiz autenticada) | PROVIDER Ready | home do papel; possui modalidade/disponibilidade/logout |
| `PitGoRoute.providerMigrationStart` | CLIENT com flag legada | inicia prova, depois troca intencional de conta |
| `PitGoRoute.providerMigrationClaim` | PROVIDER Onboarding + desafio em memória | reivindica/repara empresa legada |
| `PitGoRoute.serviceMap(serviceID:)` | CLIENT | card real de serviço da Home; voltar retorna à Home |
| `PitGoRoute.appointmentTracking(appointmentID:)` | CLIENT participante | marcador privado, sem `TabView` |
| `PitGoRoute.providerAppointmentTracking(appointmentID:)` | PROVIDER participante | inicia/para o tracking elegível |

Rotas contêm somente nomes de destino allowlisted e UUIDs opacos de serviço/atendimento. Nunca
contêm papel, ID de owner de usuário/provider, coordenadas, endereço, token, e-mail ou documento. Os
builders centralizados de rota (`PitGoRoute`/`UnauthenticatedRoute`, `enum Hashable`) validam a forma
do UUID; Repositories permanecem autoritativos.

## Session destination matrix

```text
.unauthenticated                          -> Welcome/rotas públicas
.authenticatedClient(.ready)               -> Home do cliente (TabView)
.authenticatedProviderOnboarding           -> Provider Registration
.authenticatedProviderReady                -> Provider Dashboard
.offlineVerification/.blocked/inconsistente -> SessionGateView
```

A rota atual é reavaliada sempre que `AppSessionState` muda (o `PitGoRootView` observa
`SessionStore` diretamente). Uma conta CLIENT tentando uma rota de provider ou uma PROVIDER tentando
uma rota de cliente é redirecionada para sua própria raiz; nunca vê uma tela parcial. A presença de
provider legado não muda o destino de uma conta CLIENT.

Login é único: credenciais são enviadas uma vez, então `get_my_account_context()` determina o
destino. A UI nunca pede que a pessoa declare um papel no login e nunca cai para um padrão quando o
contexto está ausente/ambíguo.

## Signup stacks

Cliente:

```text
Welcome -> Client SignUp (005) -> onboarding de veículo (006)/Home
```

Empresa:

```text
Welcome -> Provider SignUp -> Provider Registration -> Provider Dashboard
```

A criação de Auth do provider pode estar completa enquanto o cadastro fica pendente. Voltar/reiniciar/
logar novamente retoma Provider Registration. Após o cadastro, a `NavigationStack` não autenticada
inteira é descartada (mesma troca de `RootPhase` de `005`/`006`) — Voltar do sistema não pode revelar
credenciais/rascunho.

O caminho `SignUpOrigin.provider` (introduzido em `007`) é removido — o CTA de empresa nunca mais
chama o SignUp de cliente nem trava o tipo de pessoa.

## Assisted migration stack

```text
Aba Perfil -> Migration Start -> logout intencional
 -> Provider SignUp/Login -> Migration Claim -> Provider Dashboard
```

O desafio em texto plano existe somente num coordinator com escopo de processo
(`ProviderMigrationCoordinator`, `@Observable`) por no máximo 15 minutos. O logout intencional usado
entre as provas precisa parar todo trabalho de localização, mas pode reter esse único desafio de
migração. Encerramento do processo o limpa e exige reiniciar a partir da sessão CLIENT original. Ele
nunca é colocado em `UserDefaults`, `Keychain`, rota, analytics ou log.

## Tracking cleanup

Antes de limpar uma sessão autenticada, o `SessionStore` sinaliza ao controller de tracking para
parar `CLLocationManager`/canal Realtime/`Task`s e faz uma tentativa best-effort de RPC de parada. A
navegação então limpa os ViewModels específicos do papel e substitui a pilha por Welcome. Resultados
tardios carregam o `userID` esperado e são descartados após troca de conta.

## UI shells

- O mapa de descoberta de serviço mantém a `TabView` do cliente com Início selecionada; safe areas
  protegem controles do mapa e a lista.
- Provider Registration/Dashboard usam a experiência de provider e nunca renderizam a `TabView` do
  cliente.
- Acompanhamento de atendimento é uma `View` filha focada com barra de navegação/voltar e sem
  `TabView`.
- O mapa sempre tem uma representação equivalente `Mapa | Lista`; landscape expandido pode renderizar
  ambos, larguras compactas/fonte ampliada renderizam um modo por vez.
