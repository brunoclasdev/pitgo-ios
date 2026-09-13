# Data Model: Corrigir cadastro de veículos e erros por campo (iOS)

## Vehicle (backend compartilhado, inalterado)

Mesmo schema de `public.vehicles` já documentado em `006 data-model.md` — `id`, `user_id` (derivado
de `auth.uid()`), `brand`/`model` obrigatórios, demais campos opcionais, `is_primary`/`active`
controlados pelo servidor. Nenhuma coluna nova.

### Relacionamentos e invariantes (inalterados)

- Uma conta cliente possui zero ou mais `Vehicle`.
- Um `Vehicle` pertence a exatamente uma conta e nunca troca de proprietário nesta feature.
- Quando há ao menos um veículo ativo, exatamente um pode estar principal após uma criação/troca
  concluída.
- Placa, Renavam e chassi são únicos globalmente quando presentes; múltiplos `nil` são permitidos.
- Veículo principal precisa estar ativo.

## ClientAccount (backend compartilhado, inalterado)

Contexto autenticado autorizado a operar veículos: `userID` de `auth.uid()`, `accountType` deve ser
`CLIENT` (`account_roles`), `profileActive` deve ser `true`. Uma conta `PROVIDER`, sessão ausente ou
cliente sem perfil ativo não pode criar nem selecionar veículo.

### Projeção do principal na sessão

```swift
// SessionStore (006), atualização restrita:
func applyAuthoritativePrimaryVehicle(_ vehicle: Vehicle) {
    guard case .authenticatedClient(var snapshot) = state,
          vehicle.userID == snapshot.userID,
          vehicle.active,
          vehicle.isPrimary
    else { return }
    snapshot.primaryVehicle = vehicle
    state = .authenticatedClient(snapshot)
}
```

`AccountSnapshot.primaryVehicle` só pode ser atualizado em memória com o `Vehicle` retornado pela
RPC e somente quando `vehicle.userID` coincide com a conta atual, `active == true` e
`isPrimary == true`. Rascunhos e IDs informados pela UI nunca alteram essa projeção. A próxima carga
remota permanece a autoridade definitiva.

## VehicleFormDraft (client iOS)

Estado textual, somente em memória, usado enquanto a pessoa preenche o formulário (`006`, sem
mudança de forma nesta feature — apenas correções de comportamento):

- contém os treze campos visíveis e `makePrimary`;
- valores textuais não são aparados durante a digitação, exceto a formatação visual de placa/
  Renavam/chassi (mesma abordagem "ao editar" de `005 §9`);
- na submissão, produz `VehicleDraft` normalizado somente quando não há erros;
- não contém `userID`, `vehicleID`, `active` nem timestamps;
- não é persistido em `UserDefaults`/`SwiftData`.

## VehicleDraft

Payload normalizado enviado à RPC (inalterado desde `006`): `brand`/`model` não vazios; opcionais
textuais `String?` nunca vazios; anos e quilometragem `Int?` já validados; `makePrimary: Bool`
(`false` também é válido para o primeiro veículo — o banco detecta que é o primeiro e força
`is_primary = true`); sem propriedade de ownership.

## VehicleField e VehicleFieldError (inalterados desde `006`, ordem preservada)

```swift
enum VehicleField: CaseIterable {
    case brand, model, version, manufactureYear, modelYear
    case plate, renavam, chassis, color, fuelType, transmission, engine, mileage
}

enum VehicleFieldError { case required, invalidFormat, outOfRange, unavailable }
```

| Erro | Uso |
|---|---|
| `.required` | Marca ou Modelo ausente após `trim()` |
| `.invalidFormat` | Placa, Renavam, chassi ou campo numérico textual inválido |
| `.outOfRange` | Ano fora do intervalo ou quilometragem negativa |
| `.unavailable` | Placa, Renavam ou chassi já cadastrado |

O mapa de erros (`[VehicleField: VehicleFieldError]`) pode conter vários campos ao mesmo tempo. A
primeira chave seguindo a ordem acima gera um novo `VehicleFocusRequest(field:, requestID:)`.

## VehicleFormOperation

```swift
enum VehicleFormOperation {
    case loading
    case editing
    case submitting
    case success(Vehicle)
    case failure(VehicleMutationFailureReason)
}
```

Transições: `.loading → .editing`; `.loading → .failure`; `.editing → .editing` (alteração/
validação local); `.editing → .submitting`; `.submitting → .success`; `.submitting → .editing`
(falha específica de campo); `.submitting → .failure` (geral recuperável ou `.sessionExpired`);
`.failure → .editing` (nova edição/tentativa).

- `.loading`: obtém a quantidade atual de veículos para configurar a opção de principal;
- `.editing`: permite alterações e submissão;
- `.submitting`: inputs/CTA bloqueados; toques adicionais são ignorados;
- `.failure`: mantém o rascunho em falhas recuperáveis; sessão expirada limpa o estado sensível;
- `.success`: terminal para a instância do formulário; dispara navegação uma única vez.

## VehicleMutationResult

```swift
enum VehicleMutationResult {
    case success(Vehicle)
    case fieldFailure(VehicleField, VehicleFieldError)
    case failure(VehicleMutationFailureReason)
}

enum VehicleMutationFailureReason {
    case offline, timeout, sessionExpired, rpcUnavailable
    case serviceUnavailable, vehicleUnavailable, contract, unknown
}
```

Sem `Error` bruto. Somente `.fieldFailure` altera a borda/texto de apoio de um campo.

## VehicleFormOrigin (inalterado desde `006`)

| Origem | Conclusão bem-sucedida |
|---|---|
| `.onboarding` | Resolver pendência, atualizar sessão e trocar `RootPhase` para `.home` |
| `.garage` | `path.removeLast()` para a Garagem; `.task`/`.onAppear` recarrega a lista |

A pendência de onboarding não é resolvida quando o formulário é apenas aberto — apenas após a
criação confirmada ou pela ação explícita de pular o onboarding (correção desta feature; ver
`research.md §7`).
