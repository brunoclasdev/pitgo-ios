//
//  ServiceCatalogModels.swift
//  pitgo
//
//  Mapeia `list_home_services()` (já existente e compartilhada, ver
//  contracts/account-provider-database.md "Catalog" de `009`). Não expõe nenhum dado de Provider —
//  apenas o catálogo real que substitui `DemoServiceCatalog` (`003`) na Home.
//
//  NOTA: o contrato descreve o retorno apenas semanticamente ("UUID real de serviço, UUID/nome de
//  categoria, nome/descrição do serviço e preço mínimo de oferta ativa opcional"), sem fixar as
//  chaves JSON exatas — as chaves abaixo seguem a convenção `snake_case` já usada por todas as
//  outras RPCs deste projeto (`service_id`, `category_id`, etc.). Não há como confirmar contra o
//  projeto Supabase real nesta sessão (sem credenciais); ver tasks.md.
//

import Foundation

/// Distingue como o catálogo é despachado (`013` — data-model.md "Extensão de catálogo"). O iOS
/// nunca decide pelo nome do serviço, somente por este campo e pelo UUID.
enum ServiceDispatchKind: String, Decodable, Hashable {
    case browse = "BROWSE"
    case mobileSequential = "MOBILE_SEQUENTIAL"
    /// PitTec sob demanda (`015`) — despacho automático por proximidade, sem escolha manual de
    /// prestador, preço definido centralmente pela plataforma (`016`).
    case pittecAutoSequential = "PITTEC_AUTO_SEQUENTIAL"
}

/// Resultado de localizar o serviço único implícito de uma modalidade de cadastro (`016` — Móvel/
/// PitTec não escolhem serviço manualmente). Não é uma entidade persistida.
enum ImplicitServiceResolution {
    case found(CatalogService)
    /// Catálogo sem nenhum serviço ativo para esse `dispatchKind` — cadastro bloqueado.
    case missing
    /// Catálogo com mais de um serviço ativo para o mesmo `dispatchKind` — estado inconsistente;
    /// o client nunca adivinha qual usar.
    case duplicated
}

struct HomeServiceListing: Decodable, Identifiable, Hashable {
    let serviceID: UUID
    let serviceName: String
    let serviceDescription: String?
    let categoryName: String
    let minimumPrice: Decimal?
    let dispatchKind: ServiceDispatchKind

    var id: UUID { serviceID }

    // IMPORTANTE (`013`): `list_home_services()` retorna as colunas `(service_id, name,
    // description, category_name, minimum_price, dispatch_kind)` — confirmado via
    // `pg_get_functiondef` no projeto Supabase compartilhado nesta sessão. As chaves anteriores
    // (`service_name`/`service_description`/`category_id`, este último inexistente na RPC) faziam
    // toda linha falhar a decodificação silenciosamente, derrubando a Home para `.failure` sempre
    // que havia ao menos um serviço — corrigido aqui.
    enum CodingKeys: String, CodingKey {
        case serviceID = "service_id"
        case serviceName = "name"
        case serviceDescription = "description"
        case categoryName = "category_name"
        case minimumPrice = "minimum_price"
        case dispatchKind = "dispatch_kind"
    }
}
