//
//  RequestServiceContent.swift
//  pitgo
//
//  Estado da tela de solicitação — carregada por `serviceID` real do catálogo (nunca o catálogo demo
//  de `003`). `providerID` é preservado apenas para o callback mockado de confirmação; nunca exibido
//  na interface (contracts/map-ui-navigation.md "Provider summary and request").
//

import Foundation

struct RequestServiceContent: Equatable {
    let serviceID: UUID
    let providerID: UUID
    let serviceName: String
    let categoryName: String
    let description: String?
    let minimumPrice: Decimal?
}

enum RequestServiceUiState: Equatable {
    case loading
    case content(RequestServiceContent)
    /// `serviceID` não corresponde a nenhum serviço ativo do catálogo real — nunca cai para um
    /// serviço demo (ver plan.md "Bateria/preço demo").
    case invalid
    case failure
    case confirmed(RequestServiceContent)
}
