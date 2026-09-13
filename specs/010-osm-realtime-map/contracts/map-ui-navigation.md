# Contract: Map UI and Navigation (iOS)

## Discovery route

```swift
struct ServiceMapView: View {
    let serviceID: UUID
    let onBack: () -> Void
    let onRequestService: (_ providerID: UUID, _ serviceID: UUID) -> Void
    let onSessionExpired: () -> Void
}
```

- `serviceID` é `UUID` opaco validado antes do RPC;
- a View não recebe nome, preço, categoria, owner ou coordenadas;
- o Repository chama `discover_service_providers` (já existente) e rejeita coordenadas inválidas;
- o cadastro empresarial (`007`/`009`) não instancia MapLibre nem apresenta mapa.

## Public result

A UI recebe somente `providerID`, nome público, modalidade, coordenada do endereço, distância e
estimativa. CNPJ, contato e localização móvel privada são proibidos.

## Map/list parity

- Mapa e Lista usam a mesma coleção e seleção;
- a lista contém 100% dos resultados, inclusive clusters/grupos coincidentes;
- recusa de localização preserva a busca por viewport/região manual;
- a `MLNMapView` é uma região semântica; lista/sheet são as superfícies VoiceOver autoritativas.

## GeoJSON interaction

- a source de providers agrupa pontos próximos até `maximumZoomLevelForClustering`;
- coordenadas exatamente iguais são pré-agrupadas por `groupKey` estável;
- o toque consulta apenas as layers da própria app (`mapView(_:didSelect:)`) numa área equivalente a
  um alvo `>=44×44pt`;
- um provider individual abre o resumo SwiftUI;
- um cluster próximo centraliza e aumenta o zoom; não usa APIs de "leaves"/expansão sobre uma source
  mutável (evita corrida entre leitura assíncrona e atualização da source);
- um grupo coincidente abre uma lista SwiftUI com todos os IDs;
- nenhum provider é removido do modelo por clustering.

## Provider summary and request

O resumo mostra nome, modalidade localizada, distância/estimativa e o CTA "SOLICITAR ATENDIMENTO",
sem dados privados. Em largura compacta usa `.sheet` rolável; em largura expandida (`iPad`/landscape)
pode usar um painel lateral.

O CTA navega somente com IDs:

```swift
PitGoRoute.requestService(serviceID: UUID, providerID: UUID)
```

IDs são `UUID` nativos (sem necessidade de URI-encoding manual, diferente de uma rota baseada em
string). `RequestServiceView` (`003`) carrega o serviço do catálogo real, preserva `providerID` no
callback mockado e mostra um estado inválido sem cair de volta para um serviço demo quando
necessário.

## Discovery states

| Estado | UI | Recuperação |
|---|---|---|
| Data Loading | progresso; resultado anterior pode permanecer | aguardar/voltar |
| Ready | mapa/lista/contagem | buscar nesta área |
| Empty | nenhum provider | alterar região |
| Offline | banner e lista/cache anterior | retry/ver lista |
| Data Failure | mensagem genérica | retry |
| Style Failed | lista e seleção preservadas | recarregar mapa |
| Resource Degraded | mapa possível + banner | retry/ver lista |
| Location Denied | explicação sem bloqueio | região/settings |
| Session Expired | limpa dados privados | gate central |

Um `searchGeneration` (token incremental) impede que a resposta de uma busca anterior sobrescreva o
viewport/serviço atual.

## Appointment tracking

```swift
struct AppointmentTrackingView: View {
    let appointmentID: UUID
    let onBack: () -> Void
    let onSessionExpired: () -> Void
}
```

- View filha com barra de navegação e sem `TabView`;
- uma `MLNShapeSource` não clusterizada e um marcador estável;
- uma nova posição aceita atualiza somente a source;
- a câmera só acompanha enquanto "Seguir prestador" estiver ativo;
- ao vivo: `Ao vivo · Atualizado às HH:mm:ss`;
- desatualizado: mantém o marcador e mostra `Localização desatualizada · Última atualização às
  HH:mm:ss`;
- falha de tile/estilo não apaga a posição nem o texto;
- `Ended`/expiração de sessão remove imediatamente a feature privada.

## Responsive/accessibility

- controles `>=44×44pt` e CTA `>=56pt`;
- Dynamic Type grande força painel único, sem altura fixa;
- texto quebra linha e o sheet é rolável;
- seleção/live/stale usam forma, ícone e texto além de cor;
- a atribuição permanece visível/tocável;
- atualizações de 10s não geram anúncios repetitivos de VoiceOver.
