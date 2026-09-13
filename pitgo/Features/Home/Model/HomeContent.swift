//
//  HomeContent.swift
//  pitgo
//
//  Conteúdo exclusivo da Home. A Home usa o `AccountSnapshot` autorizado (ver data-model.md de
//  `006`) e, desde `009`, o catálogo real (`list_home_services()`) em vez do `DemoServiceCatalog`
//  (`003`).
//

import Foundation

struct DiagnosticPrompt {
    let title: LocalizedStringResource
    let description: LocalizedStringResource
    let symbolName: String
}

enum HomeFailureReason {
    case offline
    case unknown
}

enum HomeUiState {
    case loading
    case content(AccountSnapshot, services: LoadState<[HomeServiceListing]>)
    case noVehicle(Profile, services: LoadState<[HomeServiceListing]>)
    case failure(HomeFailureReason)
}
