# Plano de porte iOS: alerta e Home do guincheiro

Fonte funcional: `../android/pitgo/specs/029-guincho-alerta-home/` (spec validada nos commits Android `147339d` e posteriores). O contrato exige uma oferta `GUINCHO_DIRECT` autorizada pelo snapshot do servidor, card global sem troca de rota, resposta única e Home móvel com localização real.

## Estado encontrado no iOS

- `ProviderDashboardViewModel` já mantém polling de cinco segundos e assinatura privada para `get_my_active_mobile_dispatch()`.
- A tela de solicitação `ProviderIncomingRequestView` já responde usando `allowedActions` e `revision` do snapshot.
- `DeviceLocationRepository` já fornece fix pontual e stream de alta precisão; `PitGoMapView` já renderiza MapLibre e marcadores.
- O perfil móvel não tinha Home dedicada com mapa. Uma oferta Guincho PENDING era encaminhada para a tela de solicitação, impedindo o card global sobre a rota atual.
- iOS não tem o serviço foreground Android. Notificação em background precisa respeitar o ciclo de localização/execução do iOS e não pode prometer entrega depois que o sistema suspender o app.

## Sequência de implementação

1. Apresentar a oferta paga GUINCHO_DIRECT em card global com prazo e ações do snapshot. Preservar revalidação, revisão, sessão e navegação.
2. Criar Home do prestador móvel com mapa, marcador atual, controles de localização e acesso ao perfil/histórico.
3. Adicionar deduplicação e notificação genérica em background dentro das capacidades de execução iOS, abrir e validar pedido vigente ao tocar.
4. Completar retomada, limpeza na troca de sessão e cobertura/documentação de acessibilidade.

Sem migration ou dependência nova: o backend e os contratos de despacho são compartilhados com Android.
